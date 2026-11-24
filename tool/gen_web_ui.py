#!/usr/bin/env python3
"""Extract MAIN_HTML from the original files.py, strip the converter/compressor
features and write lib/host/web_ui.dart.  Usage: gen_web_ui.py files.py"""
import re, sys, pathlib

src = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8-sig')
m = re.search(r'MAIN_HTML = r"""(.*?)"""\n', src, re.S)
html = m.group(1)

def cut(text, start, end, keep_end=True, label=''):
    i = text.index(start)
    j = text.index(end, i + len(start))
    print('cut', label or start[:40], j - i, 'chars')
    return text[:i] + (text[j:] if keep_end else text[j + len(end):])

# ---- HTML sections ---------------------------------------------------------
html = cut(html, '<!-- File picker modal -->', '<!-- Permission modal -->', label='file picker')
html = cut(html, '<!-- CONVERTER PAGE (auth required) -->', '<div id="pg-links" class="pg">', label='converter page')
html = cut(html, '<!-- COMPRESSOR PAGE -->', '</div><!-- /mainWrap -->', label='compressor page')
html = re.sub(r'\s*<button class="bn" id="bn-converter".*?</button>', '', html, flags=re.S)
html = re.sub(r'\s*<button class="bn" id="bn-compressor".*?</button>', '', html, flags=re.S)
html = re.sub(r'\s*<button id="vCV".*?</button>', '', html, count=1, flags=re.S)
html = html.replace('File Converter', 'FTP / FTPS Server')
html = html.replace('fa-wand-magic-sparkles text-pink-400', 'fa-server text-pink-400')

# ---- JavaScript sections ----------------------------------------------------
html = cut(html, '// ── FILE PICKER ──', '// ── CLIPBOARD ──', label='js file picker')
html = cut(html, '// ── CONVERTER ──', '// ── DELETE ACCOUNT ──', label='js converter+compressor')

# viewer: convert button wiring
html = re.sub(r"\n\s*document\.getElementById\('vCV'\)\.onclick=.*?;\n", '\n', html, count=1)
html = re.sub(r"\n\s*// Hide convert btn for guests\n\s*const vCVBtn=.*?\n\s*if\(vCVBtn\).*?\n", '\n', html, count=1)

# context-menu entries
for label in ("Convert", "Compress", "Image→PDF"):
    html = re.sub(r"\n\s*\{icon:'[^']*',label:'%s'.*?\},\n" % re.escape(label), '\n', html, count=1)
html = re.sub(r"\n\s*isImg\?\{icon:'fa-file-pdf'.*?:null,\n", '\n', html, count=1)

# helper functions that targeted converter / compressor
for fn in ('sendToCompressor', 'sendToConverter', 'imgToPdfQuick'):
    html = re.sub(r"function %s\(.*?\n\}\n" % fn, '', html, count=1, flags=re.S)

html = html.replace("['files','clipboard','links','converter','compressor']", "['files','clipboard','links']")
html = html.replace("{clipboard:'📋 Clipboard',converter:'⚡ Converter',links:'🔗 Links',compressor:'🗜 Compressor'}",
                    "{clipboard:'📋 Clipboard',links:'🔗 Links'}")
html = html.replace("['clipPageAvIni','convPageAvIni','linksPageAvIni','compPageAvIni']", "['clipPageAvIni','linksPageAvIni']")
html = html.replace("['clipPageAv','convPageAv','linksPageAv','compPageAv']", "['clipPageAv','linksPageAv']")
html = html.replace("['bn-clipboard','bn-links','bn-converter','bn-compressor']", "['bn-clipboard','bn-links']")
html = html.replace("closeFP();", "")
html = html.replace("#pg-files,#pg-clipboard,#pg-converter,#pg-compressor,#pg-links", "#pg-files,#pg-clipboard,#pg-links")

html = cut(html, '/* File picker */', '/* CSV table */', label='css file picker')
html = html.replace('let cvFile=null, cvFmt=null, cvMultiFiles=[];\n', '')
html = html.replace("let fpTarget='upload', fpServPath='', fpServItems=[], fpMultiImgs=[];\n", '')
html = html.replace(' Consider using the Converter instead.', '')
html = cut(html, '/* Compressor */', '.fb.on{', label='css compressor')


# --- PocketServer additions ---
PATCHES = [
    ('  // Prevent drag-drop upload\n  window._guestMode=true;\n}\n',
     '  // Prevent drag-drop upload\n  window._guestMode=true;\n  showGuestSignIn();\n}\nfunction showGuestSignIn(){\n  if(document.getElementById(\'guestSignIn\'))return;\n  var hv=document.getElementById(\'hdrAv\');if(hv)hv.style.display=\'none\';\n  var b=document.createElement(\'button\');b.id=\'guestSignIn\';\n  b.innerHTML=\'<i class="fa-solid fa-right-to-bracket"></i> Sign in\';\n  b.style.cssText=hv?\'background:#6366f1;color:#fff;border:0;border-radius:999px;padding:6px 12px;font-weight:700;font-size:13px;cursor:pointer;white-space:nowrap;flex-shrink:0\':\'position:fixed;top:12px;right:12px;z-index:650;background:#6366f1;color:#fff;border:0;border-radius:999px;padding:9px 16px;font-weight:700;font-size:14px;cursor:pointer\';\n  b.onclick=function(){var aw=document.getElementById(\'authWall\');if(aw){aw.classList.remove(\'gone\');aw.style.display=\'\';aw.style.pointerEvents=\'\';}};\n  if(hv&&hv.parentNode)hv.parentNode.insertBefore(b,hv);else document.body.appendChild(b);\n}\n'),
    ('function setUser(username, avatarB64){\n  curUser=username;isGuest=false;',
     'function setUser(username, avatarB64){\n  if(window._guestMode){location.reload();return;}\n  curUser=username;isGuest=false;'),
]
for _a, _b in PATCHES:
    assert html.count(_a) == 1, _a[:40]
    html = html.replace(_a, _b)

# fail loudly if anything removed is still referenced
bad = [w for w in ('openFP', 'fpModal', 'cvFile', 'cmpFile', 'runConv', 'runCompress', 'sendToConverter',
                   'sendToCompressor', 'imgToPdfQuick', 'pg-converter', 'pg-compressor', 'vCV') if w in html]
if bad:
    sys.exit('leftover references: %s' % bad)
assert "'''" not in html

out = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else 'lib/host/web_ui.dart')
out.write_text("// GENERATED by tool/gen_web_ui.py from the original files.py UI. Do not edit by hand.\n"
               "const String kWebUiHtml = r'''" + html + "''';\n", encoding='utf-8')
print('wrote', out, len(html), 'chars')

# Arabic for the web page, then make the script run on old TV browsers (needs node)
import subprocess
subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name('web_i18n.py'))], check=True)
subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name('transpile_web_ui.py'))], check=True)
