import test from 'node:test';
import assert from 'node:assert/strict';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {adminText,localizeAdminTree} from '../src/systemAdminLocale.js';
test('administration translation retains events, values and user-provided content',()=>{
 const click=()=>{};const form=React.createElement('section',null,
  React.createElement('button',{onClick:click,'aria-label':'حفظ اسم العرض'},'حفظ اسم العرض'),
  React.createElement('input',{value:'مدير النظام',placeholder:'البريد الجديد',readOnly:true}),
  React.createElement('span',{'data-no-translate':true},'مدير النظام'));
 const translated=localizeAdminTree(form,'en');
 assert.equal(translated.props.children[0].props.onClick,click);
 assert.equal(translated.props.children[1].props.value,'مدير النظام');
 const html=renderToStaticMarkup(translated);
 assert.match(html,/Save display name/);assert.match(html,/New email address/);
 assert.match(html,/data-no-translate="true">مدير النظام/);
 assert.equal(adminText('   كلمة المرور الجديدة  ','en'),'   New password  ');
 assert.equal(adminText('اسم شخص غير موجود بالقاموس','en'),'اسم شخص غير موجود بالقاموس');
});
test('custom account components receive the language and Arabic stays unchanged',()=>{
 function Account(){return null}
 const translated=localizeAdminTree(React.createElement(Account,{user:'synthetic'}),'en');
 assert.equal(translated.props.language,'en');assert.equal(translated.props.user,'synthetic');
 assert.equal(adminText('إجراءات سريعة','ar'),'إجراءات سريعة');
});
