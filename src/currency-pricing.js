/**
 * POS price snapshots: product.sale_price is stored in its native currency.
 * The cash register and customer receivables are recorded in SYP.
 * No implicit exchange rate and no currency conversion of legacy drafts.
 */
export function validUsdRate(value){
 const n=Number(value);
 return value!==null && value!==undefined && value!=='' && Number.isFinite(n) && n>1;
}
export function posCartPrice(product, settingsRate){
 const currency=product?.sale_currency==='USD'?'USD':'SYP';
 const base=Number(product?.sale_price);
 if(!Number.isFinite(base)||base<0)throw new Error('سعر المنتج الأصلي غير صالح؛ راجع بطاقة المادة');
 if(currency==='SYP')return {
  ...product,sale_currency:'SYP',sale_price:base,base_sale_price:base,
  base_sale_price_syp:base,price_fx_rate:1
 };
 if(!validUsdRate(settingsRate)||!validUsdRate(product.current_fx_rate)){
  throw new Error('سعر صرف الدولار غير مضبوط. حدّث سعر الصرف قبل إضافة الدواء.');
 }
 const rate=Number(settingsRate);
 if(Math.abs(rate-Number(product.current_fx_rate))>0.0000001){
  throw new Error('تغيّر سعر الصرف أثناء البحث. حدّث البحث ثم أضف الدواء مجدداً.');
 }
 const converted=base*rate;
 if(!Number.isFinite(converted))throw new Error('تعذر احتساب سعر الدواء بالليرة');
 const returned=product.sale_price_syp==null?converted:Number(product.sale_price_syp);
 if(!Number.isFinite(returned)||Math.abs(returned-converted)>Math.max(0.01,converted*0.00000001)){
  throw new Error('السعر المحوّل لا يطابق سعر الصرف الحالي. أعد البحث عن الدواء.');
 }
 return {
  ...product,sale_currency:'USD',sale_price:converted,base_sale_price:base,
  base_sale_price_syp:converted,price_fx_rate:rate
 };
}
export function verifyPosCurrencyCart(cart,currentRate){
 for(const item of cart){
  if(item.sale_currency!=='USD')continue;
  if(!validUsdRate(currentRate)||!validUsdRate(item.price_fx_rate)){
   throw new Error('سلة البيع تحتوي دواء بالدولار من مسودة قديمة أو دون سعر صرف موثّق. احذفه وأعد إضافته.');
  }
  if(Math.abs(Number(item.price_fx_rate)-Number(currentRate))>0.0000001){
   throw new Error('تغيّر سعر صرف الدولار بعد إضافة أدوية للسلة. احذف أدوية الدولار وأعد إضافتها بالسعر الحالي.');
  }
  const original=Number(item.base_sale_price);
  const originalSyp=Number(item.base_sale_price_syp);
  if(!Number.isFinite(original)||original<0||!Number.isFinite(originalSyp)||Math.abs(original*Number(currentRate)-originalSyp)>Math.max(0.01,Math.abs(originalSyp)*0.00000001)){
   throw new Error('تعذر التحقق من سعر الدولار الأصلي في السلة. احذف الدواء وأعد إضافته.');
  }
 }
 return true;
}
