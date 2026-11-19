import React, {useEffect, useRef, useState} from 'react';
import {createRoot} from 'react-dom/client';
import {createClient} from '@supabase/supabase-js';
import {BranchPortal} from './BranchManagement.jsx';
import {branchIdFromSearch,branchOperatorSections,branchMoney} from './branchWorkspace.js';
import './style.css';
import './BranchManagement.css';

const client = createClient(import.meta.env.VITE_SUPABASE_URL,import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY);
const branchId = branchIdFromSearch(location.search);

function Checkout({onSaved}) {
  const [query,setQuery]=useState(''), [matches,setMatches]=useState([]), [cart,setCart]=useState([]);
  const [busy,setBusy]=useState(false), [message,setMessage]=useState('');
  const request=useRef(null);
  useEffect(()=>{
    let active=true;
    setMatches([]);
    if(query.trim())client.rpc('pharmacy_branch_pos_search',{p_branch:branchId,p_query:query.trim()}).then(({data,error})=>{
      if(active){setMatches(data??[]);if(error)setMessage('تعذّر البحث في أصناف الفرع.');}
    });
    return ()=>{active=false;};
  },[query]);
  function change(product,amount) {
    if(busy)return;
    request.current=null;
    setCart(previous=>{
      const quantity=(previous.find(line=>line.id===product.id)?.quantity??0)+amount;
      if(quantity>product.stock)return previous;
      return [...previous.filter(line=>line.id!==product.id),...(quantity>0?[{...product,quantity}]:[])];
    });
  }
  async function save(){
    if(busy||!cart.length)return;
    setBusy(true);
    try{
      request.current??=crypto.randomUUID();
      const {error,data}=await client.rpc('pharmacy_branch_pos_complete',{p_branch:branchId,p_id:request.current,
        p_items:cart.map(line=>({product_id:line.id,unit_price:line.sale_price,quantity:line.quantity}))});
      if(error)throw error;
      setMessage('تم البيع · '+branchMoney(data.total));setCart([]);setQuery('');request.current=null;onSaved();
    }catch{setMessage('تعذّر تأكيد البيع. راجع الرصيد والسعر وأعد المحاولة.');}
    finally{setBusy(false);}
  }
  return <section className="qaBranchDetail"><h3>بيع نقدي من مخزون الفرع</h3>
    <label>اسم الصنف أو الباركود<input value={query} onChange={e=>setQuery(e.target.value)}/></label>
    {matches.map(p=><button disabled={busy||!p.stock} key={p.id} onClick={()=>change(p,1)}>{p.name} · {branchMoney(p.sale_price)}</button>)}
    {cart.map(line=><p key={line.id}>{line.name} × {line.quantity} <button disabled={busy} onClick={()=>change(line,-1)}>إنقاص</button></p>)}
    <button className="primary" disabled={busy||!cart.length} onClick={save}>تأكيد البيع · {branchMoney(cart.reduce((s,p)=>s+BigInt(p.quantity)*BigInt(p.sale_price),0n))}</button>
    <p role="status">{message}</p></section>;
}
function BranchShell({branch}) {
  const options=branchOperatorSections.filter(item=>!item.locked&&item.id!=='dashboardProfit'&&branch.canOpen(item.id));
  const [selected,setSelected]=useState('dashboard'),[revision,refresh]=useState(0);
  const current=options.find(item=>item.id===selected)??options[0];
  return <main dir="rtl" className="panel qaBranchCenter"><header><h2>{branch.name}</h2>
    <button onClick={()=>client.auth.signOut()}>تسجيل الخروج</button></header>
    <nav className="qaBranchControls">{options.map(item=><button key={item.id} aria-pressed={current?.id===item.id} onClick={()=>setSelected(item.id)}>{item.label}</button>)}</nav>
    {current?.id==='pos'&&<Checkout onSaved={()=>refresh(v=>v+1)}/>}
    <div key={current?.id+':'+revision}>{current?branch.render(current.id):'لم يمنح المدير صلاحيات تشغيل لهذا الفرع.'}</div></main>;
}
function Entry() {
  const [session,setSession]=useState(undefined);
  useEffect(()=>{
    const {data:{subscription}}=client.auth.onAuthStateChange((event,current)=>setSession(current));
    return ()=>subscription.unsubscribe();
  },[]);
  if(session===undefined)return <p>جارٍ تحميل الفرع…</p>;
  return <BranchPortal client={client} branchId={branchId} user={session?.user} renderShell={branch=><BranchShell branch={branch}/>}/>;
}
createRoot(document.getElementById('root')).render(<Entry/>);
