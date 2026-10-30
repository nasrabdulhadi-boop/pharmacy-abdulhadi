import {createRequire} from 'node:module';
const {chromium}=createRequire(import.meta.url)('playwright');
import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const users=JSON.parse(readFileSync('/tmp/pharmacy-qa-accounts.json')).users;
const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
const results=[];
try{
 for(const label of ['manager','employee','support']){
  const user=users.find(u=>u.label===label);const context=await browser.newContext({viewport:{width:label==='employee'?390:1440,height:1000}});const page=await context.newPage();const errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto((process.env.QA_PREVIEW_URL||'http://127.0.0.1:4173/')+'#admin');
  await page.getByPlaceholder('البريد الإلكتروني').fill(user.email);await page.getByPlaceholder('كلمة المرور',{exact:true}).fill(user.password);
  await page.getByRole('button',{name:'دخول',exact:true}).click();
  const heading=label==='manager'?'لوحة مدير QA المستقل':label==='employee'?'بوابة موظف QA':'بوابة الدعم الفني التجريبية';
  await page.getByRole('heading',{name:heading,exact:true}).waitFor({timeout:60000});
  if(label!=='support')await page.getByText('QA-USD',{exact:true}).first().waitFor({timeout:60000});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'Page must not overflow viewport');
  assert.deepEqual(errors,[]);results.push({name:label+' actual browser login and responsive portal',passed:true});
  if(label==='support'){assert.equal(await page.getByText('سعر شراء العبوة').count(),0);assert.equal(await page.getByRole('heading',{name:'المخزون التجريبي القابل للبيع'}).count(),0)}
  await page.screenshot({path:'/tmp/pharmacy-qa-'+label+'.png',fullPage:true});
  await context.close();
 }
}finally{await browser.close();writeFileSync('/tmp/pharmacy-qa-browser-results.json',JSON.stringify(results,null,2));console.log(results)}
