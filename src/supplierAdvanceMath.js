const round6=value=>Math.round((value+Number.EPSILON)*1e6)/1e6;
export function purchaseAdvancePreview(total,cash,credit){
 const values=[total,cash,credit].map(Number);
 if(values.some(v=>!Number.isFinite(v)||v<0||!Number.isSafeInteger(Math.round(v*1e6))))return null;
 const [invoice,paid,available]=values,used=round6(Math.min(invoice,available));
 const cashDue=round6(Math.max(invoice-used,0));
 const created=round6(Math.max(paid-cashDue,0));
 return {used,cashDue,created,due:round6(Math.max(cashDue-paid,0)),balance:round6(available-used+created)};
}
