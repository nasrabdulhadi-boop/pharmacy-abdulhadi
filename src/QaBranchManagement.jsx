import React, { useState } from 'react';
import { Store, WalletCards, Receipt, Package, AlertCircle } from 'lucide-react';
import { demoBranches } from './qaBranchDemo.js';
import './QA_BRANCH_MANAGEMENT.css';

const number = new Intl.NumberFormat('ar-SY');
const amount = value => `${number.format(value)} ل.س`;
const dollars = value => `${number.format(value)} د.أ`;
const sum = (rows, read) => rows.reduce((total, row) => total + read(row), 0);
const missing = 'لم يُسجّل';
const cashStatus = branch => branch.difference === null ? 'بانتظار الإقفال' : branch.difference === 0 ? 'مطابق' : `فرق ${amount(branch.difference)}`;

function BranchTable({ caption, columns, rows }) {
  return <div className="qaBranchTable">
    <table>
      <caption>{caption}</caption>
      <thead><tr>{columns.map(label => <th key={label} scope="col">{label}</th>)}</tr></thead>
      <tbody>{rows.map(([id, label, ...cells]) => <tr key={id}>
        <th scope="row">{label}</th>
        {cells.map((cell, index) => <td key={columns[index + 1]}>{cell}</td>)}
      </tr>)}</tbody>
    </table>
  </div>;
}

export default function QaBranchManagement() {
  const [branchId, setBranchId] = useState('');
  const branch = demoBranches.find(item => item.id === branchId);
  const visible = branch ? [branch] : demoBranches;
  const alerts = visible.filter(item => item.lowStock || item.stockDifferences || item.difference !== 0);
  const metrics = [
    [Store, 'الفروع المعروضة', number.format(visible.length)],
    [Receipt, 'المبيعات اليوم', amount(sum(visible, item => item.sales))],
    [WalletCards, 'الصندوق المتوقع', amount(sum(visible, item => item.expected))],
    [Package, 'نواقص المخزون عبر الفروع', number.format(sum(visible, item => item.lowStock))],
  ];

  return <section className="qaBranchCenter" dir="rtl" aria-label="مركز إدارة الفروع">
    <div className="qaBranchIntro">
      <div><strong>بيانات اصطناعية · QA</strong><p>تابع وضع الصيدليات الخمس أو اختر فرعاً لعرض تفاصيله.</p></div>
      <label>عرض الفرع
        <select value={branchId} onChange={event => setBranchId(event.target.value)}>
          <option value="">كل الفروع</option>
          {demoBranches.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}
        </select>
      </label>
    </div>

    <div className="qaBranchMetrics" aria-live="polite">
      {metrics.map(([Icon, label, value]) => <article key={label}>
        <Icon size={19} aria-hidden="true"/><span>{label}</span><strong>{value}</strong>
      </article>)}
    </div>

    {!branch && <BranchTable caption="مقارنة الفروع اليوم"
      columns={['الفرع', 'مسؤول الفرع', 'المبيعات', 'فواتير البيع', 'حالة الصندوق']}
      rows={visible.map(item => [
        item.id,
        <button type="button" onClick={() => setBranchId(item.id)}>{item.name}</button>,
        item.staff,
        amount(item.sales),
        number.format(item.invoiceCount),
        cashStatus(item),
      ])}/>}
    {branch && <>
      <div className="qaBranchDetail">
        <h4>{branch.name}</h4><p>مسؤول الفرع · {branch.staff}</p>
        <dl>
          <div><dt>رصيد الافتتاح</dt><dd>{amount(branch.openingCash)}</dd></div>
          <div><dt>الصندوق المعدود</dt><dd>{branch.counted === null ? missing : amount(branch.counted)}</dd></div>
          <div><dt>مطابقة الإقفال</dt><dd>{cashStatus(branch)}</dd></div>
        </dl>
      </div>
      <BranchTable caption="المخزون والجرد" columns={['الصنف', 'الرصيد', 'الحد الأدنى', 'المعدود', 'فرق الجرد']}
        rows={branch.inventory.map(item => [item.name, item.name, number.format(item.quantity), number.format(item.reorder),
          item.counted === null ? missing : number.format(item.counted),
          item.counted === null ? '—' : number.format(item.counted - item.quantity)])}/>
      <BranchTable caption="حركة الفواتير اليوم" columns={['الفاتورة', 'العملية', 'القيمة', 'أثرها على الصندوق']}
        rows={branch.activity.map(entry => [entry.id, <bdi>{entry.id}</bdi>, entry.type, amount(entry.value), amount(entry.cash)])}/>
    </>}

    <div className="qaBranchDetail">
      <h4>الديون حسب العملة</h4>
      <dl>
        <div><dt>ديون الزبائن</dt><dd>{amount(sum(visible, item => item.debts.customersSyp))}</dd></div>
        <div><dt>ديون الموردين بالليرة</dt><dd>{amount(sum(visible, item => item.debts.suppliersSyp))}</dd></div>
        <div><dt>ديون الموردين بالدولار</dt><dd>{dollars(sum(visible, item => item.debts.suppliersUsd))}</dd></div>
      </dl>
    </div>
    <div className="qaBranchDetail">
      <h4><AlertCircle size={17} aria-hidden="true"/> تنبيهات المتابعة</h4>
      {alerts.length ? <ul>{alerts.map(item => <li key={item.id}>
        <strong>{item.name}</strong>
        {item.lowStock > 0 && <span>أصناف تحت حد الطلب أو عنده · {number.format(item.lowStock)}</span>}
        {item.stockDifferences > 0 && <span>فروقات الجرد · {number.format(item.stockDifferences)}</span>}
        {item.difference !== 0 && <span>{cashStatus(item)}</span>}
      </li>)}</ul> : <p>لا توجد تنبيهات لهذا الفرع.</p>}
    </div>
  </section>;
}
