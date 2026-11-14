const duration = 8 * 60 * 60 * 1000;
const roles = ['system_owner','system_admin','employee'];

export function prepareRegister(actor, snapshot, previous, now = Date.now(), day = localDay(now)) {
 if (!actor || !roles.includes(snapshot?.role) || !Array.isArray(snapshot.products) ||
     !Array.isArray(snapshot.batches) || snapshot.fx_rate !== 140) throw Error('invalid_catalog');
 if (previous?.sales.length) throw Error('sync_first');
 const stocks = new Map();
 for (const batch of snapshot.batches) {
  const quantity = Number(batch.quantity);
  if (batch.expiry_date >= day && Number.isFinite(quantity) && quantity > 0) {
   stocks.set(batch.product_id,(stocks.get(batch.product_id)||0)+quantity);
  }
 }
 const products = snapshot.products.flatMap(product => {
  const stock = Math.floor(stocks.get(product.id)||0);
  const price = Number(product.sale_price) * (product.sale_currency === 'USD' ? 140 : 1);
  const ticks = Math.round(price * 10000);
  if (!product.active || !['USD','SYP'].includes(product.sale_currency) || !stock ||
      !Number.isSafeInteger(ticks) || ticks <= 0 || ticks > 1e12) return [];
  return [{id:product.id,name:product.name,barcode:product.barcode,stock,ticks}];
 });
 return {actor, day, expiresAt:now+duration, products, sales:[],lastReceipt:previous?.lastReceipt??null};
}

export function localDay(now = Date.now()) {
 return new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Damascus',year:'numeric',month:'2-digit',day:'2-digit'}).format(now);
}

export function queueSale(register, cart, id, now = Date.now(), day = localDay(now)) {
 if (!register || now >= register.expiresAt || day !== register.day) throw Error('expired_snapshot');
 if (register.sales.some(sale=>sale.id===id) || register.sales.length>=100 ||
     cart.length<1 || cart.length>30 || new Set(cart.map(item=>item.id)).size!==cart.length) throw Error('invalid_sale');
 const quantities = new Map(cart.map(item=>[item.id,item.quantity]));
 const lines = [];
 let total = 0;
 const products = register.products.map(product=>{
  if (!quantities.has(product.id)) return product;
  const quantity = quantities.get(product.id);
  if (!Number.isInteger(quantity) || quantity<=0 || quantity>999 || quantity>product.stock) throw Error('insufficient_stock');
  total+=quantity*product.ticks;
  lines.push({id:product.id,quantity,unitPrice:(product.ticks/10000).toFixed(4)});
  return {...product,stock:product.stock-quantity};
 });
 if (lines.length!==cart.length || !Number.isSafeInteger(total)) throw Error('invalid_sale');
 const sale={id,lines,total,createdAt:now};
 return {...register,products,sales:[...register.sales,sale],lastReceipt:{...sale,serverId:null}};
}

export function markSynced(register,id,serverId) {
 if (register.sales[0]?.id!==id) return register;
 return {...register,expiresAt:0,sales:register.sales.slice(1),
  lastReceipt:register.lastReceipt?.id===id?{...register.lastReceipt,serverId}:register.lastReceipt};
}

export async function updateRegister(actor, transform = state => state) {
 const db = await new Promise((resolve,reject)=>{
  const request = indexedDB.open('pharmacy-qa-offline-pos-v1',1);
  request.onerror=()=>reject(request.error);
  request.onupgradeneeded=()=>request.result.createObjectStore('registers');
  request.onsuccess=()=>resolve(request.result);
 });
 try {
  return await new Promise((resolve,reject)=>{
   const tx = db.transaction('registers','readwrite',{durability:'strict'});
   const store = tx.objectStore('registers');
   const request = store.get(actor);
   let value, failure;
   request.onsuccess=()=>{
    try {
     const current=request.result??null;
     value=transform(current);
     if(value!==current)store.put(value,actor);
    } catch(error){failure=error;tx.abort();}
   };
   tx.oncomplete=()=>resolve(value);
   tx.onabort=()=>reject(failure||tx.error||Error('storage_error'));
  });
 } finally {db.close();}
}
