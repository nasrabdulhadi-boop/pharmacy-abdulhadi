import {test} from 'node:test';
import assert from 'node:assert/strict';
import {catalogRows,readCatalogCsv,previewCatalogImport,catalogSample} from '../src/adminCatalogTools.js';
test('the downloadable template has no synthetic records',()=>assert.equal(catalogSample.trim(),'barcode,name,price,currency'));
test('CSV and worksheet imports preserve leading zeros and verify aliases',()=>{
 const rows=readCatalogCsv(catalogSample+'001234,"دواء, عبوة",2.25,USD');
 assert.equal(rows[0].barcode,'001234');
 const product={id:'p',barcode:'001234',active:true,sale_currency:'USD',sale_price:2};
 assert.equal(previewCatalogImport(rows,[product])[0].mode,'update');
 assert.ok(previewCatalogImport(rows,[{...product,alias:true}])[0].errors.length);
 assert.ok(previewCatalogImport(rows,[{...product,active:false}])[0].errors.length);
 const sheet=catalogRows([['barcode','name','price','currency'],[1234,'دواء',5,'SYP']]);
 assert.ok(previewCatalogImport(sheet,[])[0].errors.length);
});
