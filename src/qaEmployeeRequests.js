const operations=Object.freeze({sale:'بيع',purchase_draft:'مسودة شراء',inventory_count:'جرد',return_request:'مرتجع زبون',order_process:'معالجة طلب'});
const statuses=Object.freeze({pending:'بانتظار موافقة المدير',approved:'موافق عليه',rejected:'مرفوض'});
// Render only an employee's server-filtered request metadata, never payloads or identities.
export function employeeRequestRows(data){
 if(!Array.isArray(data))return [];
 return data.filter(r=>r&&Object.hasOwn(operations,r.operation)&&Object.hasOwn(statuses,r.status)&&typeof r.id==='string'&&/^[a-f0-9-]{36}$/i.test(r.id)&&!r.payload?.bundle_parent).slice(0,20).map(r=>({id:r.id,operation:operations[r.operation],status:r.status,statusLabel:statuses[r.status],createdAt:typeof r.created_at==='string'&&Number.isFinite(Date.parse(r.created_at))?r.created_at:null}));
}
