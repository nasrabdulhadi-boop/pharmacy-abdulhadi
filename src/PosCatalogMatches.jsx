import {uiText} from './systemLocale.js';
import React, {useEffect, useState} from 'react';
import {findCatalogMatches, hasCatalogMatchFields} from './posCatalogMatches.js';

export default function PosCatalogMatches({product, supabase, money, autoLoad=false}) {
  const [state, setState] = useState({status:'idle', matches:[]});
  const complete = hasCatalogMatchFields(product);

  useEffect(() => { if (autoLoad) load(); }, [autoLoad]);

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

  return <section aria-label={uiText("مطابقات دليل الأدوية")}>
    <div className="detailGrid">
      <div><b>{uiText("المادة الفعالة")}</b><span>{product.active_ingredient || '—'}</span></div>
      <div><b>{uiText("التركيز")}</b><span>{product.strength || '—'}</span></div>
      <div><b>{uiText("الشكل الصيدلاني")}</b><span>{product.dosage_form || '—'}</span></div>
    </div>
    {complete
      ? <button type="button" className="secondaryAction" onClick={load} disabled={state.status === 'loading'}>
          {state.status === 'loading' ? uiText("جارٍ البحث…") : uiText("عرض البدائل حسب الدليل")}
        </button>
      : <p className="muted">{uiText("أكمل المادة الفعالة والتركيز والشكل الصيدلاني لعرض المطابقات.")}</p>}
    {state.status === 'error' && <p role="alert">{uiText("تعذر تحميل المطابقات. أعد المحاولة.")}</p>}
    {state.status === 'ready' && <>
      <p className="muted">{uiText("مطابقات حسب بيانات الدليل. تحقّق من العبوة وطريق الإعطاء ونوع التحرّر والتكافؤ العلاجي قبل الاستبدال.")}</p>
      {state.limited && <p className="muted">{uiText("شمل البحث أول 100 نتيجة من الدليل.")}</p>}
      {state.matches.length ? <div className="tableWrap"><table>
        <thead><tr><th>{uiText("الدواء")}</th><th>{uiText("الباركود")}</th><th>{uiText("الرصيد الصالح")}</th><th>{uiText("سعر المبيع")}</th></tr></thead>
        <tbody>{state.matches.map(match => <tr key={match.id}>
          <td>{match.name}</td><td>{match.barcode || '—'}</td><td>{Number(match.stock)>0 ? money(match.stock) : uiText("غير متوفر")}</td>
          <td>{match.sale_price_syp == null ? '—' : money(match.sale_price_syp)+' ل.س'}</td>
        </tr>)}</tbody>
      </table></div> : <p role="status">{uiText("ما ظهر صنف آخر بنفس الاسم العلمي والعيار والشكل الصيدلاني ضمن نتائج البحث.")}</p>}
    </>}
  </section>;
}
