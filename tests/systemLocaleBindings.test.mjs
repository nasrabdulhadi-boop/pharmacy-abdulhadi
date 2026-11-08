import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import {parse} from '@babel/parser';
import traverseModule from '@babel/traverse';
import * as locale from '../src/systemLocale.js';
const traverse=traverseModule.default||traverseModule;
// Bundling permits free identifiers; a populated row can expose a missing import
// that a build and an empty-table render both miss.
test('every shared locale reference in active UI modules has a lexical binding',()=>{
 const helpers=new Set(Object.keys(locale)),missing=[];
 for(const file of readdirSync('src').filter(name=>name.endsWith('.jsx')&&!['main_new.jsx','main.pre_v513.jsx'].includes(name))){
  const tree=parse(readFileSync('src/'+file,'utf8'),{sourceType:'module',plugins:['jsx']});
  traverse(tree,{ReferencedIdentifier(path){if(helpers.has(path.node.name)&&!path.scope.hasBinding(path.node.name))missing.push(file+':'+path.node.loc.start.line+' '+path.node.name);}});
 }
 assert.deepEqual(missing,[],'Unbound locale helpers crash populated UI paths');
});
