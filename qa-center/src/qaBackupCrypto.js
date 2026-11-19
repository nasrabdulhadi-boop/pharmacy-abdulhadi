const encoder=new TextEncoder(),decoder=new TextDecoder();
const MAX_BYTES=50*1024*1024,ITERATIONS=310000;
const hex=bytes=>Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,'0')).join('');
function b64(bytes){let text='';for(const byte of new Uint8Array(bytes))text+=String.fromCharCode(byte);return btoa(text);}
function unb64(text){if(typeof text!=='string'||text.length>MAX_BYTES*1.4||!/^[A-Za-z0-9+/]*={0,2}$/.test(text))throw new Error('invalid_archive');return Uint8Array.from(atob(text),c=>c.charCodeAt(0));}
async function key(passphrase,salt){
 if(typeof passphrase!=='string'||passphrase.length<16||encoder.encode(passphrase).length>1024)throw new Error('invalid_passphrase');
 const material=await crypto.subtle.importKey('raw',encoder.encode(passphrase),'PBKDF2',false,['deriveKey']);
 return crypto.subtle.deriveKey({name:'PBKDF2',salt,iterations:ITERATIONS,hash:'SHA-256'},material,{name:'AES-GCM',length:256},false,['encrypt','decrypt']);
}
export function validateQaBackup(data){
 if(data?.format!=='pharmacy-qa-application-backup-v1'||data.project_ref!=='vpjxdsprfcpqclnhbeoh'||data.auth_credentials_included!==false||!Array.isArray(data.tables)||!Array.isArray(data.functions)||!Array.isArray(data.storage_files)||!Array.isArray(data.storage_inventory))throw new Error('invalid_archive');
 const names=new Set();
 for(const table of data.tables){
  if(!['public','pharmacy_qa_private','pharmacy_supplier_stage','supplier_currency_qa'].includes(table.schema)||typeof table.name!=='string'||!Array.isArray(table.rows)||table.rows.length!==table.row_count||names.has(table.schema+'.'+table.name))throw new Error('invalid_archive');
  names.add(table.schema+'.'+table.name);
 }
 const files=new Set(data.storage_files.map(file=>file.bucket_id+'/'+file.name));
 if(files.size!==data.storage_files.length||files.size!==data.storage_inventory.length||data.storage_inventory.some(file=>file.bucket_id!=='supplier-preview-prescriptions'||!files.has(file.bucket_id+'/'+file.name)))throw new Error('invalid_archive');
 return {tables:data.tables.length,rows:data.tables.reduce((n,t)=>n+t.row_count,0),files:data.storage_files.length,restoreVerified:false};
}
export async function encryptQaBackup(data,passphrase,confirmation){
 if(passphrase!==confirmation)throw new Error('passphrase_mismatch');
 validateQaBackup(data);const bytes=encoder.encode(JSON.stringify(data));
 if(bytes.length>MAX_BYTES)throw new Error('archive_too_large');
 const salt=crypto.getRandomValues(new Uint8Array(16)),iv=crypto.getRandomValues(new Uint8Array(12));
 const cipher=await crypto.subtle.encrypt({name:'AES-GCM',iv},await key(passphrase,salt),bytes);
 return {format:'pharmacy-qa-encrypted-backup-v1',kdf:'PBKDF2-SHA256',iterations:ITERATIONS,cipher:'AES-256-GCM',salt:b64(salt),iv:b64(iv),ciphertext:b64(cipher),plaintext_sha256:hex(await crypto.subtle.digest('SHA-256',bytes))};
}
export async function decryptQaBackup(envelope,passphrase){
 if(envelope?.format!=='pharmacy-qa-encrypted-backup-v1'||envelope.kdf!=='PBKDF2-SHA256'||envelope.iterations!==ITERATIONS||envelope.cipher!=='AES-256-GCM')throw new Error('invalid_archive');
 const salt=unb64(envelope.salt),iv=unb64(envelope.iv),cipher=unb64(envelope.ciphertext);
 if(salt.length!==16||iv.length!==12||cipher.length>MAX_BYTES+16)throw new Error('invalid_archive');
 let bytes;try{bytes=await crypto.subtle.decrypt({name:'AES-GCM',iv},await key(passphrase,salt),cipher);}catch{throw new Error('backup_decryption_failed');}
 if(hex(await crypto.subtle.digest('SHA-256',bytes))!==envelope.plaintext_sha256)throw new Error('backup_hash_mismatch');
 const data=JSON.parse(decoder.decode(bytes));validateQaBackup(data);
 for(const file of data.storage_files){
  const content=unb64(file.bytes_base64);
  if(file.bucket_id!=='supplier-preview-prescriptions'||content.length!==file.size||hex(await crypto.subtle.digest('SHA-256',content))!==file.sha256)throw new Error('backup_file_hash_mismatch');
 }
 return {data,summary:validateQaBackup(data)};
}
