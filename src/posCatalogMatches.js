const fields = ['active_ingredient', 'strength', 'dosage_form'];

function normalizeCatalogField(value) {
  return String(value ?? '').normalize('NFC').trim().replace(/\s+/g, ' ').toLowerCase();
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
    Number(product.stock) > 0 &&
    hasCatalogMatchFields(product) &&
    fields.every(field => normalizeCatalogField(product[field]) === normalizeCatalogField(source[field]))
  );
}
