#!/usr/bin/env python3
"""Adds Arabic (right-to-left) to the embedded web page without touching its logic.

A small ES5 script translates visible text (text nodes, placeholders, titles) from a dictionary and keeps doing so
for text the page creates later (toasts, lists). The language follows the browser (Arabic browser -> Arabic) and can be
switched with the round button in the corner. Anything not in the dictionary (file names, user names) stays as is.
Idempotent. Run before tool/transpile_web_ui.py (gen_web_ui.py does both). Usage: tool/web_i18n.py"""
import json, pathlib, re

P = pathlib.Path(__file__).resolve().parent.parent / 'lib/host/web_ui.dart'
MARK = '/*ps-i18n*/'

AR = {
 '1 Hour':'ساعة واحدة','1 Month':'شهر واحد','1 Week':'أسبوع واحد','24 Hours':'24 ساعة','Account':'الحساب','All':'الكل',
 'All clipboard entries':'كل عناصر الحافظة','All favourites & activity history':'كل المفضلة وسجل النشاط',
 'All notes you posted':'كل الملاحظات التي نشرتها','All saved links':'كل الروابط المحفوظة',
 'All share links you created':'كل روابط المشاركة التي أنشأتها','All your uploaded files & folders':'كل ملفاتك ومجلداتك المرفوعة',
 'Anyone on the network can see this':'يستطيع أي شخص على الشبكة رؤية هذا','Appearance':'المظهر',
 'Change Password':'تغيير كلمة المرور','Change photo':'تغيير الصورة','Clipboard':'الحافظة','Clipboard Sync':'مزامنة الحافظة',
 'Close':'إغلاق','Default Upload Privacy':'خصوصية الرفع الافتراضية','Delete':'حذف','Drop to Upload':'أفلت للرفع',
 'ETA':'الوقت المتبقي','Everything below will be wiped — this cannot be undone.':'سيتم مسح كل ما يلي ولا يمكن التراجع عن ذلك.',
 'Exit':'خروج','FTP / FTPS Server':'خادم FTP / FTPS','Files':'الملفات','Folder':'مجلد','Generate Share Link':'إنشاء رابط مشاركة',
 'Hidden from all other users':'مخفي عن كل المستخدمين الآخرين','Link expires after:':'ينتهي الرابط بعد:','Links':'الروابط',
 'Loading...':'جارٍ التحميل...','Long-press to select · tap to toggle':'اضغط مطولاً للتحديد · المس للتبديل','Move':'نقل',
 'Network Share':'مشاركة الشبكة','New Folder':'مجلد جديد','OK':'حسناً','Permanently delete your account.':'حذف حسابك نهائياً.',
 'Pick exactly who can access this':'اختر بالضبط من يستطيع الوصول','Post':'نشر','Private Files':'ملفات خاصة','Profile':'الملف الشخصي',
 'Register':'إنشاء حساب','Save and share your favorite links':'احفظ وشارك روابطك المفضلة','Select':'تحديد',
 'Select users who can access:':'اختر المستخدمين المسموح لهم بالوصول:','Server Info':'معلومات الخادم','Share URL:':'رابط المشاركة:',
 'Sign In':'تسجيل الدخول','Sign in':'تسجيل الدخول','Sign Out':'تسجيل الخروج','Sign out':'تسجيل الخروج','Create Account':'إنشاء حساب',
 'Continue as Guest (public files only)':'المتابعة كضيف (الملفات العامة فقط)',
 'Text snippets — copy, save, download':'مقتطفات نصية — انسخ، احفظ، نزّل','Unzip':'فك الضغط','Update Password':'تحديث كلمة المرور',
 'Upload':'رفع','Uploading...':'جارٍ الرفع...','Use QR button in top bar to share':'استخدم زر QR في الشريط العلوي للمشاركة',
 'Username':'اسم المستخدم','Your personal file hub':'مركز ملفاتك الشخصي','Zip':'ضغط','File Info':'معلومات الملف','Light':'فاتح',
 'Settings':'الإعدادات','Danger Zone':'منطقة الخطر','Favourites':'المفضلة','Public':'عام','Dark':'داكن',
 'Selected Users Only':'مستخدمون محددون فقط','Notes':'الملاحظات','Latest':'الأحدث','Scan to Connect':'امسح للاتصال','Size':'الحجم',
 'Storage Usage':'استخدام التخزين','Auto':'تلقائي','Set File Access':'تحديد صلاحية الملف','Private':'خاص','Private — Only You':'خاص — أنت فقط',
 'Share Link':'رابط مشاركة','Name':'الاسم','Access':'الوصول','Cancel':'إلغاء',
 'Changing the extension may make the file unreadable.':'تغيير الامتداد قد يجعل الملف غير قابل للقراءة.','Copy':'نسخ','Copy All':'نسخ الكل',
 'Copy CSV':'نسخ CSV','DESCRIPTION':'الوصف','DL':'تنزيل','Download':'تنزيل','Download to open':'نزّل للفتح','Edit':'تعديل',
 'Empty CSV':'ملف CSV فارغ','Extension':'الامتداد','File Name':'اسم الملف','Filter':'تصفية','Go to':'اذهب إلى','Home':'الرئيسية',
 'NAME *':'الاسم *','URL *':'الرابط *','No clipboards yet':'لا توجد عناصر حافظة بعد','No links yet':'لا توجد روابط بعد',
 'No notes yet. Be the first!':'لا توجد ملاحظات بعد. كن الأول!','No other users registered':'لا يوجد مستخدمون آخرون مسجلون',
 'No preview available':'لا توجد معاينة','Pg':'ص','Rename':'إعادة تسمية','Save':'حفظ','Save Access':'حفظ الصلاحيات',
 'Select users:':'اختر المستخدمين:','Sign in to use Clipboard':'سجّل الدخول لاستخدام الحافظة','Sign in to use Links':'سجّل الدخول لاستخدام الروابط',
 'Speed:':'السرعة:','Tap + to add your first link':'اضغط + لإضافة أول رابط','To Clipboard':'إلى الحافظة','Total on server':'الإجمالي على الخادم',
 'Who can see this link:':'من يستطيع رؤية هذا الرابط:','Your files':'ملفاتك','Add Link':'إضافة رابط','Save Changes':'حفظ التغييرات',
 'Upload files to get started':'ارفع ملفات للبدء','Empty folder':'مجلد فارغ','No files yet':'لا توجد ملفات بعد','(optional)':'(اختياري)',
 'Apply':'تطبيق','Done':'تم','Password required':'كلمة المرور مطلوبة','Please wait...':'يرجى الانتظار...','Saving...':'جارٍ الحفظ...',
 'Move to':'نقل إلى','Copy to':'نسخ إلى','Password':'كلمة المرور','Language':'اللغة',
 # placeholders / titles
 'Add a note...':'أضف ملاحظة...','Current password':'كلمة المرور الحالية','Enter your password to confirm':'أدخل كلمة المرور للتأكيد',
 'New password (min 4 chars)':'كلمة مرور جديدة (4 أحرف على الأقل)','Search files...':'ابحث عن ملفات...','Type here...':'اكتب هنا...',
 'Exit selection':'إلغاء التحديد',
 # toasts
 'Access updated':'تم تحديث الصلاحيات','Account deleted. Goodbye!':'تم حذف الحساب. إلى اللقاء!','Avatar updated!':'تم تحديث الصورة!',
 'Browsing as guest 👀 (view & download only)':'تتصفح كضيف 👀 (عرض وتنزيل فقط)','Copied!':'تم النسخ!','Copy failed':'فشل النسخ',
 'Copy failed — try long-press':'فشل النسخ — جرّب الضغط المطول','Deleted':'تم الحذف','Done!':'تم!','Error':'خطأ','Extracted!':'تم الاستخراج!',
 'File name cannot be empty':'لا يمكن ترك اسم الملف فارغاً','File saved!':'تم حفظ الملف!','Fill both password fields':'املأ حقلي كلمة المرور',
 'Folder created':'تم إنشاء المجلد','Guests cannot upload files':'الضيوف لا يستطيعون رفع الملفات','Link access updated':'تم تحديث صلاحية الرابط',
 'Logged out':'تم تسجيل الخروج','Long-press a file to start selecting':'اضغط مطولاً على ملف لبدء التحديد','Name is required':'الاسم مطلوب',
 'New password must be 4+ chars':'يجب أن تتكون كلمة المرور الجديدة من 4 أحرف على الأقل','Note added!':'تمت إضافة الملاحظة!',
 'Password updated!':'تم تحديث كلمة المرور!','Please sign in first':'يرجى تسجيل الدخول أولاً','Removed from favourites':'تمت الإزالة من المفضلة',
 'Renamed':'تمت إعادة التسمية','Saved to Clipboard!':'تم الحفظ في الحافظة!','Saved!':'تم الحفظ!',
 'Select exactly 1 item to rename':'اختر عنصراً واحداً فقط لإعادة تسميته','Select files first':'اختر ملفات أولاً',
 'Selection mode — tap more to select':'وضع التحديد — المس المزيد للتحديد','Share link created!':'تم إنشاء رابط المشاركة!',
 'Sign in to manage access':'سجّل الدخول لإدارة الصلاحيات','Sign in to star files':'سجّل الدخول لإضافة ملفات إلى المفضلة',
 'Sign in to use clipboard':'سجّل الدخول لاستخدام الحافظة','Sign in to use this feature':'سجّل الدخول لاستخدام هذه الميزة',
 'URL is required':'الرابط مطلوب','Upload complete!':'اكتمل الرفع!','Upload failed':'فشل الرفع','Zipped!':'تم الضغط!',
 'Added to favourites':'تمت الإضافة إلى المفضلة',
}
PREFIX = [['Welcome, ','مرحباً، '],['Access updated for ','تم تحديث الصلاحيات لـ '],['Default privacy saved: ','تم حفظ الخصوصية الافتراضية: '],
          ['Duplicated as ','تم النسخ باسم '],['Theme: ','المظهر: ']]

EDGE = re.compile(r'^([^A-Za-z0-9؀-ۿ]*)([\s\S]*?)([^A-Za-z0-9؀-ۿ]*)$')
def core(t): return EDGE.match(t).group(2)

D = {}
for en, ar in AR.items():
    D[en] = ar
    ce, ca = core(en), core(ar)
    if ce and ce != en and ce not in D: D[ce] = ca

JS = r"""/*ps-i18n*/
(function(){
  var D=__DICT__, PF=__PREFIX__;
  var EDGE=/^([^A-Za-z0-9؀-ۿ]*)([\s\S]*?)([^A-Za-z0-9؀-ۿ]*)$/;
  var lang='en';
  try{lang=localStorage.getItem('ps_lang')||''}catch(e){}
  if(lang!=='ar'&&lang!=='en'){lang=((navigator.language||'en')+'').toLowerCase().indexOf('ar')===0?'ar':'en'}
  function tx(s){
    var t=s.replace(/^\s+|\s+$/g,''); if(!t)return s;
    var i=s.indexOf(t), lead=s.slice(0,i), trail=s.slice(i+t.length), r;
    if(D.hasOwnProperty(t))return lead+D[t]+trail;
    var m=EDGE.exec(t);
    if(m&&m[2]&&D.hasOwnProperty(m[2]))return lead+m[1]+D[m[2]]+m[3]+trail;
    for(var k=0;k<PF.length;k++)if(t.indexOf(PF[k][0])===0)return lead+PF[k][1]+t.slice(PF[k][0].length)+trail;
    if((r=/^Apply to All (\d+) Files$/.exec(t)))return lead+'تطبيق على كل '+r[1]+' ملفات'+trail;
    return s;
  }
  var ATTRS=['placeholder','title','aria-label'];
  function textNode(n){
    var v=n.nodeValue;
    if(n.__t===undefined||v!==n.__t)n.__o=v; /* new text from the page (not our own output) */
    var o=lang==='ar'?tx(n.__o):n.__o; n.__t=o; if(o!==v)n.nodeValue=o;
  }
  function el(e){
    var tag=e.nodeName;
    if(tag==='SCRIPT'||tag==='STYLE'||tag==='TEXTAREA'||e.id==='ps-lang'||e.id==='ps-err')return;
    for(var i=0;i<ATTRS.length;i++){var a=ATTRS[i];
      if(e.hasAttribute&&e.hasAttribute(a)){var cur=e.getAttribute(a), key='__a_'+a;
        if(e[key]===undefined||cur!==e[key+'t']){e[key]=cur}
        var out=lang==='ar'?tx(e[key]):e[key]; e[key+'t']=out; if(out!==cur)e.setAttribute(a,out);}}
    for(var c=e.firstChild;c;c=c.nextSibling)walk(c);
  }
  function walk(n){ if(n.nodeType===3)textNode(n); else if(n.nodeType===1)el(n); }
  function apply(){
    var h=document.documentElement; h.setAttribute('lang',lang); h.setAttribute('dir',lang==='ar'?'rtl':'ltr');
    if(document.body)walk(document.body);
  }
  function start(){
    window.psSetLang=function(l){lang=l==='ar'?'ar':'en';try{localStorage.setItem('ps_lang',lang)}catch(e){} apply()};
    apply();
    if(window.MutationObserver){
      var busy=false;
      new MutationObserver(function(ms){
        if(busy)return; busy=true;
        try{ for(var i=0;i<ms.length;i++){var m=ms[i];
          if(m.type==='characterData')textNode(m.target);
          else if(m.type==='attributes')el(m.target);
          else for(var j=0;j<m.addedNodes.length;j++)walk(m.addedNodes[j]); } }catch(e){}
        busy=false;
      }).observe(document.body,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:ATTRS});
    }
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start); else start();
})();
"""

LANG_BLOCK = '''    <!-- ps-lang -->
    <div class="bg-slate-50 dark:bg-slate-800 rounded-2xl p-4 mb-4">
      <p class="text-xs font-black text-slate-500 uppercase tracking-wider mb-3">Language</p>
      <div class="flex gap-2">
        <button onclick="psSetLang('en')" class="flex-1 py-2.5 rounded-xl font-black text-sm bg-white dark:bg-slate-700 border-2 border-slate-200 dark:border-slate-600 text-slate-700 dark:text-slate-300 active:scale-95">English</button>
        <button onclick="psSetLang('ar')" class="flex-1 py-2.5 rounded-xl font-black text-sm bg-white dark:bg-slate-700 border-2 border-slate-200 dark:border-slate-600 text-slate-700 dark:text-slate-300 active:scale-95">العربية</button>
      </div>
    </div>

'''
s = P.read_text(encoding='utf-8')
if MARK in s:  # replace an older block
    i = s.index('<script>\n' + MARK); j = s.index('</script>\n', i) + len('</script>\n')
    s = s[:i] + s[j:]
if '<!-- ps-lang -->' not in s:
    s = s.replace('    <!-- Server info -->', LANG_BLOCK + '    <!-- Server info -->', 1)
a = s.rindex('<script>\n')
block = '<script>\n' + JS.replace('__DICT__', json.dumps(D, ensure_ascii=False)).replace('__PREFIX__', json.dumps(PREFIX, ensure_ascii=False)) + '</script>\n'
P.write_text(s[:a] + block + s[a:], encoding='utf-8')
print('added', len(D), 'entries')
