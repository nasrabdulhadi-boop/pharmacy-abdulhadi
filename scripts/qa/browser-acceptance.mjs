import {createRequire} from 'node:module';
const {chromium}=createRequire(import.meta.url)('playwright');
import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const users=JSON.parse(readFileSync('/tmp/pharmacy-qa-accounts.json')).users;
const proxy=process.env.HTTPS_PROXY||process.env.HTTP_PROXY;
const browser=await chromium.launch({headless:true,executablePath:process.env.QA_CHROMIUM_PATH||undefined,...(proxy?{proxy:{server:proxy,bypass:'127.0.0.1,localhost'}}:{}),args:['--no-sandbox','--disable-dev-shm-usage']});
const results=[];
try{
 for(const label of ['owner','manager','employee','support']){
  const user=users.find(u=>u.label===label);const context=await browser.newContext({ignoreHTTPSErrors:!!proxy,viewport:{width:label==='employee'?390:1440,height:1000}});const page=await context.newPage();const errors=[];
  const unexpected=[];
  await context.route('**/*',async route=>{
   const host=new URL(route.request().url()).hostname;
   if(host==='fonts.googleapis.com')return route.fulfill({status:200,contentType:'text/css',body:''});
   // Optional transport bridge for restricted test runners. This still calls real
   // QA Auth/RPC endpoints, but does not verify browser TLS/CORS transport.
   if(host==='vpjxdsprfcpqclnhbeoh.supabase.co'&&process.env.QA_NODE_NETWORK==='true'){
    try{const request=route.request();const headers={...request.headers()};for(const k of ['host','content-length','connection','accept-encoding'])delete headers[k];
     const r=await fetch(request.url(),{method:request.method(),headers,...(['GET','HEAD'].includes(request.method())?{}:{body:request.postData()}),signal:AbortSignal.timeout(30000)});
     const responseHeaders=Object.fromEntries(r.headers);for(const k of ['content-length','content-encoding','transfer-encoding'])delete responseHeaders[k];
     return route.fulfill({status:r.status,headers:responseHeaders,body:Buffer.from(await r.arrayBuffer())});
    }catch{return route.abort();}
   }
   if(['127.0.0.1','localhost','vpjxdsprfcpqclnhbeoh.supabase.co'].includes(host))return route.continue();
   unexpected.push(host);return route.abort();
  });
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto((process.env.QA_PREVIEW_URL||'http://127.0.0.1:4173/')+'#admin');
  await page.getByPlaceholder('البريد الإلكتروني').fill(user.email);await page.getByPlaceholder('كلمة المرور',{exact:true}).fill(user.password);
  await page.getByRole('button',{name:'دخول',exact:true}).click();
  try{await page.getByText('QA • واجهة النظام الأصلية • البيانات اصطناعية',{exact:true}).waitFor({timeout:60000});}
  catch(error){writeFileSync('/tmp/pharmacy-qa-browser-failure.txt',JSON.stringify({label,body:await page.locator('body').innerText(),unexpected,errors},null,2));throw error;}
  assert.equal(await page.locator('.adminShell').count(),1,'All roles must use the original Admin layout');
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'Page must not overflow viewport');
  assert.deepEqual(errors,[]);assert.deepEqual(unexpected,[],'No production or external host may be contacted');results.push({name:label+' actual browser login and responsive shared workspace',passed:true});
  if(label==='support'){assert.equal(await page.getByText('سعر شراء العبوة').count(),0);assert.equal(await page.getByRole('heading',{name:'المخزون التجريبي القابل للبيع'}).count(),0)}
  if(['owner','manager'].includes(label)){
   await page.getByRole('button',{name:'مركز إدارة النظام',exact:true}).click();
   await page.getByRole('button',{name:'الأدوار والصلاحيات',exact:true}).click();
   const accounts=page.getByRole('region',{name:'إدارة حسابات QA'});
   await accounts.getByText(user.email,{exact:true}).waitFor({timeout:30000});
   const self=accounts.getByRole('row').filter({hasText:user.email});
   assert.equal(await self.getByRole('button').isDisabled(),true,'Own account must be protected');
   results.push({name:label+' account management loads and protects self',passed:true});
   if(label==='owner'){
    const employee=users.find(u=>u.label==='employee');const target=accounts.getByRole('row').filter({hasText:employee.email});
    await target.getByRole('combobox').selectOption('technical_support');await target.getByRole('button').click();
    await target.locator('td').nth(1).getByText('دعم فني',{exact:true}).waitFor({timeout:30000});
    await target.getByRole('combobox').selectOption('employee');await target.getByRole('button').click();
    await target.locator('td').nth(1).getByText('موظف',{exact:true}).waitFor({timeout:30000});
    results.push({name:'owner changes disposable employee role and restores it through real QA RPC',passed:true});
   }
  }
  await page.screenshot({path:'/tmp/pharmacy-qa-'+label+'.png',fullPage:true});
  await context.close();
 }
}finally{await browser.close();writeFileSync('/tmp/pharmacy-qa-browser-results.json',JSON.stringify(results,null,2));console.log(results)}
