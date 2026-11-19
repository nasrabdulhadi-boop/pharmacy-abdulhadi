// Offline verification only. This module never exports, reads or restores a database.
const REQUIRED_SECTIONS=Object.freeze(['schema','policies','functions','table_counts','storage_inventory']);
export function validateBackupManifest(manifest){
 const errors=[];
 if(!manifest||typeof manifest!=='object'||Array.isArray(manifest))return {ok:false,errors:['Invalid manifest']};
 if(manifest.format!=='pharmacy-admin-backup-v1')errors.push('Unsupported backup format');
 if(manifest.environment!=='isolated-staging')errors.push('Only isolated staging manifests are allowed');
 if(typeof manifest.created_at!=='string'||!Number.isFinite(Date.parse(manifest.created_at)))errors.push('Missing valid creation timestamp');
 if(!manifest.sections||typeof manifest.sections!=='object'||Array.isArray(manifest.sections))errors.push('Missing sections');
 else for(const name of REQUIRED_SECTIONS){const section=manifest.sections[name];if(!section||section.verified!==true||typeof section.sha256!=='string'||!/^[a-f0-9]{64}$/i.test(section.sha256))errors.push('Unverified section: '+name)}
 if(manifest.includes_patient_data!==false)errors.push('Sensitive patient data must be excluded from staging manifest');
 return {ok:errors.length===0,errors};
}
export function makeBackupReadinessReport(manifest){const result=validateBackupManifest(manifest);return {manifestValid:result.ok,restoreTested:false,productionReady:false,errors:result.errors};}
