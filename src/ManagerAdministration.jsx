import React, {useEffect, useState} from 'react';
import {Home, Users, ShieldCheck, Sparkles} from 'lucide-react';
import {verifiedSystemRole} from './systemAdminRoleGate.js';
import {readAdminPreferences, writeAdminPreferences} from './systemAdminPreferences.js';
import './SYSTEM_ADMIN_WINDOW_POLISH.css';
import './SYSTEM_ADMIN_REBUILD_V3.css';

const sections = [
  ['overview', 'نظرة عامة', Home],
  ['profile', 'الملف الشخصي', Users],
  ['preferences', 'المظهر', Sparkles],
];

export default function ManagerAdministration({client, darkMode, setDarkMode, openAudit}) {
  const [section, setSection] = useState('overview');
  const [identity, setIdentity] = useState({status: 'checking'});
  const [preferences, setPreferences] = useState(() => readAdminPreferences(window.localStorage));
  const [message, setMessage] = useState('');
  useEffect(() => {
    let active = true;
    async function verify() {
      try {
        const {data, error} = await client.auth.getUser();
        const role = verifiedSystemRole(data?.user);
        if (error || !['system_admin', 'system_owner'].includes(role)) throw Error();
        if (active) setIdentity({status: 'verified', email: data.user.email, role});
      } catch {
        if (active) setIdentity({status: 'unavailable'});
      }
    }
    verify();
    return () => { active = false; };
  }, [client]);
  function changeDensity(density) {
    const next = {...preferences, density};
    if (writeAdminPreferences(window.localStorage, next)) {
      setPreferences(next);
      setMessage('');
    } else {
      setMessage('تعذّر حفظ الإعداد على هذا الجهاز.');
    }
  }
  if (identity.status !== 'verified') return <p role="status">{identity.status === 'checking' ? 'جارٍ التحقق من حساب المدير…' : 'تعذّر التحقق من صلاحية المدير.'}</p>;
  const roleLabel = identity.role === 'system_owner' ? 'مالك النظام' : 'مدير النظام';
  return <div className="panel systemAdminModern" dir="rtl" data-density={preferences.density}>
    <header className="systemAdminTopbar"><div className="systemAdminBrand"><ShieldCheck/><h2>مركز إدارة النظام</h2></div></header>
    <nav className="systemAdminTabs systemAdminTabsTop" aria-label="أقسام مركز الإدارة">{sections.map(([id, label, Icon]) =>
      <button type="button" key={id} className={section === id ? 'primary' : ''} aria-current={section === id ? 'page' : undefined} onClick={() => setSection(id)}><Icon size={18}/>{label}</button>)}</nav>
    <div className="systemAdminMain" style={{padding: preferences.density === 'compact' ? 12 : 24}}>
      <h3>{sections.find(([id]) => id === section)[1]}</h3>
      {section === 'overview' && <section className="systemAdminOverview"><div className="systemAdminMetrics"><article className="systemAdminMetric"><span>جلسة الحساب</span><strong>مؤكدة</strong></article><article className="systemAdminMetric"><span>دور الحساب</span><strong>{roleLabel}</strong></article></div><button type="button" onClick={openAudit}>فتح الأمان والتدقيق</button></section>}
      {section === 'profile' && <div className="adminIdentityCard"><Users/><div><span>البريد الإلكتروني</span><b dir="ltr">{identity.email}</b></div><span>{roleLabel}</span></div>}
      {section === 'preferences' && <section className="adminPreferencesGrid"><label>مظهر النظام<select value={darkMode ? 'dark' : 'light'} onChange={e => setDarkMode(e.target.value === 'dark')}><option value="light">نهاري</option><option value="dark">ليلي</option></select></label><label>كثافة عرض المركز<select value={preferences.density} onChange={e => changeDensity(e.target.value)}><option value="comfortable">مريح</option><option value="compact">مضغوط</option></select></label>{message && <p role="status">{message}</p>}</section>}
    </div>
  </div>;
}
