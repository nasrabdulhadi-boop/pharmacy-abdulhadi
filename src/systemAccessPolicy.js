// Preview-only access policy specification. This is NOT a database authorization mechanism.
// Manifest only: employee operations remain disabled until dedicated audited RLS/RPC enforcement and manager approvals are implemented.
export const ROLES = Object.freeze(['system_owner','system_admin','technical_support','employee']);
export const CAPABILITIES = Object.freeze([
 'system.view_technical_health',
 'system.view_sanitized_diagnostics',
 'system.manage_users',
 'system.manage_security',
 'system.manage_backups',
 'pharmacy.read_sensitive',
 'pharmacy.write_operations',
 'finance.read',
 'finance.write',
 'employee.pos_sale','employee.catalog_read','employee.inventory_read','employee.inventory_count_submit','employee.purchase_draft_create','employee.order_process','employee.return_request_create','employee.supplier_operational_read',
 'employee.price_change','employee.invoice_delete','employee.finance_manage','employee.user_manage'
]);
const permissions = {
 system_owner: CAPABILITIES,
 system_admin: [
  'system.view_technical_health','system.view_sanitized_diagnostics',
  'system.manage_users','pharmacy.read_sensitive','pharmacy.write_operations',
  'finance.read','finance.write'
 ],
 technical_support: ['system.view_technical_health','system.view_sanitized_diagnostics'],
 employee: ['employee.pos_sale','employee.catalog_read','employee.inventory_read','employee.inventory_count_submit','employee.purchase_draft_create','employee.order_process','employee.return_request_create','employee.supplier_operational_read']
};
export const ROLE_CAPABILITIES = Object.freeze(Object.fromEntries(
 Object.entries(permissions).map(([role,caps])=>[role,Object.freeze([...caps])])
));
export function hasCapability(role,capability){
 return ROLES.includes(role) && CAPABILITIES.includes(capability) &&
  ROLE_CAPABILITIES[role].includes(capability);
}
export function sanitizeTechnicalDiagnostic(input){
 // Strict allowlist: never pass raw errors, SQL messages, URLs, user IDs or free-text metadata.
 const status = ['healthy','degraded','unavailable','unknown'].includes(input?.status)?input.status:'unknown';
 const component = ['authentication','api','database','deployment'].includes(input?.component)?input.component:'unknown';
 const timestamp = typeof input?.observedAt === 'string' && input.observedAt.length <= 35 && input.observedAt.endsWith('Z') && Number.isFinite(Date.parse(input.observedAt)) && new Date(input.observedAt).toISOString().slice(0,19) === input.observedAt.slice(0,19) ? input.observedAt : null;
 return Object.freeze({status,component,observedAt:timestamp});
}
