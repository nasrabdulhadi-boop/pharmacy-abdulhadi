const header = ['barcode', 'name', 'price', 'currency'];
const barcodePattern = /^QA-IMPORT-[A-Z0-9_-]{1,60}$/;
const decimalPattern = /^[0-9]{1,7}(\.[0-9]{1,4})?$/;

export const catalogSample = '\uFEFFbarcode,name,price,currency\r\nQA-IMPORT-DEMO-01,صنف تجريبي,12500,SYP\r\nQA-IMPORT-DEMO-02,صنف تجريبي بالدولار,2.75,USD\r\n';

export function readCatalogCsv(text) {
 const input = text.replace(/^\uFEFF/, '');
 const records = [];
 let record = [], field = '', quoted = false, closed = false;
 const delimiter = input.slice(0, input.indexOf('\n') < 0 ? input.length : input.indexOf('\n')).includes(';') ? ';' : ',';
 const pushField = () => { record.push(field); field = ''; closed = false; };
 const pushRecord = () => {
  pushField();
  if (record.some(value => value.trim())) records.push(record);
  record = [];
  if (records.length > 201) throw Error('عدد الصفوف يتجاوز 200.');
 };
 for (let i = 0; i < input.length; i++) {
  const c = input[i];
  if (quoted) {
   if (c !== '"') field += c;
   else if (input[i + 1] === '"') { field += '"'; i++; }
   else { quoted = false; closed = true; }
  } else if (c === delimiter) pushField();
  else if (c === '\n' || c === '\r') {
   if (c === '\r' && input[i + 1] === '\n') i++;
   pushRecord();
  } else if (c === '"' && !field && !closed) quoted = true;
  else if (c === '"' || closed) throw Error('صيغة CSV غير صالحة.');
  else field += c;
 }
 if (quoted) throw Error('صيغة CSV غير صالحة.');
 pushRecord();
 return catalogRows(records);
}

export function catalogRows(records) {
 const [columns, ...rows] = records;
 if (!columns || columns.length !== header.length || header.some((key, index) => String(columns[index] ?? '').trim().toLowerCase() !== key)) {
  throw Error('الأعمدة المطلوبة بالترتيب: barcode, name, price, currency.');
 }
 if (!rows.length || rows.length > 200) throw Error('اختر ملفاً فيه من 1 إلى 200 صف.');
 return rows.map((row, index) => ({
  row: index + 2,
  ...Object.fromEntries(header.map((key, col) => [key, String(row[col] ?? '').trim()])),
  invalidShape: row.length !== header.length || typeof row[0] === 'number',
 }));
}

export function previewCatalogImport(rows, products) {
 const occurrences = new Map();
 const byCode = new Map();
 for (const row of rows) occurrences.set(row.barcode, (occurrences.get(row.barcode) || 0) + 1);
 for (const product of products) {
  const key = product.barcode;
  const found = byCode.get(key) || [];
  found.push(product);
  byCode.set(key, found);
 }
 return rows.map(row => {
  const matches = byCode.get(row.barcode) || [];
  const previous = matches[0];
  const errors = [];
  if (row.invalidShape) errors.push('احفظ الباركود كنص وتحقق من عدد الأعمدة.');
  if (!barcodePattern.test(row.barcode)) errors.push('رمز تجريبي مطلوب يبدأ بـ QA-IMPORT-.');
  if (occurrences.get(row.barcode) > 1 || matches.length > 1) errors.push('الباركود مكرر.');
  if (!decimalPattern.test(row.price) || Number(row.price) > 1_000_000) errors.push('السعر غير صالح.');
  if (!['USD', 'SYP'].includes(row.currency)) errors.push('حدد USD أو SYP.');
  if (previous && previous.sale_currency !== row.currency) errors.push('عملة الصنف الحالي مختلفة.');
  if (!previous && (!row.name || row.name.length > 250)) errors.push('اسم الصنف الجديد مطلوب.');
  const samePrice = previous && Number(previous.sale_price) === Number(row.price);
  return {...row, errors, previous, mode: !previous ? 'create' : samePrice ? 'unchanged' : 'update'};
 });
}

export function catalogFindings(products) {
 const issues = [];
 const groups = new Map();
 const normalize = value => String(value ?? '').trim().normalize('NFKC').replace(/\s+/g, ' ').toLowerCase();
 for (const item of products) {
  const name = normalize(item.name), barcode = normalize(item.barcode);
  const missing = ['name', 'barcode', 'active_ingredient', 'strength', 'dosage_form'].filter(key => !normalize(item[key]));
  if (missing.length) issues.push({kind:'missing', items:[item], missing});
  for (const [kind, key] of [['barcode', barcode], ['similar', name]]) {
   if (!key) continue;
   const id = kind + ':' + key;
   if (!groups.has(id)) groups.set(id, {kind, items:[]});
   groups.get(id).items.push(item);
  }
 }
 return [...Array.from(groups.values()).filter(group => group.items.length > 1), ...issues];
}
