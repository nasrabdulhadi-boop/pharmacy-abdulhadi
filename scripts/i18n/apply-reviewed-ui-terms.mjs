import fs from 'node:fs';
import {ENGLISH_INTERFACE} from '../../src/systemLanguageCatalogs.js';
const reviewed=JSON.parse(fs.readFileSync(new URL('./reviewed-ui-terms.json',import.meta.url)));
for(const [i,code]of ['ru','tr','ro','fr','de'].entries()){
 const path=new URL('../../src/locales/'+code+'.js',import.meta.url),data=(await import(path.href+'?review='+Date.now())).default;
 let count=0;for(const [source,english]of Object.entries(ENGLISH_INTERFACE))if(reviewed[english]){data[source]=reviewed[english][i];count++;}
 fs.writeFileSync(path,'// Static interface catalog: offline draft with reviewed core UI terms.\nexport default '+JSON.stringify(data,null,2)+';\n');console.log({code,reviewedTerms:count,messages:Object.keys(data).length});
}
