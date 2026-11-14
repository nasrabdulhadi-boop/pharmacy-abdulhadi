const fields = ['active_ingredient', 'strength', 'dosage_form'];

function normalizeCatalogField(value) {
  return String(value ?? '').normalize('NFC').trim().replace(/\s+/g, ' ').toLowerCase();
}

function comparableField(product, field) {
  const value = normalizeCatalogField(product[field]);
  if (field === 'dosage_form' && ['tab','tap','تاب','tablet','tablets','أقراص','قرص'].includes(value)) return 'tab';
  if (field === 'strength') {
    return value
      .replace(/[٠-٩۰-۹]/g, digit => String(digit.charCodeAt(0) % 16))
      .replace(/٫/g, '.')
      .replace(/(?:ملغ|ملجم|مغ|ملغرام|mg)(?![a-z])/gu, 'mg')
      .replace(/(\d)\s+(?=[a-z\p{Script=Arabic}])/gu, '$1')
      .replace(/\s*([/+])\s*/g, '$1');
  }
  return value;
}

export function hasCatalogMatchFields(product) {
  return fields.every(field => {
    const value = normalizeCatalogField(product[field]);
    return /[\p{L}\p{N}]/u.test(value) && !['unknown', 'n/a', 'null', 'غير معروف', 'غير محدد'].includes(value);
  });
}

export function findCatalogMatches(source, products) {
  if (!hasCatalogMatchFields(source)) return [];
  return products.filter(product =>
    product.id !== source.id &&
    hasCatalogMatchFields(product) &&
    fields.every(field => comparableField(product, field) === comparableField(source, field))
  ).sort((a,b) => Number(Number(b.stock)>0)-Number(Number(a.stock)>0));
}
