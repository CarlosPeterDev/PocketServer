#!/usr/bin/env python3
"""Make the embedded web UI script run on old TV browsers (LG webOS 4/5, Samsung Tizen: Chromium 53-79).

The UI was written for modern phone browsers and uses syntax such as `a?.b`, `catch {}` and object spread.
An old browser fails to *parse* the script, so none of the buttons work. This rewrites the main inline
<script> of lib/host/web_ui.dart with esbuild (target chrome53), adds tiny polyfills and an on-screen error
banner. Needs node (npx esbuild). Idempotent. Usage: tool/transpile_web_ui.py"""
import pathlib, re, subprocess, sys

P = pathlib.Path(__file__).resolve().parent.parent / 'lib/host/web_ui.dart'
MARK = '/*ps-es2015*/'

PRELUDE = r"""/*ps-es2015*/
(function(){
  var o=Object, A=Array.prototype, S=String.prototype;
  if(!o.entries)o.entries=function(x){return Object.keys(x).map(function(k){return[k,x[k]]})};
  if(!o.values)o.values=function(x){return Object.keys(x).map(function(k){return x[k]})};
  if(!S.padStart)S.padStart=function(n,c){var s=String(this);c=c===undefined?' ':String(c);while(s.length<n)s=c+s;return s};
  if(!S.padEnd)S.padEnd=function(n,c){var s=String(this);c=c===undefined?' ':String(c);while(s.length<n)s=s+c;return s};
  if(!A.includes)A.includes=function(v){return this.indexOf(v)>=0};
  if(!S.includes)S.includes=function(v,i){return this.indexOf(v,i)>=0};
  if(window.Promise&&!Promise.prototype.finally)Promise.prototype.finally=function(f){var P=this.constructor;return this.then(function(v){return P.resolve(f()).then(function(){return v})},function(e){return P.resolve(f()).then(function(){throw e})})};
  window.addEventListener('error',function(e){
    try{var d=document.getElementById('ps-err');
    if(!d){d=document.createElement('div');d.id='ps-err';d.style.cssText='position:fixed;left:0;right:0;bottom:0;z-index:99999;pointer-events:none;background:#7f1d1d;color:#fff;font:14px monospace;padding:8px;white-space:pre-wrap';(document.body||document.documentElement).appendChild(d)}
    d.textContent='Script error: '+(e.message||'')+' ('+(e.lineno||'?')+')'}catch(_){}
  });
})();
"""

s = P.read_text(encoding='utf-8')
a = s.rindex('<script>\n') + len('<script>\n')
b = s.index('</script>', a)
js = s[a:b]
if js.lstrip().startswith(MARK):
    print('already transpiled'); sys.exit(0)
r = subprocess.run(['npx', '--yes', 'esbuild@0.28.2', '--target=chrome53', '--loader=js'],
                   input=js, capture_output=True, text=True)
if r.returncode:
    sys.exit(r.stderr)
out = r.stdout
# old browsers enforce the temporal dead zone: init() runs before later top-level let/const -> use var (hoisted)
out = re.sub(r'(?m)^(?:let|const) ', 'var ', out)
if "'''" in out:
    sys.exit("output contains ''' which would end the Dart raw string")
P.write_text(s[:a] + PRELUDE + out + s[b:], encoding='utf-8')
print('transpiled', len(js), '->', len(out))
