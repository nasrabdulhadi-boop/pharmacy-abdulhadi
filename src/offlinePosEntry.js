import {createClient} from '@supabase/supabase-js';
import {ISOLATED_QA_PROJECT_URL} from './stagingAuthGuard.js';
import {prepareRegister,queueSale,markSynced,localDay,updateRegister} from './offlineSaleQueue.js';
import './offlinePos.css';

const url=import.meta.env.VITE_SUPABASE_URL;
const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || import.meta.env.VITE_SUPABASE_ANON_KEY;
const els=Object.fromEntries(['prepare','sync','state','message','search','results','cart','total','save','pending'].map(id=>[id,document.getElementById(id)]));
const pointer='pharmacy-qa-offline-actor';
const fmt=(ticks)=>new Intl.NumberFormat('en-US',{maximumFractionDigits:4}).format(ticks/10000)+' ل.س';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const roles=['system_owner','system_admin','employee'];
const qa=url===ISOLATED_QA_PROJECT_URL && !!key && import.meta.env.MODE==='staging';
const client=qa?createClient(url,key):null;
let actor=null, register=null, busy=false, ready=false;
const cart=new Map();

const element=(tag,text)=>Object.assign(document.createElement(tag),{textContent:text});
function action(text,fn,disabled=false) {
 const node=element('button',text);node.type='button';node.disabled=disabled;node.onclick=fn;return node;
}
function canSell() {
 return qa&&ready&&actor===localStorage.getItem(pointer)&&register&&register.day===localDay()&&register.expiresAt>Date.now()&&register.sales.length<100;
}
function render() {
 const valid=canSell();
 const q=els.search.value.trim().toLowerCase();
 const products=register?.products||[];
 els.results.replaceChildren(...(q&&valid?products.filter(p=>p.stock>0&&[p.name,p.barcode].some(value=>String(value||'').toLowerCase().includes(q))).slice(0,20):[]).map(p=>{
  const row=element('li',p.name+' · '+p.barcode+' · '+fmt(p.ticks)+' · '+p.stock+' ');
  row.append(action('إضافة',()=>add(p.id),busy||(cart.get(p.id)||0)>=p.stock));return row;
 }));
 els.cart.replaceChildren(...[...cart].flatMap(([id,quantity])=>{
  const item=products.find(p=>p.id===id);
  if(!item)return [];
  const row=element('li',item.name+' × '+quantity+' · '+fmt(quantity*item.ticks)+' ');
  row.append(action('−',()=>{if(quantity===1)cart.delete(id);else cart.set(id,quantity-1);render();},busy));
  return [row];
 }));
 els.total.textContent='الإجمالي '+fmt([...cart].reduce((n,[id,q])=>n+q*(products.find(p=>p.id===id)?.ticks||0),0));
 els.pending.replaceChildren(...(register?.sales||[]).map(sale=>element('li',sale.id+' · '+fmt(sale.total))));
 if(register?.lastReceipt?.serverId)els.pending.append(element('li','آخر مرجع مؤكد: '+register.lastReceipt.serverId));
 els.prepare.disabled=busy||!qa||!navigator.onLine||!!register?.sales.length;
 els.sync.disabled=busy||!qa||!navigator.onLine||!register?.sales.length;
 els.save.disabled=busy||!valid||!cart.size;
 els.search.disabled=busy||!valid;
 els.state.textContent=!qa?'هذه الشاشة متاحة على QA فقط.':
  (navigator.onLine?'متصل بالشبكة':'غير متصل')+' · '+(valid?'الدليل المحلي جاهز':register?'التسجيل متوقف. زامن المبيعات وجدّد الدليل.':'جهّز الجهاز أولاً أثناء الاتصال.');
}
function add(id) {
 const product=register?.products.find(p=>p.id===id);
 const current=cart.get(id)||0;
 if(busy||!canSell()||!product||current>=Math.min(product.stock,999)||(cart.size>=30&&!current))return;
 cart.set(id,current+1);els.search.value='';render();els.search.focus();
}
async function locked(operation) {
 if(busy)return;
 busy=true;els.message.textContent='';render();
 try{await operation();}
 catch(error){
  els.message.textContent=({
   storage_error:'تعذر الحفظ على الجهاز.',
   insufficient_stock:'الرصيد تغيّر. راجع الكمية.',
   expired_snapshot:'انتهت صلاحية الدليل المحلي.',
   offline_price_changed:'تغيّر السعر. توقفت المزامنة عند هذه الفاتورة وبقيت محفوظة على الجهاز.',
   sync_first:'زامن المبيعات المنتظرة أولاً.',
   account_mismatch:'ارجع للنظام وسجّل دخول نفس الحساب، ثم أعد المحاولة.',
   offline_unavailable:'تعذر تجهيز العمل دون اتصال على هذا المتصفح.',
  })[error.message]||'تعذرت العملية. إذا كنت تزامن، تبقى المبيعات غير المؤكدة على الجهاز.';
 }finally{busy=false;render();}
}
async function verifiedUser() {
 const {data,error}=await client.auth.getUser();
 const id=data?.user?.id;
 if(error||!uuid.test(id||''))throw Error('account_mismatch');
 return id;
}
async function installShell() {
 if(!('serviceWorker' in navigator))throw Error('offline_unavailable');
 const registration=await navigator.serviceWorker.register('/offline-pos/sw.js',{scope:'/offline-pos/'});
 if(!registration.active || navigator.serviceWorker.controller?.scriptURL!==new URL('/offline-pos/sw.js',location.href).href){
  await new Promise((resolve,reject)=>{
   const timeout=setTimeout(()=>{navigator.serviceWorker.removeEventListener('controllerchange',changed);reject(Error('offline_unavailable'));},20000);
   function changed(){
    if(navigator.serviceWorker.controller?.scriptURL!==new URL('/offline-pos/sw.js',location.href).href)return;
    clearTimeout(timeout);navigator.serviceWorker.removeEventListener('controllerchange',changed);resolve();
   }
   navigator.serviceWorker.addEventListener('controllerchange',changed);
   changed();
  });
 }
 ready=true;
}
els.search.oninput=render;
els.search.onkeydown=event=>{
 if(event.key!=='Enter')return;
 event.preventDefault();
 const match=register?.products.filter(p=>p.barcode===els.search.value.trim()&&p.stock>0);
 if(match?.length===1)add(match[0].id);
};
els.prepare.onclick=()=>locked(async()=>{
 const id=await verifiedUser();
 if(actor&&actor!==id&&(await updateRegister(actor))?.sales.length)throw Error('account_mismatch');
 const {data,error}=await client.rpc('qa_workspace_snapshot');
 if(error||!roles.includes(data?.role)||await verifiedUser()!==id)throw Error('account_mismatch');
 await installShell();
 const prepared=await updateRegister(id,previous=>prepareRegister(id,data,previous));
 localStorage.setItem(pointer,id);
 actor=id;register=prepared;cart.clear();
 await navigator.storage?.persist?.().catch(()=>false);
 els.message.textContent='تم تجهيز الدليل لهذا الجهاز.';
});
els.save.onclick=()=>locked(async()=>{
 if(!canSell()||!actor)return;
 const id=crypto.randomUUID();
 const lines=[...cart].map(([id,quantity])=>({id,quantity}));
 try{register=await updateRegister(actor,current=>queueSale(current,lines,id));}
 catch(error){register=await updateRegister(actor);throw error;}
 cart.clear();els.message.textContent='حُفظ البيع محلياً · '+id;
});
els.sync.onclick=()=>locked(async()=>{
 if(!actor||await verifiedUser()!==actor)throw Error('account_mismatch');
 register=await updateRegister(actor);
 while(register?.sales.length){
  const sale=register.sales[0];
  const {data,error}=await client.rpc('qa_sync_offline_sale',{p_actor:actor,p_local_id:sale.id,p_lines:sale.lines});
  if(error||!uuid.test(data||''))throw error||Error('sync_failed');
  register=await updateRegister(actor,current=>markSynced(current,sale.id,data));
 }
 els.message.textContent='تأكد حفظ كل المبيعات على الخادم. جدّد الدليل قبل فصل الاتصال.';
});
window.addEventListener('online',()=>{render();if(!els.sync.disabled)els.sync.click();});
window.addEventListener('offline',render);
window.addEventListener('storage',event=>{if(event.key===pointer&&event.newValue!==actor){cart.clear();register=null;render();}});
window.addEventListener('focus',()=>{if(actor&&!busy)updateRegister(actor).then(current=>{if(!busy){register=current;render();}}).catch(()=>{});});
if(qa){
 locked(async()=>{
  const id=localStorage.getItem(pointer);
  ready=navigator.serviceWorker?.controller?.scriptURL===new URL('/offline-pos/sw.js',location.href).href;
  if(!uuid.test(id||''))return;
  actor=id;register=await updateRegister(id);
  if(navigator.onLine){
   const onlineId=await verifiedUser().catch(()=>null);
   if(onlineId!==id){register=null;throw Error('account_mismatch');}
  }
 }).then(()=>{if(!els.sync.disabled)els.sync.click();});
}else render();
