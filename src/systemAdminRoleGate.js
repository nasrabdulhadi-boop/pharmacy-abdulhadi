// Presentation-only guard. All database authorization must be enforced by RLS and RPC.
const ROLE_ALLOWLIST=Object.freeze(['system_owner','system_admin','technical_support']);
export function verifiedSystemRole(user){
 const role=user?.app_metadata?.system_role;
 if(ROLE_ALLOWLIST.includes(role))return role;
 if(role===undefined&&user?.app_metadata?.role==='admin')return 'system_admin';
 return null;
}
export function canViewSystemAdminSection(role,section){
 if(role==='technical_support')return section==='overview';
 if(role==='system_owner'||role==='system_admin')return ['overview','profile','access','backup','preferences'].includes(section);
 return false;
}
