// Preview-only access policy specification. This is NOT a database authorization mechanism.
// No role is provisioned until RLS and SECURITY DEFINER RPC checks pass in isolated staging.
export const ROLES = Object.freeze(['system_owner','system_admin','technical_support']);
export const CAPABILITIES = Object.freeze([
 'system.view_technical_health',
 'system.view_sanitized_diagnostics',
 'system.manage_users',
 'system.manage_security',
 'system.manage_backups',
 'pharmacy.read_sensitive',
 'pharmacy.write_operations',
 'finance.read',
 'finance.write'
]);
const permissions = {
 system_owner: CAPABILITIES,
 system_admin: [
  'system.view_technical_health','system.view_sanitized_diagnostics',
  'system.manage_users','pharmacy.read_sensitive','pharmacy.write_operations',
  'finance.read','finance.write'
 ],
 technical_support: ['system.view_technical_health','system.view_sanitized_diagnostics']
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
 const timestamp = typeof input?.observedAt==='string' && /^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?Z$/.test(input.observedAt)?input.observedAt:null;
 return Object.freeze({status,component,observedAt:timestamp});
}
