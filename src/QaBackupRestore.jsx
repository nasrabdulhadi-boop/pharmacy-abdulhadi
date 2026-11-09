import React, {useEffect, useRef, useState} from 'react';
import {getSystemLanguage, uiText, uiTemplate} from './systemLocale.js';

const MAX_FILE_BYTES = 70 * 1024 * 1024;
const TIMEOUT_MS = 120_000;

const recoveryLabels = {
 ar: ['نجح تشغيل القاعدة المستعادة من جديد وتطابقت سجلاتها.', 'اعتماد النسخة على النظام المستضاف غير متاح قبل اختبار الاستعادة الكاملة.', 'تنزيل تقرير التحقق'],
 en: ['The recovered database restarted and its records matched.', 'Hosted activation requires a verified full recovery.', 'Download verification report'],
 ru: ['База перезапущена, записи совпали.', 'Для запуска на сервере нужна проверка полного восстановления.', 'Скачать отчёт проверки'],
 tr: ['Veritabanı yeniden başlatıldı ve kayıtlar eşleşti.', 'Barındırılan sistemde etkinleştirme için tam kurtarma doğrulanmalıdır.', 'Doğrulama raporunu indir'],
 ro: ['Baza repornită conține aceleași înregistrări.', 'Activarea pe server necesită verificarea recuperării complete.', 'Descarcă raportul de verificare'],
 fr: ['La base restaurée a redémarré et les données correspondent.', 'L’activation hébergée exige une restauration complète vérifiée.', 'Télécharger le rapport de vérification'],
 de: ['Die wiederhergestellte Datenbank wurde neu gestartet. Die Datensätze stimmen überein.', 'Die Aktivierung auf dem Server erfordert eine geprüfte vollständige Wiederherstellung.', 'Prüfbericht herunterladen'],
};

export default function QaBackupRestore({verifyActor}) {
 const [file, setFile] = useState(null);
 const [phrase, setPhrase] = useState('');
 const [busy, setBusy] = useState(false);
 const [message, setMessage] = useState('');
 const [recovery, setRecovery] = useState(null);
 const active = useRef(null);
 const download = useRef(null);
 const reportDownload = useRef(null);
 const [restartPassed, activationBlocked, reportLabel] = recoveryLabels[getSystemLanguage()] || recoveryLabels.en;

 function clearDownload() {
  if (download.current) URL.revokeObjectURL(download.current);
  download.current = null;
  if (reportDownload.current) URL.revokeObjectURL(reportDownload.current);
  reportDownload.current = null;
 }

 useEffect(() => () => {
  active.current?.stop();
  active.current = null;
  clearDownload();
 }, []);

 async function restore(event) {
  event.preventDefault();
  if (active.current || !file || file.size > MAX_FILE_BYTES || phrase.length < 16) return;
  const job = {stop() {}};
  active.current = job;
  clearDownload();
  setRecovery(null);
  setMessage('');
  setBusy(true);
  setPhrase('');

  let worker;
  let timer;
  try {
   await verifyActor();
   if (active.current !== job) return;
   const recovered = await new Promise((resolve, reject) => {
    worker = new Worker(new URL('./qaRestore.worker.js', import.meta.url), {type: 'module'});
    job.stop = () => {
     worker.terminate();
     clearTimeout(timer);
     reject(new Error('restore_cancelled'));
    };
    timer = setTimeout(job.stop, TIMEOUT_MS);
    worker.onmessage = ({data}) => data.code ? reject(new Error(data.code)) : resolve(data);
    worker.onerror = () => reject(new Error('restore_failed'));
    worker.onmessageerror = () => reject(new Error('restore_failed'));
    worker.postMessage({file, phrase});
   });
   if (active.current !== job) return;
   await verifyActor();
   if (active.current !== job) return;
   if (!recovered.result?.localRestartVerified || !recovered.result.allRowsMatch || !(recovered.database instanceof Blob) || !recovered.database.size) {
    throw new Error('restore_failed');
   }
   download.current = URL.createObjectURL(recovered.database);
   const {tables, rows, archiveSummary} = recovered.result;
   const report = {
    format: 'pharmacy-recovery-verification-v1',
    verifiedAt: new Date().toISOString(),
    scope: 'isolated-qa-local-database',
    sourceArchiveSha256: recovered.sourceArchiveSha256,
    tables,
    rows,
    attachmentChecksumsVerified: archiveSummary.files,
    databaseRestartVerified: true,
    recordsMatchedAfterRestart: true,
    hostedApplicationVerified: false,
    hostedAuthenticationVerified: false,
    hostedStorageVerified: false,
    activation: 'blocked',
   };
   reportDownload.current = URL.createObjectURL(new Blob([JSON.stringify(report, null, 2)], {type: 'application/json'}));
   setRecovery({url: download.current, reportUrl: reportDownload.current, tables, rows});
  } catch (error) {
   if (active.current !== job) return;
   if (error.message === 'backup_decryption_failed') {
    setMessage('تعذر فك التشفير. تحقق من العبارة وسلامة الملف.');
   } else if (error.message === 'archive_requires_exact_decimal_encoding') {
    setMessage('هذه النسخة قديمة. جهّز نسخة جديدة تدعم استعادة الأرقام بدقة.');
   } else if (error.message === 'restore_cancelled') {
    setMessage('انتهت مهلة الاستعادة المحلية.');
   } else {
    setMessage('تعذرت الاستعادة المحلية.');
   }
  } finally {
   clearTimeout(timer);
   worker?.terminate();
   if (active.current === job) {
    active.current = null;
    setBusy(false);
   }
  }
 }

 return <form className="adminSettingsCard adminBackupVerify" onSubmit={restore}>
  <h4>{uiText('استعادة البيانات محلياً')}</h4>
  <p>{uiText('تُستعاد الجداول في قاعدة معزولة داخل المتصفح. تبقى الملفات المرفقة في النسخة المشفرة.')}</p>
  <label>{uiText('اختيار نسخة مشفرة')}
   <input type="file" accept=".json,application/json" disabled={busy} onChange={event => {
    const next = event.target.files?.[0];
    clearDownload();
    setRecovery(null);
    setFile(next && next.size <= MAX_FILE_BYTES ? next : null);
    setMessage(next?.size > MAX_FILE_BYTES ? 'ملف النسخة أكبر من الحد المدعوم (70 MiB).' : '');
   }}/>
  </label>
  <label>{uiText('عبارة تشفير النسخة')}
   <input type="password" autoComplete="off" minLength={16} maxLength={1024}
    required disabled={busy} value={phrase} onChange={event => setPhrase(event.target.value)}/>
  </label>
  <button type="submit" disabled={busy || !file || phrase.length < 16}>
   {uiText(busy ? 'جارٍ استعادة البيانات…' : 'استعادة نسخة محلية')}
  </button>
  {message && <p role="status">{uiText(message)}</p>}
  {recovery && <div role="status">
   <p>{uiTemplate(['تمت استعادة ', ' جدول و', ' سجل ومطابقتها مع النسخة.'], [recovery.tables, recovery.rows])}</p>
   <p>{restartPassed}</p>
   <p>{activationBlocked}</p>
   <p><a href={recovery.reportUrl} download="Pharmacy_QA_Recovery_Report.json">{reportLabel}</a></p>
   <a href={recovery.url} download="Pharmacy_QA_Recovered.pglite.tar.gz">{uiText('تنزيل قاعدة البيانات المستعادة')}</a>
   <p>{uiText('الملف المستعاد غير مشفر ومخصص لـ PGlite. احفظه في مكان محمي.')}</p>
  </div>}
 </form>;
}
