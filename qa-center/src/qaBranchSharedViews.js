import {branchToday} from './qaBranchWorkspace.js';

export function createBranchPosClient(client, branchId) {
  const call = (name, args) => client.rpc(name, {p_branch:branchId, ...args});
  return {
    search: query => call('qa_branch_pos_search',{p_query:query}),
    barcode: code => call('qa_branch_pos_search',{p_query:code,p_exact:true}),
    complete: (id, items) => call('qa_branch_pos_complete',{p_id:id,p_items:items}),
  };
}

export async function readBranchDashboard(client, branchId, day=branchToday()) {
  const {data,error} = await client.rpc('qa_branch_dashboard',{p_branch:branchId,p_day:day});
  if (error || !data) throw new Error('تعذّر تحميل مؤشرات الفرع');
  return {
    ...data,orders:'—',rx:'—',expired:'—',expiring:'—',dead:'—',notifications:[],error:'',
    chart:data.chart.map(point=>({...point,label:new Intl.DateTimeFormat('ar-SY',{weekday:'short',timeZone:'Asia/Damascus'})
      .format(new Date(point.dateKey+'T12:00:00Z'))})),
  };
}

export async function readBranchDashboardDay(client, branchId, day) {
  const [summary, detail] = await Promise.all([
    readBranchDashboard(client,branchId,day),
    client.rpc('qa_branch_operator_day',{p_branch:branchId,p_day:day,p_kinds:['sale','purchase','return','deposit','withdrawal','expense']}),
  ]);
  if (detail.error || !detail.data?.branch) throw new Error('تعذّر تحميل تفاصيل يوم الفرع');
  const rows=detail.data.movements;
  const by=kind=>rows.filter(item=>item.kind===kind).map(item=>({
    id:item.id,created_at:item.recorded_at,invoice_number:item.reference,total:item.amount,paid_amount:item.cash,
    due_amount:item.amount-item.cash,payment_method:item.cash<item.amount?'credit':'cash',
    type:'customer',amount:item.amount,reason:item.reference,items:item.items,
  }));
  return {
    dayKey:day, branch:true,
    summary:{...summary,net_sales:summary.netSales},
    sales:by('sale'),purchases:by('purchase'),returns:by('return'),
    cashbox:rows.filter(item=>['deposit','withdrawal','expense'].includes(item.kind)).map(item=>({
      id:item.id,type:item.kind,amount:item.kind==='deposit'?item.cash:-item.cash,description:item.reference,created_at:item.recorded_at,
    })),
  };
}
