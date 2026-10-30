import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {createRequire} from 'node:module';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {buildSync} from 'esbuild';
const source=fs.readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
const content=source.slice(0,source.lastIndexOf("createRoot(document.getElementById('root'))"))+'\nexport {Admin,Login};';
const result=buildSync({stdin:{contents:content,resolveDir:path.resolve('src'),sourcefile:'main.jsx',loader:'jsx'},bundle:true,write:false,platform:'node',format:'cjs',external:['react','react-dom','react-dom/client'],loader:{'.css':'empty'},define:{'import.meta.env':JSON.stringify({VITE_SUPPLIER_CURRENCY_PREVIEW:'true',VITE_SUPABASE_URL:'https://vpjxdsprfcpqclnhbeoh.supabase.co',VITE_SUPABASE_PUBLISHABLE_KEY:'test-public-key',VITE_ORIGINAL_AUTH_URL:'https://eewjjzgwoaxhojnjvzgq.supabase.co',VITE_ORIGINAL_AUTH_PUBLISHABLE_KEY:'test-original-public-key'})}});
const module={exports:{}};vm.runInNewContext(result.outputFiles[0].text,{module,exports:module.exports,require:createRequire(import.meta.url),console,URL,Headers,Request,Response,AbortController,WebSocket,fetch,setTimeout,clearTimeout,setInterval,clearInterval,process,Buffer});
test('full original admin shell and all navigation sections render, rather than a separate workbench',()=>{
 const html=renderToStaticMarkup(React.createElement(module.exports.Admin,{onLogout:()=>{}}));
 assert.match(html,/adminShell/);
 for(const label of ['لوحة التحكم','نقطة البيع','منتجات الصيدلية','منتجات الموقع','المخزون','المخزون الذكي','المشتريات','الموردون','ديون الموردين','الطلبات','الوصفات','طلبات الأدوية','العملاء','المتدينين','العروض','الصندوق','المرتجعات','التقارير','مركز الأرباح الذكي','الأمان والتدقيق'])assert.ok(html.includes(label),label);
 assert.match(source,/if\(authorized\)return <Admin/);assert.match(source,/<AppErrorBoundary><Root\/>/);assert.ok(!source.includes('function SupplierCurrencyPreview'));
});
test('original login form remains the entry point and explains using original administrator credentials',()=>{
 const html=renderToStaticMarkup(React.createElement(module.exports.Login));assert.match(html,/type="email"/);assert.match(html,/type="password"/);assert.ok(html.includes('بحساب المدير الأصلي نفسه'));
});
