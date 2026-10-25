// The hardened path requires a separately reviewed database proposal. No silent legacy fallback.
export const PUBLIC_CATALOG_FIELDS=['id','name','active_ingredient','dosage_form','strength','manufacturer','category','unit','sale_price','sale_currency','barcode'];
const publicOnly=row=>Object.fromEntries(PUBLIC_CATALOG_FIELDS.filter(key=>Object.hasOwn(row,key)).map(key=>[key,row[key]]));
export async function loadPublicCatalog(client,{hardened=false,pageSize=500,maxRows=20000}={}){
 if(!hardened)return client.from('products').select(PUBLIC_CATALOG_FIELDS.join(',')).eq('customer_visible',true).order('name');
 try{
  if(!Number.isInteger(pageSize)||pageSize<1||pageSize>500||!Number.isInteger(maxRows)||maxRows<1||maxRows>20000)throw new Error('Invalid catalog bounds');
  const rows=[],seen=new Set();
  while(rows.length<maxRows){
   const count=Math.min(pageSize,maxRows-rows.length);
   const {data,error}=await client.rpc('get_public_catalog_v1',{p_limit:count,p_offset:rows.length});
   if(error)throw error;
   if(!Array.isArray(data)||data.length>count)throw new Error('Invalid public catalog response');
   for(const row of data){
    if(!row||typeof row.id!=='string'||!row.id||seen.has(row.id))throw new Error('Invalid or duplicate catalog identifier');
    seen.add(row.id);rows.push(publicOnly(row));
   }
   if(data.length<count)return {data:rows,error:null};
  }
  const {data,error}=await client.rpc('get_public_catalog_v1',{p_limit:1,p_offset:rows.length});
  if(error)throw error;
  if(!Array.isArray(data)||data.length)throw new Error('Public catalog exceeds the configured limit');
  return {data:rows,error:null};
 }catch(error){return {data:null,error}}
}
