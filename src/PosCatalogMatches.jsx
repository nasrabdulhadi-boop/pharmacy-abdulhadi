import React, {useState} from 'react';
import {findCatalogMatches, hasCatalogMatchFields} from './posCatalogMatches.js';

export default function PosCatalogMatches({product, supabase, money}) {
  const [state, setState] = useState({status:'idle', matches:[]});
  const complete = hasCatalogMatchFields(product);

  async function load() {
    if (!complete || state.status === 'loading') return;
    setState({status:'loading', matches:[]});
    try {
      const {data, error} = await supabase.rpc('admin_search_pos_products_currency', {
        p_query:product.active_ingredient.trim(),
        p_limit:100
      });
      if (error) throw error;
      const rows = data || [];
      setState({status:'ready', matches:findCatalogMatches(product, rows), limited:rows.length >= 100});
    } catch {
      setState({status:'error', matches:[]});
    }
  }

  return <section aria-label="مطابقات دليل الأدوية">
    <div className="detailGrid">
      <div><b>المادة الفعالة</b><span>{product.active_ingredient || '—'}</span></div>
      <div><b>التركيز</b><span>{product.strength || '—'}</span></div>
      <div><b>الشكل الصيدلاني</b><span>{product.dosage_form || '—'}</span></div>
    </div>
    {complete
      ? <button type="button" className="secondaryAction" onClick={load} disabled={state.status === 'loading'}>
          {state.status === 'loading' ? 'جارٍ البحث…' : 'عرض مطابقات الدليل'}
        </button>
      : <p className="muted">أكمل المادة الفعالة والتركيز والشكل الصيدلاني لعرض المطابقات.</p>}
    {state.status === 'error' && <p role="alert">تعذر تحميل المطابقات. أعد المحاولة.</p>}
    {state.status === 'ready' && <>
      <p className="muted">مطابقات حسب بيانات الدليل. تحقّق من العبوة وطريق الإعطاء ونوع التحرّر والتكافؤ العلاجي قبل الاستبدال.</p>
      {state.limited && <p className="muted">شمل البحث أول 100 نتيجة من الدليل.</p>}
      {state.matches.length ? <div className="tableWrap"><table>
        <thead><tr><th>الدواء</th><th>الباركود</th><th>الرصيد الصالح</th><th>سعر المبيع</th></tr></thead>
        <tbody>{state.matches.map(match => <tr key={match.id}>
          <td>{match.name}</td><td>{match.barcode || '—'}</td><td>{money(match.stock)}</td>
          <td>{match.sale_price_syp == null ? '—' : money(match.sale_price_syp)+' ل.س'}</td>
        </tr>)}</tbody>
      </table></div> : <p role="status">ما ظهر صنف مطابق برصيد صالح ضمن نتائج البحث.</p>}
    </>}
  </section>;
}
