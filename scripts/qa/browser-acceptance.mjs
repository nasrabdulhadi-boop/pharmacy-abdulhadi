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
  await context.route('**/*',route=>{
   const host=new URL(route.request().url()).hostname;
   if(host==='fonts.googleapis.com')return route.fulfill({status:200,contentType:'text/css',body:''});
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
  await page.screenshot({path:'/tmp/pharmacy-qa-'+label+'.png',fullPage:true});
  await context.close();
 }
}finally{await browser.close();writeFileSync('/tmp/pharmacy-qa-browser-results.json',JSON.stringify(results,null,2));console.log(results)}
