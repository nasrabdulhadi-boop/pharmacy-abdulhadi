// Read-only QA audit classifier. No credentials, SQL execution or production access.
const REQUIRED_ROLES=['system_owner','system_admin','technical_support'];
export function assessStagingAuthorization(snapshot){
 const issues=[];
 if(!snapshot||typeof snapshot!=='object'||Array.isArray(snapshot))return {ready:false,issues:['missing_audit_snapshot']};
 if(snapshot.environment!=='isolated-staging')issues.push('not_isolated_staging');
 if(snapshot.hasEmailAdminBypass!==false)issues.push('email_admin_bypass');
 if(snapshot.hasPublicDefinerExecute!==false)issues.push('public_definer_execute');
 if(snapshot.hasSensitiveSchemaCoverage!==true)issues.push('incomplete_sensitive_schema');
 if(!Array.isArray(snapshot.testedRoles)||REQUIRED_ROLES.some(role=>!snapshot.testedRoles.includes(role)))issues.push('missing_role_tests');
 if(snapshot.directApiDenyTestsPassed!==true)issues.push('direct_api_denials_unverified');
 if(snapshot.rpcDenyTestsPassed!==true)issues.push('rpc_denials_unverified');
 if(snapshot.revocationTestsPassed!==true)issues.push('revocation_unverified');
 if(snapshot.realAuthSessionTestsPassed!==true)issues.push('real_auth_session_unverified');
 if(snapshot.sessionRefreshTestsPassed!==true)issues.push('session_refresh_unverified');
 return {ready:issues.length===0,issues};
}
export const QA_AUTHORIZATION_FINDINGS=Object.freeze({
 environment:'isolated-staging',hasEmailAdminBypass:false,hasPublicDefinerExecute:false,
 hasSensitiveSchemaCoverage:false,testedRoles:[],directApiDenyTestsPassed:false,
 rpcDenyTestsPassed:false,revocationTestsPassed:false,
 realAuthSessionTestsPassed:false,sessionRefreshTestsPassed:false
});
