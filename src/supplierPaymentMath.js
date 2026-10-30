// Match PostgreSQL round(numeric, 6) for positive monetary conversions.
const decimal=value=>{
 const text=String(value??'').trim();
 if(!/^\d+(?:\.\d+)?$/.test(text)||text.replace('.','').length>15)return null;
 const [whole,fraction='']=text.split('.');return {n:BigInt(whole+fraction),d:10n**BigInt(fraction.length),fraction:fraction.length};
};
export function supplierSettlement(amount,tenderCurrency,debtCurrency,rate){
 const a=decimal(amount),r=decimal(rate);
 if(!a||!r||a.n<=0n||r.n<=0n||a.fraction>2||!['USD','SYP'].includes(tenderCurrency)||!['USD','SYP'].includes(debtCurrency))return null;
 if(a.n*100n/a.d>BigInt(Number.MAX_SAFE_INTEGER))return null;
 let n=a.n,d=a.d;
 if(tenderCurrency!==debtCurrency){if(debtCurrency==='USD'){n*=r.d;d*=r.n}else{n*=r.n;d*=r.d}}
 const scaled=(n*1000000n*2n+d)/(2n*d);
 if(scaled<=0n||scaled>BigInt(Number.MAX_SAFE_INTEGER))return null;
 return Number(scaled)/1000000;
}
export const supplierMoney=value=>new Intl.NumberFormat('en-US',{maximumFractionDigits:6}).format(Number(value||0));
