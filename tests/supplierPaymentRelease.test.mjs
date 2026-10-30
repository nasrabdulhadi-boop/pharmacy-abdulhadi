import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import vm from 'node:vm';
import {createRequire} from 'node:module';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {buildSync} from 'esbuild';
const source=fs.readFileSync('src/main.jsx','utf8');
test('production login, authentication, products and inventory are unchanged',()=>{
 const spans=JSON.parse(fs.readFileSync('tests/original-unchanged.json','utf8'));
 for(const [name,{start,end,sha256}] of Object.entries(spans)){const section=source.slice(source.indexOf(start),source.indexOf(end,source.indexOf(start)));assert.equal(crypto.createHash('sha256').update(section).digest('hex'),sha256,name);}
 assert.ok(!source.includes('supplierFullPreviewClient'));assert.ok(!source.includes('vpjxdsprfcpqclnhbeoh'));assert.ok(!source.includes('VITE_ORIGINAL_AUTH'));
});
test('original admin navigation and supplier-ledger root still render',()=>{
 const body=source.slice(0,source.lastIndexOf("createRoot(document.getElementById('root'))"))+'\nexport {Admin,SupplierDebts};';
 const compiled=buildSync({stdin:{contents:body,resolveDir:path.resolve('src'),sourcefile:'main.jsx',loader:'jsx'},bundle:true,write:false,platform:'node',format:'cjs',external:['react','react-dom','react-dom/client'],loader:{'.css':'empty'},define:{'import.meta.env':'{}'}});
 const module={exports:{}};vm.runInNewContext(compiled.outputFiles[0].text,{module,exports:module.exports,require:createRequire(import.meta.url),console,crypto,URL,Headers,Request,Response,AbortController,WebSocket,fetch,setTimeout,clearTimeout,setInterval,clearInterval,process,Buffer});
 const html=renderToStaticMarkup(React.createElement(module.exports.Admin,{onLogout:()=>{}}));
 for(const label of ['نقطة البيع','المشتريات','الموردون','ديون الموردين','الصندوق','التقارير','الأمان والتدقيق'])assert.ok(html.includes(label),label);
 assert.ok(renderToStaticMarkup(React.createElement(module.exports.SupplierDebts)).includes('ديون الموردين'));
 assert.match(source,/admin_record_supplier_payment_currency_v2/);assert.match(source,/إجمالي الدفعة الأصلية/);
});
