// Presentation-only guard. All database authorization must be enforced by RLS and RPC.
const ROLE_ALLOWLIST=Object.freeze(['system_owner','system_admin','technical_support']);
export function verifiedSystemRole(user){
 const role=user?.app_metadata?.system_role;
 return ROLE_ALLOWLIST.includes(role)?role:null;
}
export function canViewSystemAdminSection(role,section){
 if(role==='technical_support')return section==='overview';
 if(role==='system_owner'||role==='system_admin')return ['overview','profile','access','backup','preferences'].includes(section);
 return false;
}
