export const branchKinds = {
  sale: 'بيع',
  return: 'مرتجع بيع',
  purchase: 'شراء',
  expense: 'مصروف تشغيلي',
  deposit: 'إيداع بالصندوق',
  withdrawal: 'سحب من الصندوق',
  inventory: 'تسجيل رصيد صنف',
};

export const comparisonMetrics = {
  sales: 'المبيعات',
  returns: 'المرتجعات',
  profit: 'نتيجة التشغيل المسجّلة',
  cash_in: 'داخل الصندوق',
  cash_paid: 'المدفوع من الصندوق',
  cash_withdrawn: 'المسحوب من الصندوق',
  cash_balance: 'رصيد الصندوق حتى نهاية اليوم',
  shortages: 'أصناف بلغت حد الطلب',
};

const formatter = new Intl.NumberFormat('ar-SY');
export const branchNumber = value => formatter.format(BigInt(value ?? 0));
export const branchMoney = value => `${branchNumber(value)} ل.س`;
export const branchToday = () => new Intl.DateTimeFormat('en-CA', {timeZone:'Asia/Damascus'}).format(new Date());

export function orderBranches(branches, metric, descending) {
  return [...branches].sort((left, right) => {
    const a = BigInt(left[metric]);
    const b = BigInt(right[metric]);
    if (a === b) return left.name.localeCompare(right.name, 'ar');
    return (a > b ? 1 : -1) * (descending ? -1 : 1);
  });
}

export function branchLink(origin, id) {
  const url = new URL('/', origin);
  url.searchParams.set('branch', id);
  return url.href;
}

export function branchIdFromSearch(search) {
  const id = new URLSearchParams(search).get('branch');
  return /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(id ?? '') ? id : null;
}

export async function readBranchDay(client, day, id) {
  const {data, error} = await client.rpc('qa_branch_day', {p_day:day, p_branch:id || null});
  if (error) throw error;
  return data;
}

export const branchOperatorSections = [
  {id:'dashboard', label:'لوحة التحكم', kinds:[]},
  {id:'pos', label:'نقطة البيع', kinds:['sale']},
  {id:'returns', label:'المرتجعات', kinds:['return']},
  {id:'purchases', label:'المشتريات', kinds:['purchase']},
  {id:'inventory', label:'المخزون والجرد', kinds:['inventory']},
  {id:'suppliers', label:'الموردون', kinds:[]},
  {id:'cashbox', label:'الصندوق', kinds:['deposit','withdrawal','expense']},
  {id:'settings', label:'إعدادات الواجهة', kinds:[]},
  {id:'customers', label:'العملاء', locked:true},
  {id:'offers', label:'العروض', locked:true},
  {id:'profit', label:'مركز الأرباح', locked:true},
  {id:'reports', label:'التقارير العامة', locked:true},
  {id:'system', label:'مركز إدارة النظام', locked:true},
];
