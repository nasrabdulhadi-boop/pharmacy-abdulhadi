import React, { useEffect, useRef, useState } from 'react';
import QaBranchManagement from './QaBranchManagement.jsx';
import { branchKinds, comparisonMetrics, branchMoney, branchNumber, branchToday, orderBranches, branchLink, readBranchDay } from './qaBranchWorkspace.js';

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

function RecordEvent({client, branchId, onRecorded}) {
  const [kind, setKind] = useState('sale');
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
        const saved = await client.from('qa_branch_events').select('id').eq('branch_id',branchId).eq('id',request.current.id).maybeSingle();
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
    <h4>تسجيل حركة تجريبية</h4>
    <label>نوع الحركة <select value={kind} onChange={event => setKind(event.target.value)}>
      {Object.entries(branchKinds).map(([id,label]) => <option key={id} value={id}>{label}</option>)}
    </select></label>
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

function SignedInBranch({ client, branchId }) {
  const [claim, setClaim] = useState(null);
  const [day, setDay] = useState(branchToday);
  const [revision, refresh] = useState(0);
  useEffect(() => {
    let active = true;
    client.rpc('qa_claim_branch',{p_branch:branchId}).then(({error}) => {
      if (active) setClaim(!error);
    }).catch(() => {
      if (active) setClaim(false);
    });
    return () => { active = false; };
  }, [client, branchId]);
  if (claim === null) return <p role="status">جارٍ التحقق من صلاحية الدخول للفرع…</p>;
  if (claim === false) return <p role="alert">تعذّر التحقق من صلاحية الفرع.</p>;
  return <BranchOperations client={client} branchId={branchId} day={day} setDay={setDay} revision={revision} refresh={refresh}/>;
}

function BranchOperations({ client, branchId, day, setDay, revision, refresh }) {
  const detail = useDay(client, day, branchId, revision);
  const branch = detail?.data?.branches[0];
  const [confirmed, setConfirmed] = useState(false);
  useEffect(() => { if (branch) setConfirmed(true); }, [branch]);
  return <>
    {(branch || (!detail && confirmed)) && <RecordEvent client={client} branchId={branchId} onRecorded={() => {setDay(branchToday());refresh(value => value + 1);}}/>}
    <label>تاريخ التقرير <input type="date" value={day} max={branchToday()} onChange={event => { if (event.target.value) setDay(event.target.value); }}/></label>
    {!detail && <p role="status">جارٍ تحميل بيانات الفرع…</p>}
    {detail && !branch && <p role="alert">{detail.error ? 'تعذّر تحميل الفرع.' : 'هذا الرابط غير متاح للحساب الحالي. ادخل بالبريد المدعو.'}</p>}
    {branch && <BranchDetails data={detail.data} branch={branch}/>}
  </>;
}

export function QaBranchPortal({client, branchId, user}) {
  return <main className="panel qaBranchCenter qaBranchPortal" dir="rtl">
    <header className="qaBranchIntro">
      <div><h2>بوابة الفرع</h2><p>QA · سجل تشغيل تجريبي مستقل لكل فرع</p></div>
      {user && <button type="button" onClick={() => client.auth.signOut()}>تسجيل الخروج</button>}
    </header>
    {user ? <SignedInBranch key={user.id + branchId} client={client} branchId={branchId}/> : <BranchSignIn client={client} branchId={branchId}/>}
    <a href="/#admin">العودة إلى دخول الإدارة</a>
  </main>;
}
