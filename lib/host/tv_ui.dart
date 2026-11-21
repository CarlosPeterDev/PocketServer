// 10-foot "TV mode" page, served at /tv. Works in any smart-TV / Android TV browser.
const String kTvHtml = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>PocketServer TV</title>
<style>
*{box-sizing:border-box}
html,body{margin:0;height:100%;background:#0b0b14;color:#fff;font-family:system-ui,Segoe UI,Roboto,Arial,sans-serif;overflow:hidden}
#top{display:flex;align-items:center;gap:24px;padding:22px 48px;background:linear-gradient(#0b0b14,#0b0b1400)}
#top h1{margin:0;font-size:30px;background:linear-gradient(90deg,#7c4dff,#00b8d9);-webkit-background-clip:text;color:transparent}
.tab{font-size:22px;padding:10px 22px;border-radius:999px;background:#ffffff14;border:3px solid transparent;cursor:pointer}
.tab.on{background:#7c4dff55}
.focus{border-color:#00e5ff!important;transform:scale(1.06);box-shadow:0 0 0 4px #00e5ff55}
#grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:26px;padding:10px 48px 80px;height:calc(100% - 90px);overflow-y:auto}
.card{background:#171726;border-radius:16px;overflow:hidden;border:4px solid transparent;transition:transform .12s;cursor:pointer;position:relative}
.card .th{aspect-ratio:16/9;background:linear-gradient(135deg,#2a2a45,#14142a);display:flex;align-items:center;justify-content:center;font-size:56px;overflow:hidden}
.card video{width:100%;height:100%;object-fit:cover;pointer-events:none}
.card .nm{padding:12px 14px;font-size:20px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.card .sub{padding:0 14px 12px;font-size:15px;color:#9aa}
.heart{position:absolute;top:10px;right:12px;font-size:30px;text-shadow:0 2px 6px #000}
#player{position:fixed;inset:0;background:#000;display:none;z-index:10}
#player video{width:100%;height:100%;background:#000}
#ptitle{position:fixed;top:18px;left:28px;font-size:24px;text-shadow:0 2px 8px #000;z-index:11;display:none}
#msg{position:fixed;bottom:22px;left:50%;transform:translateX(-50%);background:#000c;padding:10px 22px;border-radius:12px;font-size:20px;z-index:12;display:none}
#login{position:fixed;inset:0;background:#0b0b14;display:none;align-items:center;justify-content:center;z-index:20}
#login form{display:flex;flex-direction:column;gap:16px;width:420px}
#login input,#login button{font-size:24px;padding:14px;border-radius:12px;border:3px solid #333;background:#171726;color:#fff}
#login input:focus,#login button:focus{outline:none;border-color:#00e5ff}
#empty{padding:40px 48px;font-size:24px;color:#9aa;display:none}
#hint{position:fixed;bottom:8px;right:18px;font-size:14px;color:#667}
</style></head><body>
<div id="top"><h1>PocketServer TV</h1>
<div class="tab on" data-t="all" tabindex="0">All videos</div>
<div class="tab" data-t="new" tabindex="0">Recently added</div>
<div class="tab" data-t="liked" tabindex="0">Liked</div></div>
<div id="empty"></div>
<div id="grid"></div>
<div id="player"><video id="v" controls autoplay></video></div>
<div id="ptitle"></div><div id="msg"></div>
<div id="login"><form id="lf"><h2>Sign in</h2>
<input id="lu" placeholder="Username" autocomplete="username">
<input id="lp" type="password" placeholder="Password" autocomplete="current-password">
<button type="submit">Sign in</button><div id="le" style="color:#f77"></div></form></div>
<div id="hint">Arrows: move · OK: play · L: like · Back/Esc: close</div>
<script>
let vids=[],stars=new Set(),tab='all',idx=0,playing=false,me=null;
const $=s=>document.querySelector(s);
const enc=p=>p.split('/').map(encodeURIComponent).join('/');
function say(t){const m=$('#msg');m.textContent=t;m.style.display='block';clearTimeout(say.t);say.t=setTimeout(()=>m.style.display='none',1800)}
async function j(u,o){const r=await fetch(u,o);if(!r.ok)throw r.status;return r.json()}
async function crawl(path,depth,out){
  let d;try{d=await j('/api/files?path='+encodeURIComponent(path)+'&sort=date')}catch(e){return}
  for(const it of d.items){
    if(it.is_folder){if(depth<5)await crawl(it.path,depth+1,out)}
    else if(it.type==='video')out.push(it);
  }
}
async function load(){
  $('#grid').innerHTML='<div style="padding:30px;font-size:24px">Loading…</div>';
  const out=[];await crawl('',0,out);vids=out;
  try{stars=new Set(await j('/api/stars'))}catch(e){stars=new Set()}
  render();
}
function list(){
  let l=vids.slice();
  if(tab==='new')l.sort((a,b)=>b.date-a.date);
  else l.sort((a,b)=>a.name.localeCompare(b.name));
  if(tab==='liked')l=l.filter(v=>stars.has(v.path));
  return l;
}
function render(keep){
  const l=list(),g=$('#grid');g.innerHTML='';
  $('#empty').style.display=l.length?'none':'block';
  $('#empty').textContent=tab==='liked'?'No liked videos yet. Press L on a video to like it.':'No videos found. Upload some from the web hub.';
  l.forEach((v,i)=>{
    const c=document.createElement('div');c.className='card';c.tabIndex=0;c.dataset.i=i;
    c.innerHTML='<div class="th">🎬</div><div class="nm"></div><div class="sub"></div>'+(stars.has(v.path)?'<div class="heart">❤️</div>':'');
    c.querySelector('.nm').textContent=v.name.replace(/\.[^.]+$/,'');
    c.querySelector('.sub').textContent=v.size+' · '+new Date(v.date*1000).toLocaleDateString();
    c.onclick=()=>{idx=i;play(v)};
    g.appendChild(c);
  });
  if(idx>=l.length)idx=Math.max(0,l.length-1);
  focusCard(keep?idx:0);
}
function cols(){const g=$('#grid');const cs=getComputedStyle(g).gridTemplateColumns.split(' ').length;return cs||1}
function focusCard(i){
  const cards=[...document.querySelectorAll('.card')];
  document.querySelectorAll('.focus').forEach(e=>e.classList.remove('focus'));
  if(!cards.length)return;
  idx=Math.max(0,Math.min(cards.length-1,i));
  cards[idx].classList.add('focus');cards[idx].focus({preventScroll:true});cards[idx].scrollIntoView({block:'nearest'});
}
function focusTab(i){const t=[...document.querySelectorAll('.tab')];document.querySelectorAll('.focus').forEach(e=>e.classList.remove('focus'));t[i].classList.add('focus');t[i].focus();focusTab.i=i}
focusTab.i=-1;
document.querySelectorAll('.tab').forEach((t,i)=>t.onclick=()=>{tab=t.dataset.t;document.querySelectorAll('.tab').forEach(x=>x.classList.toggle('on',x===t));idx=0;render()});
function play(v){
  const p=$('#player'),vd=$('#v');p.style.display='block';$('#ptitle').style.display='block';$('#ptitle').textContent=v.name;
  vd.src='/file/'+enc(v.path);vd.play().catch(()=>{});playing=true;
  setTimeout(()=>{if(playing)$('#ptitle').style.display='none'},4000);
}
function stop(){const vd=$('#v');vd.pause();vd.removeAttribute('src');vd.load();$('#player').style.display='none';$('#ptitle').style.display='none';playing=false;focusCard(idx)}
async function like(){
  const l=list(),v=l[idx];if(!v)return;
  try{const r=await j('/api/star',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({path:v.path})});
    r.starred?stars.add(v.path):stars.delete(v.path);say(r.starred?'Added to Liked ❤️':'Removed from Liked');render(true)}
  catch(e){say('Sign in to like videos')}
}
document.addEventListener('keydown',e=>{
  if($('#login').style.display==='flex')return;
  const k=e.key,vd=$('#v');
  if(playing){
    if(k==='Escape'||k==='Backspace'||k==='BrowserBack'||e.keyCode===10009||e.keyCode===461){e.preventDefault();stop()}
    else if(k==='ArrowRight'){vd.currentTime+=10;say('+10s')}
    else if(k==='ArrowLeft'){vd.currentTime-=10;say('-10s')}
    else if(k==='Enter'||k===' '){e.preventDefault();vd.paused?vd.play():vd.pause()}
    else if(k==='ArrowUp'){vd.volume=Math.min(1,vd.volume+.1)}
    else if(k==='ArrowDown'){vd.volume=Math.max(0,vd.volume-.1)}
    return;
  }
  const c=cols();
  if(focusTab.i>=0){
    if(k==='ArrowRight')focusTab(Math.min(2,focusTab.i+1));
    else if(k==='ArrowLeft')focusTab(Math.max(0,focusTab.i-1));
    else if(k==='ArrowDown'){focusTab.i=-1;focusCard(idx)}
    else if(k==='Enter')document.querySelectorAll('.tab')[focusTab.i].click();
    return;
  }
  if(k==='ArrowRight'){e.preventDefault();focusCard(idx+1)}
  else if(k==='ArrowLeft'){e.preventDefault();focusCard(idx-1)}
  else if(k==='ArrowDown'){e.preventDefault();focusCard(idx+c)}
  else if(k==='ArrowUp'){e.preventDefault();if(idx-c<0)focusTab(['all','new','liked'].indexOf(tab));else focusCard(idx-c)}
  else if(k==='Enter'){const l=list();if(l[idx])play(l[idx])}
  else if(k==='l'||k==='L')like();
});
$('#v').addEventListener('ended',()=>{const l=list();if(idx+1<l.length){idx++;play(l[idx])}else stop()});
$('#lf').onsubmit=async e=>{e.preventDefault();
  try{await j('/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:$('#lu').value,password:$('#lp').value})});
    $('#login').style.display='none';start()}catch(x){$('#le').textContent='Wrong username or password'}};
async function start(){
  try{me=await j('/api/me')}catch(e){me=null}
  if(!me||!me.username&&!me.logged_in&&me.authenticated===false){}
  load();
}
(async()=>{
  // guests can browse public files; offer sign-in if nothing is visible
  await start();
  if(!vids.length){$('#login').style.display='flex';$('#lu').focus()}
})();
</script></body></html>''';
