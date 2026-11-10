import {normalizeSystemLanguage} from './systemLanguages.js';
import {getSystemDirection, uiText} from './systemLocale.js';

const key = 'pharmacy_qa_device_setup_v1';
export const printKinds = {
 receipt: {label:'إيصال البيع', paper:'80mm'},
 supplier: {label:'كشف المورد', paper:'A4'},
 report: {label:'التقرير المالي', paper:'A4'},
};
const clean = (value, max) => typeof value === 'string' ? value.trim().slice(0, max) : '';
export function normalizeDeviceSetup(value) {
 const templates = Object.fromEntries(Object.entries(printKinds).map(([id, defaults]) => {
  const item = value?.templates?.[id];
  return [id, {
   paper: ['80mm', 'A4'].includes(item?.paper) ? item.paper : defaults.paper,
   title: clean(item?.title, 90),
   logo: item?.logo !== false,
   date: item?.date !== false,
  }];
 }));
 return {templates, device: {
  name: clean(value?.device?.name, 80),
  printer: clean(value?.device?.printer, 100),
  drawer: clean(value?.device?.drawer, 100),
 }};
}

export function readDeviceSetup() {
 try { return normalizeDeviceSetup(JSON.parse(localStorage.getItem(key))); }
 catch { return normalizeDeviceSetup(null); }
}

export function saveDeviceSetup(setup) {
 localStorage.setItem(key, JSON.stringify(normalizeDeviceSetup(setup)));
}

export function makeSetupPackage(setup, appearance) {
 return {
  format: 'pharmacy-qa-setup-v1',
  templates: normalizeDeviceSetup(setup).templates,
  appearance: {language:normalizeSystemLanguage(appearance.language), density:appearance.density==='compact'?'compact':'comfortable'},
 };
}

export function readSetupPackage(text) {
 const value = JSON.parse(text);
 if (value?.format !== 'pharmacy-qa-setup-v1' || !value.templates || !value.appearance ||
     !Object.keys(printKinds).every(id => ['80mm','A4'].includes(value.templates[id]?.paper)) ||
     !['compact','comfortable'].includes(value.appearance.density) ||
     normalizeSystemLanguage(value.appearance.language) !== value.appearance.language) throw Error('حزمة الإعدادات غير صالحة.');
 return makeSetupPackage(value, value.appearance);
}

const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, ch => ({
 '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;',
}[ch]));
const printedHeader = (template, title, logo) =>
 `<header>${template.logo ? `<img src="${escapeHtml(logo)}" alt="">` : ''}<h1>${escapeHtml(template.title || title)}</h1>${template.date ? `<p>${escapeHtml(new Date().toLocaleString('en-GB'))}</p>` : ''}</header>`;

export function printAdminDocument(kind, {title, columns, rows, total, sample=false}, setup=readDeviceSetup()) {
 const template = normalizeDeviceSetup(setup).templates[kind];
 if (!template) return;
 const frame = document.createElement('iframe');
 frame.title = uiText('معاينة الطباعة');
 frame.style.cssText = 'position:fixed;width:1px;height:1px;opacity:0;pointer-events:none;border:0';
 const logo = new URL('/logo.png', window.location.origin).href;
 const table = rows.map(row => '<tr>'+row.map(cell => '<td>'+escapeHtml(cell)+'</td>').join('')+'</tr>').join('');
 frame.srcdoc = `<!doctype html><html dir="${getSystemDirection()}"><meta charset="utf-8">
 <style>@page{size:${template.paper==='80mm'?'auto':'A4'};margin:${template.paper==='80mm'?'3mm':'12mm'}}
 body{font:14px sans-serif;color:#152922;width:${template.paper==='80mm'?'74mm':'auto'};margin:0}
 header{border-bottom:2px solid #207454;margin-bottom:12px}header img{width:42px;float:inline-end}
 h1{font-size:18px}table{width:100%;border-collapse:collapse;overflow-wrap:anywhere}
 th,td{text-align:start;padding:6px;border-bottom:1px solid #ddd}tr{break-inside:avoid}</style>
 ${printedHeader(template,title,logo)}${sample ? '<p>'+escapeHtml(uiText('نسخة تجريبية للطباعة'))+'</p>' : ''}
 <table><thead><tr>${columns.map(column=>'<th>'+escapeHtml(column)+'</th>').join('')}</tr></thead><tbody>${table}</tbody></table>
 ${total ? '<p><strong>'+escapeHtml(total)+'</strong></p>' : ''}</html>`;
 const cleanup = () => frame.remove();
 frame.addEventListener('load', () => {
  frame.contentWindow.addEventListener('afterprint', cleanup, {once:true});
  try {frame.contentWindow.print();} finally {setTimeout(cleanup, 120_000);}
 }, {once:true});
 document.body.append(frame);
}

export function printConfiguredReport() {
 const template = readDeviceSetup().templates.report;
 const css = document.createElement('style');
 css.textContent = '@media print{@page{size:'+ (template.paper==='80mm'?'auto':'A4') +';margin:'+ (template.paper==='80mm'?'3mm':'12mm') +'}'+
  '.qaPrintHeader{display:block!important;padding-bottom:8px;border-bottom:1px solid #333;margin-bottom:12px}}';
 const header = document.createElement('div');
 header.className = 'qaPrintHeader';
 header.hidden = true;
 header.innerHTML = printedHeader(template,uiText('التقرير المالي'),new URL('/logo.png',window.location.origin).href);
 const container = document.querySelector('.adminMain') || document.querySelector('main') || document.body;
 container.prepend(header);
 document.head.append(css);
 try { window.print(); } finally { header.remove(); css.remove(); }
}
