// A UI safety gate, not a server authorization mechanism.
// Backup and restore are forbidden until an independently audited server implementation exists.
export const BACKUP_STATES=Object.freeze(['not_configured','pending_verification','verified','failed']);
export function normalizeBackupState(state){return BACKUP_STATES.includes(state)?state:'not_configured';}
export function getBackupCenterStatus({backupState,restoreTestPassed=false,serverAuthorizationVerified=false}={}){
 const state=normalizeBackupState(backupState);
 return Object.freeze({state,canDownloadBackup:false,canRestore:false,restoreTestPassed:restoreTestPassed===true,serverAuthorizationVerified:serverAuthorizationVerified===true,requiresSeparateEnvironment:true});
}
