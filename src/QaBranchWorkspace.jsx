import React, { useEffect, useRef, useState } from 'react';
import { ShoppingCart, RotateCcw, Receipt, Package, Truck, WalletCards, Users, Tag, TrendingUp, BarChart3, ShieldCheck, LockKeyhole, LogOut, Menu } from 'lucide-react';
import QaBranchManagement from './QaBranchManagement.jsx';
import { branchKinds, comparisonMetrics, branchMoney, branchNumber, branchToday, orderBranches, branchLink, readBranchDay, branchOperatorSections } from './qaBranchWorkspace.js';

function BranchTable({ title, columns, rows }) {
  return <div className="qaBranchTable" role="region" tabIndex={0} aria-label={title}>
    <table>
      <caption>{title}</caption>
      <thead><tr>{columns.map(column => <th key={column} scope="col">{column}</th>)}</tr></thead>
      <tbody>{rows.map(([id, name, ...values]) => <tr key={id}>
        <th scope="row">{name}</th>
        {values.map((value, index) => <td key={columns[index + 1]}>{value}</td>)}
      </tr>)}</tbody>
    </table>
  </div>;
}

function useDay(client, day, id, revision) {
  const [state, setState] = useState(null);
  const key = JSON.stringify([day, id, revision]);
  useEffect(() => {
    let active = true;
    readBranchDay(client, day, id).then(data => {
      if (active) setState({key, data});
    }).catch(() => {
      if (active) setState({key, error:true});
    });
    return () => { active = false; };
  }, [client, day, id, key]);
  return state?.key === key ? state : null;
}

function Comparison({ branches }) {
  const [metric, setMetric] = useState('sales');
  const [descending, setDescending] = useState(true);
  const rows = orderBranches(branches, metric, descending);
  return <>
    <div className="qaBranchControls">
      <label>ترتيب حسب <select value={metric} onChange={event => setMetric(event.target.value)}>
        {Object.entries(comparisonMetrics).map(([id, label]) => <option key={id} value={id}>{label}</option>)}
      </select></label>
      <label>الاتجاه <select value={descending ? 'desc' : 'asc'} onChange={event => setDescending(event.target.value === 'desc')}>
        <option value="desc">الأعلى أولاً</option><option value="asc">الأدنى أولاً</option>
      </select></label>
    </div>
    <BranchTable title="مقارنة الفروع" columns={['الفرع', ...Object.values(comparisonMetrics)]}
      rows={rows.map(row => [row.id, row.name, ...Object.keys(comparisonMetrics).map(key => key === 'shortages' ? branchNumber(row[key]) : branchMoney(row[key]))])}/>
    <p>نتيجة التشغيل المسجّلة تُحسب من البيع والمرتجعات وتكلفتهما والمصروفات. السحب والإيداع يؤثران على رصيد الصندوق.</p>
  </>;
}

function CreateBranch({ client, ownerEmail, onCreated }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  async function submit(event) {
    event.preventDefault();
    const form = event.currentTarget;
    const fields = new FormData(form);
    const email = String(fields.get('email')).trim().toLowerCase();
    if (email === ownerEmail?.toLowerCase()) {
      setError('أدخل بريداً مختلفاً لمسؤول الفرع.');
      return;
    }
    setBusy(true);
    setError('');
    try {
      const {data, error:failure} = await client.from('qa_branches').insert({
        name:String(fields.get('name')).trim(), location:String(fields.get('location')).trim(), invite_email:email,
      }).select('id').single();
      if (failure) throw failure;
      form.reset();
      onCreated(data.id);
    } catch {
      setError('تعذّر إنشاء الفرع. تحقّق من المعلومات وصلاحية الحساب.');
    } finally {
      setBusy(false);
    }
  }
  return <form className="qaBranchDetail qaBranchForm" onSubmit={submit}>
    <h4>إنشاء فرع</h4>
    <label>اسم الفرع<input name="name" required minLength={2} maxLength={100}/></label>
    <label>المنطقة أو العنوان<input name="location" required minLength={2} maxLength={140}/></label>
    <label>بريد مسؤول الفرع التجريبي<input name="email" type="email" required maxLength={254}/></label>
    <button type="submit" className="primary" disabled={busy}>{busy ? 'جارٍ الإنشاء…' : 'إنشاء الفرع'}</button>
    {error && <p role="alert">{error}</p>}
  </form>;
}

function InviteLink({ branch }) {
  const [status, setStatus] = useState('');
  const link = branchLink(window.location.origin, branch.id);
  async function copy() {
    try {
      await navigator.clipboard.writeText(link);
      setStatus('تم نسخ الرابط.');
    } catch {
      setStatus('حدّد الرابط وانسخه يدوياً.');
    }
  }
  return <div className="qaBranchDetail">
    <h4>دخول مسؤول الفرع</h4>
    <p><bdi>{branch.invite_email}</bdi> · {branch.member_id ? 'الحساب مرتبط' : 'بانتظار إثبات البريد'}</p>
    <label>رابط الفرع<input dir="ltr" value={link} readOnly onFocus={event => event.target.select()}/></label>
    <div className="qaBranchControls">
      <button type="button" onClick={copy}>نسخ رابط الفرع</button>
      <a href={link} target="_blank" rel="noreferrer">فتح بوابة الفرع</a>
    </div>
    <p role="status">{status}</p>
  </div>;
}

function BranchDetails({ data, branch }) {
  const {movements, inventory} = data;
  return <>
    <div className="qaBranchDetail">
      <h4>{branch.name} · {branch.location}</h4>
      <dl>{[
        ...Object.entries(comparisonMetrics).map(([key,label]) => [label,key === 'shortages' ? branchNumber(branch[key]) : branchMoney(branch[key])]),
        ['فواتير البيع',branchNumber(branch.invoices)],['عمليات الإرجاع',branchNumber(branch.return_count)],['المشتريات',branchMoney(branch.purchases)],
      ].map(([label,value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl>
    </div>
    {inventory.length ? <BranchTable title="آخر أرصدة الأصناف المسجّلة حتى اليوم المختار" columns={['الصنف أو الباركود', 'الرصيد', 'حد الطلب', 'الحالة']}
      rows={inventory.map(item => [item.id,item.reference,branchNumber(item.quantity),branchNumber(item.reorder_level),item.quantity <= item.reorder_level ? 'بلغ حد الطلب' : 'متوفر'])}/>
      : <p>ما في أرصدة أصناف مسجّلة لهذا الفرع حتى التاريخ المختار.</p>}
    {movements.length ? <BranchTable title="حركة اليوم · أحدث 100 سجل" columns={['المرجع', 'العملية', 'الوقت', 'القيمة', 'أثر الصندوق', 'التكلفة', 'مسجّل بواسطة']}
      rows={movements.map(item => [item.id,item.reference,branchKinds[item.kind],
        new Intl.DateTimeFormat('ar-SY',{timeZone:'Asia/Damascus',timeStyle:'short'}).format(new Date(item.recorded_at)),
        item.kind === 'inventory' ? '—' : branchMoney(item.amount),
        item.kind === 'inventory' ? '—' : branchMoney(BigInt(item.cash) * (['sale','deposit'].includes(item.kind) ? 1n : -1n)),
        ['sale','return'].includes(item.kind) ? branchMoney(item.cost) : '—',
        item.actor_id === branch.member_id ? 'مسؤول الفرع' : 'حساب المدير',
      ])}/>
      : <p>ما في حركات مسجّلة بالتاريخ المختار.</p>}
  </>;
}

export default function QaBranchWorkspace({ client, ownerEmail }) {
  const [tab, setTab] = useState('branches');
  const [day, setDay] = useState(branchToday);
  const [selected, setSelected] = useState('');
  const [revision, refresh] = useState(0);
  const overview = useDay(client, day, '', revision);
  const detail = useDay(client, day, selected, revision);
  const branches = overview?.data?.branches ?? [];
  const branch = detail?.data?.branches.find(row => row.id === selected);
  return <section className="qaBranchCenter" dir="rtl" aria-label="مركز إدارة الفروع">
    <p>QA · استخدم أسماء وعمليات تجريبية. التقارير تُحسب من سجلات الفروع المحفوظة هون.</p>
    <nav className="qaBranchControls" aria-label="أقسام إدارة الفروع">
      {[['branches','الفروع'],['compare','مقارنة بين الفروع'],['example','مثال بخمس صيدليات']].map(([id,label]) =>
        <button type="button" key={id} aria-pressed={tab === id} className={tab === id ? 'primary' : ''} onClick={() => setTab(id)}>{label}</button>)}
    </nav>
    {tab === 'example' ? <QaBranchManagement/> : <>
      <div className="qaBranchControls">
        <label>تاريخ التقرير <input type="date" value={day} max={branchToday()} onChange={event => { if (event.target.value) setDay(event.target.value); }}/></label>
        <button type="button" onClick={() => refresh(value => value + 1)}>تحديث البيانات</button>
      </div>
      {tab === 'branches' && <CreateBranch client={client} ownerEmail={ownerEmail} onCreated={id => { setSelected(id); refresh(value => value + 1); }}/>}
      {!overview && <p role="status">جارٍ تحميل الفروع…</p>}
      {overview?.error && <p role="alert">تعذّر تحميل الفروع. حدّث البيانات وحاول مجدداً.</p>}
      {overview?.data && !branches.length && <p>أنشئ أول فرع من تبويب الفروع لتبدأ.</p>}
      {tab === 'compare' && branches.length > 0 && <Comparison branches={branches}/>}
      {tab === 'branches' && branches.length > 0 && <>
        <label>اختيار الفرع <select value={selected} onChange={event => setSelected(event.target.value)}>
          <option value="">اختر فرعاً</option>
          {branches.map(row => <option key={row.id} value={row.id}>{row.name} · {row.location}</option>)}
        </select></label>
        {selected && !detail && <p role="status">جارٍ تحميل تفاصيل الفرع…</p>}
        {selected && detail?.error && <p role="alert">تعذّر تحميل تفاصيل الفرع.</p>}
        {branch && <><InviteLink key={branch.id} branch={branch}/><BranchDetails data={detail.data} branch={branch}/></>}
      </>}
    </>}
  </section>;
}

function RecordEvent({client, branchId, kinds, onRecorded}) {
  const [kind, setKind] = useState(kinds[0]);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState('');
  const request = useRef(null);
  async function submit(event) {
    event.preventDefault();
    const form = event.currentTarget;
    const fields = new FormData(form);
    const amount = Number(fields.get('amount'));
    const cash = ['expense','deposit','withdrawal'].includes(kind) ? amount : Number(fields.get('cash'));
    if (cash > amount) {
      setStatus('المبلغ النقدي لازم يكون أقل من قيمة العملية أو يساويها.');
      return;
    }
    const payload = {
      branch_id:branchId, kind, reference:String(fields.get('reference')).trim(),
      amount, cash, cost:Number(fields.get('cost')),
      quantity:kind === 'inventory' ? Number(fields.get('quantity')) : null,
      reorder_level:kind === 'inventory' ? Number(fields.get('reorder')) : null,
    };
    const signature = JSON.stringify(payload);
    if (request.current?.signature !== signature) request.current = {signature, id:crypto.randomUUID()};
    setBusy(true);
    setStatus('');
    try {
      const {error} = await client.from('qa_branch_events').insert({...payload,id:request.current.id});
      if (error) {
        if (error.code !== '23505') throw error;
        const saved = await client.rpc('qa_branch_event_saved',{p_branch:branchId,p_id:request.current.id});
        if (saved.error || !saved.data) throw error;
      }
      request.current = null;
      form.reset();
      setStatus('تم تسجيل الحركة.');
      onRecorded();
    } catch {
      setStatus('تعذّر تأكيد الحفظ. اضغط تسجيل مرة أخرى لنفس الحركة.');
    } finally {
      setBusy(false);
    }
  }
  const salesCost = ['sale','return'].includes(kind);
  return <form onSubmit={submit} className="qaBranchDetail qaBranchForm">
    <h4>تسجيل {kinds.length === 1 ? branchKinds[kind] : 'حركة صندوق'} · QA</h4>
    {kinds.length > 1 && <label>نوع الحركة <select value={kind} onChange={event => setKind(event.target.value)}>
      {kinds.map(id => <option key={id} value={id}>{branchKinds[id]}</option>)}
    </select></label>}
    <label key={kind}>{kind === 'inventory' ? 'اسم الصنف أو الباركود' : 'رقم الفاتورة أو وصف الحركة'}
      <input name="reference" required maxLength={160}/>
    </label>
    {kind === 'inventory' ? <>
      <label>الرصيد الحالي<input name="quantity" type="number" min="0" max="100000000" step="1" required/></label>
      <label>حد الطلب<input name="reorder" type="number" min="0" max="100000000" step="1" required/></label>
    </> : <>
      <label>قيمة الحركة بالليرة<input name="amount" type="number" min="1" max="1000000000000" step="1" required/></label>
      {['sale','return','purchase'].includes(kind) && <label>المبلغ النقدي بالليرة<input name="cash" type="number" min="0" max="1000000000000" step="1" required/></label>}
      {salesCost && <label>تكلفة الأصناف بالليرة<input name="cost" type="number" min="0" max="1000000000000" step="1" required/></label>}
    </>}
    <button type="submit" className="primary" disabled={busy}>{busy ? 'جارٍ الحفظ…' : 'تسجيل الحركة'}</button>
    <p role="status">{status}</p>
  </form>;
}

function BranchSignIn({ client, branchId }) {
  const [email, setEmail] = useState('');
  const [sent, setSent] = useState(false);
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState('');
  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    setStatus('');
    try {
      const normalized = email.trim().toLowerCase();
      const result = code.trim()
        ? await client.auth.verifyOtp({email:normalized, token:code.trim(), type:'email'})
        : await client.auth.signInWithOtp({email:normalized, options:{emailRedirectTo:branchLink(window.location.origin,branchId)}});
      if (result.error) throw result.error;
      if (!code.trim()) {
        setSent(true);
        setStatus('افتح رسالة التحقق، أو أدخل الرمز إذا وصلك رمز.');
      }
    } catch {
      setStatus('تعذّر التحقق. راجع البريد أو الرمز وحاول مجدداً.');
    } finally {
      setBusy(false);
    }
  }
  return <form onSubmit={submit} className="qaBranchDetail qaBranchForm">
    <h3>دخول مسؤول الفرع</h3>
    <p>استخدم البريد الذي سجّله المدير عند إنشاء الفرع.</p>
    <label>البريد الإلكتروني<input type="email" required value={email} onChange={event => { setEmail(event.target.value); setCode(''); setSent(false); }}/></label>
    {sent && <label>رمز التحقق إن وصلك<input value={code} inputMode="numeric" autoComplete="one-time-code" onChange={event => setCode(event.target.value)}/></label>}
    <button type="submit" className="primary" disabled={busy}>{code ? 'تحقق من الرمز' : 'أرسل التحقق إلى بريدي'}</button>
    <p role="status">{status}</p>
  </form>;
}

const operatorIcons = {
  pos:ShoppingCart, returns:RotateCcw, purchases:Receipt, inventory:Package, suppliers:Truck, cashbox:WalletCards,
  customers:Users, offers:Tag, profit:TrendingUp, reports:BarChart3, system:ShieldCheck,
};

function useOperatorData(client, branchId, day, section, revision) {
  const [state, setState] = useState(null);
  useEffect(() => {
    let active = true;
    client.rpc('qa_branch_operator_day', {p_branch:branchId, p_day:day, p_kinds:section.kinds ?? []}).then(({data,error}) => {
      if (active) setState({day, section, revision, data, error});
    }).catch(() => {
      if (active) setState({day, section, revision, error:true});
    });
    return () => { active = false; };
  }, [client, branchId, day, section, revision]);
  return {latest:state, current:state?.day === day && state.section === section && state.revision === revision ? state : null};
}

function BranchSuppliers({client, branchId}) {
  const [rows, setRows] = useState(null);
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [page, setPage] = useState(0);
  const [revision, refresh] = useState(0);
  const pageSize = 50;
  useEffect(() => {
    let active = true;
    client.from('qa_branch_suppliers').select('id,name,phone').eq('branch_id',branchId).order('name').order('id')
      .range(page * pageSize, (page + 1) * pageSize).then(({data,error}) => {
        if (!active) return;
        setRows(error ? [] : data);
        if (error) setMessage('تعذّر تحميل الموردين.');
      }).catch(() => { if (active) { setRows([]); setMessage('تعذّر تحميل الموردين.'); } });
    return () => { active = false; };
  }, [client, branchId, page, revision]);

  async function add(event) {
    event.preventDefault();
    const form = event.currentTarget;
    const values = new FormData(form);
    setBusy(true);
    setMessage('');
    try {
      const {error} = await client.from('qa_branch_suppliers').insert({
        branch_id:branchId, name:String(values.get('name')).trim(), phone:String(values.get('phone')).trim() || null,
      });
      if (error) {
        setMessage(error.code === '23505' ? 'اسم المورد مسجّل مسبقاً.' : 'تعذّر إضافة المورد.');
        return;
      }
      form.reset();
      setMessage('تمت إضافة المورد.');
      setPage(0);
      refresh(value => value + 1);
    } catch {
      setMessage('تعذّر تأكيد الإضافة. حدّث القائمة وحاول مجدداً.');
    } finally {
      setBusy(false);
    }
  }
  return <>
    <form className="qaBranchDetail qaBranchForm" onSubmit={add}>
      <h4>إضافة مورد للفرع</h4>
      <label>اسم المورد<input name="name" required minLength={2} maxLength={120}/></label>
      <label>هاتف المورد (اختياري)<input name="phone" type="tel" maxLength={40}/></label>
      <button type="submit" className="primary" disabled={busy}>إضافة مورد</button>
      <p role="status">{message}</p>
    </form>
    {rows === null ? <p role="status">جارٍ تحميل الموردين…</p> : rows.length === 0
      ? <p>لا يوجد موردون في هذه الصفحة.</p>
      : <BranchTable title="موردو الفرع" columns={['المورد','الهاتف']} rows={rows.slice(0,pageSize).map(row => [row.id,row.name,row.phone || '—'])}/>}
    {(page > 0 || rows?.length > pageSize) && <div className="qaBranchControls">
      <button type="button" disabled={page === 0} onClick={() => {setRows(null);setPage(value => value - 1);}}>السابق</button>
      <button type="button" disabled={!(rows?.length > pageSize)} onClick={() => {setRows(null);setPage(value => value + 1);}}>التالي</button>
    </div>}
  </>;
}

function OperatorActivity({data, section}) {
  if (section.id === 'inventory') {
    return data.inventory.length ? <BranchTable title="أرصدة الأصناف المسجّلة" columns={['الصنف أو الباركود','الرصيد','حد الطلب']}
      rows={data.inventory.map(item => [item.id,item.reference,branchNumber(item.quantity),branchNumber(item.reorder_level)])}/>
      : <p>ما في أرصدة أصناف مسجّلة لهذا التاريخ.</p>;
  }
  return data.movements.length ? <BranchTable title="أحدث 100 حركة في القسم خلال اليوم المختار" columns={['المرجع','الحركة','قيمة العملية','المبلغ النقدي','الوقت']}
    rows={data.movements.map(item => [item.id,item.reference,branchKinds[item.kind],branchMoney(item.amount),branchMoney(item.cash),
      new Intl.DateTimeFormat('ar-SY',{timeZone:'Asia/Damascus',timeStyle:'short'}).format(new Date(item.recorded_at))])}/>
    : <p>ما في حركات مسجّلة بهذا القسم للتاريخ المختار.</p>;
}

function SignedInBranch({ client, branchId }) {
  const [claim, setClaim] = useState(null);
  useEffect(() => {
    let active = true;
    client.rpc('qa_claim_branch',{p_branch:branchId}).then(({error}) => {
      if (active) setClaim(!error);
    }).catch(() => {
      if (active) setClaim(false);
    });
    return () => { active = false; };
  }, [client, branchId]);
  if (claim === null) return <p className="panel qaBranchPortal" role="status">جارٍ التحقق من صلاحية الدخول للفرع…</p>;
  if (claim === false) return <BranchDenied client={client}>تعذّر التحقق من صلاحية الفرع.</BranchDenied>;
  return <BranchOperations client={client} branchId={branchId}/>;
}

function BranchDenied({client, children}) {
  return <main className="panel qaBranchPortal" dir="rtl">
    <p role="alert">{children}</p>
    <button type="button" onClick={() => client.auth.signOut()}>تسجيل الخروج</button>
  </main>;
}

function BranchOperations({ client, branchId }) {
  const [section, setSection] = useState(branchOperatorSections[0]);
  const [day, setDay] = useState(branchToday);
  const [revision, refresh] = useState(0);
  const [mobile, setMobile] = useState(false);
  const {latest,current} = useOperatorData(client, branchId, day, section, revision);
  const branch = latest?.data?.branch;
  if (!latest) return <p className="panel qaBranchPortal" role="status">جارٍ تحميل الفرع…</p>;
  if (!branch) return <BranchDenied client={client}>{latest.error ? 'تعذّر تحميل الفرع.' : 'ادخل بالبريد المدعو لهذا الفرع.'}</BranchDenied>;
  const renderSection = item => {
    const Icon = operatorIcons[item.id];
    return <button key={item.id} type="button" aria-current={section === item ? 'page' : undefined}
      className={(section === item ? 'active ' : '') + (item.locked ? 'workspaceNavLocked' : '')}
      onClick={() => {setSection(item);setMobile(false);}}>
      <Icon aria-hidden="true"/><span>{item.label}{item.locked && <span className="qaBranchSrOnly"> · مقفل</span>}</span>
      {item.locked && <LockKeyhole aria-hidden="true"/>}
    </button>;
  };
  return <div className="adminShell qaBranchOperator" dir="rtl">
    <aside id="qa-branch-navigation" className={mobile ? 'open' : ''} aria-label="أقسام الفرع">
      <div className="sideBrand"><img className="sideLogo" src="/logo.png" alt=""/><div><b>{branch.name}</b><span>{branch.location}</span></div></div>
      {mobile && <button type="button" className="qaBranchCloseMenu" onClick={() => setMobile(false)}>إغلاق قائمة الأقسام</button>}
      <div className="sideMiniProfile"><span className="onlineDot"/><div><b>حساب تشغيل الفرع</b><small>QA</small></div></div>
      <nav>
        <div className="navGroup"><div className="sideCaption">تشغيل الفرع</div>{branchOperatorSections.filter(item => !item.locked).map(renderSection)}</div>
        <div className="navGroup"><div className="sideCaption">صلاحيات المدير</div>{branchOperatorSections.filter(item => item.locked).map(renderSection)}</div>
      </nav>
      <div className="sideFooter"><button type="button" className="logout" onClick={() => client.auth.signOut()}><LogOut aria-hidden="true"/> تسجيل الخروج</button></div>
    </aside>
    <main className="adminMain">
      <div className="mobileBar"><button type="button" aria-label="فتح أقسام الفرع" aria-controls="qa-branch-navigation" aria-expanded={mobile} onClick={() => setMobile(value => !value)}><Menu size={18}/></button><div><small>{branch.name}</small><b>{section.label}</b></div></div>
      <header className="pageHead"><div><p>{branch.name} · {branch.location} · QA</p><h1>{section.label}</h1></div></header>
      <section className="panel qaBranchCenter">
        {section.locked ? <div className="workspacePermissionNote" role="status"><LockKeyhole size={17} aria-hidden="true"/> هذا القسم متاح لحساب المدير العام.</div>
          : section.id === 'suppliers' ? <BranchSuppliers client={client} branchId={branchId}/>
          : <>
            <RecordEvent key={section.id} client={client} branchId={branchId} kinds={section.kinds}
              onRecorded={() => {setDay(branchToday());refresh(value => value + 1);}}/>
            <div className="qaBranchControls">
              <label>تاريخ السجل<input type="date" value={day} max={branchToday()} onChange={event => {if (event.target.value) setDay(event.target.value);}}/></label>
              <button type="button" onClick={() => refresh(value => value + 1)}>تحديث السجل</button>
            </div>
            {!current && <p role="status">جارٍ تحميل السجل…</p>}
            {current?.data && <OperatorActivity data={current.data} section={section}/>}
          </>}
      </section>
    </main>
  </div>;
}

export function QaBranchPortal({client, branchId, user}) {
  if (user) return <SignedInBranch key={user.id + branchId} client={client} branchId={branchId}/>;
  return <main className="panel qaBranchCenter qaBranchPortal" dir="rtl">
    <header className="qaBranchIntro">
      <div><h2>بوابة الفرع</h2><p>QA · سجل تشغيل تجريبي مستقل لكل فرع</p></div>
    </header>
    <BranchSignIn client={client} branchId={branchId}/>
    <a href="/#admin">العودة إلى دخول الإدارة</a>
  </main>;
}
