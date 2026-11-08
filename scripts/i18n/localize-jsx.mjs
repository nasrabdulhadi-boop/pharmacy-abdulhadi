// One-time JSX display codemod; business expressions, RPC parameters and input values stay intact.
import fs from 'node:fs';import {parse} from '@babel/parser';import traverse from '@babel/traverse';
const arabic=/[\u0600-\u06ff]/,files=fs.readdirSync('src').filter(f=>f.endsWith('.jsx')&&!['main.pre_v513.jsx','main_new.jsx'].includes(f));
const catalog=new Set(),allLiterals=new Set();
function clean(text){const lines=text.replace(/\r/g,'').split('\n');let last=-1;for(let i=0;i<lines.length;i++)if(/\S/.test(lines[i]))last=i;return lines.map((line,i)=>{let s=line.replace(/\t/g,' ');if(i)s=s.replace(/^ +/,'');if(i!==lines.length-1)s=s.replace(/ +$/,'');return s+(s&&i!==last?' ':'');}).join('');}
for(const file of files){
 const source=fs.readFileSync('src/'+file,'utf8'),ast=parse(source,{sourceType:'module',plugins:['jsx']}),edits=[];let touched=false;
 const add=(start,end,text)=>{edits.push({start,end,text});touched=true;};
 const record=value=>{if(arabic.test(value.trim()))catalog.add(value.trim());};
 function display(node){
  if(!node)return;
  if(node.type==='StringLiteral'&&arabic.test(node.value)){record(node.value);add(node.start,node.end,'uiText('+source.slice(node.start,node.end)+')');}
  else if(node.type==='TemplateLiteral'&&node.quasis.some(q=>arabic.test(q.value.cooked||q.value.raw))){const parts=node.quasis.map(q=>q.value.cooked??q.value.raw);record(parts.map((s,i)=>s+(i<node.expressions.length?'{'+i+'}':'')).join(''));add(node.start,node.end,'uiTemplate('+JSON.stringify(parts)+',['+node.expressions.map(n=>source.slice(n.start,n.end)).join(',')+'])');}
  else if(node.type==='ConditionalExpression'){display(node.consequent);display(node.alternate);}
  else if(node.type==='BinaryExpression'&&node.operator==='+'){display(node.left);display(node.right);}
  else if(node.type==='LogicalExpression'){if(node.left.type==='MemberExpression'||(node.left.type==='Identifier'&&/label|title|message|error|notice|caption|empty|sub/i.test(node.left.name)))display(node.left);display(node.right);}
  else if(node.type==='Identifier'&&!/^(name|email|phone|address|notes|description|barcode|query|search|q|value|children|p|x|r|user)$/i.test(node.name)){add(node.start,node.end,'uiText('+source.slice(node.start,node.end)+')');}
  else if(node.type==='MemberExpression'){
   const property=node.computed?null:node.property.name,object=node.object.type==='Identifier'?node.object.name:'';
   if((property&&['label','status','unit','payment_method','currency','movement_type','role','system_role','component'].includes(property))||/label|caption|heading|names|typeLabel/i.test(object))add(node.start,node.end,'uiText('+source.slice(node.start,node.end)+')');
  }
  else if(node.type==='CallExpression'&&node.callee.type==='Identifier'&&!/^(uiText|uiTemplate|localizeAdminTree|createPortal|money|format|localDate|localDateTime)|name|product|customer|supplier/i.test(node.callee.name))add(node.start,node.end,'uiText('+source.slice(node.start,node.end)+')');
 }
 traverse(ast,{
  StringLiteral(p){if(arabic.test(p.node.value))allLiterals.add(p.node.value.trim());},
  JSXText(p){const value=clean(p.node.value);if(arabic.test(value)){record(value);add(p.node.start,p.node.end,'{uiText('+JSON.stringify(value)+')}');}},
  JSXAttribute(p){const name=p.node.name.name;if(['title','placeholder','aria-label','alt'].includes(name)&&p.node.value?.type==='StringLiteral'&&arabic.test(p.node.value.value)){record(p.node.value.value);add(p.node.value.start,p.node.value.end,'{uiText('+JSON.stringify(p.node.value.value)+')}');}},
  JSXExpressionContainer(p){if(p.parent.type==='JSXAttribute'){if(['title','placeholder','aria-label','alt'].includes(p.parent.name.name))display(p.node.expression);return;}display(p.node.expression);}
 });
 if(process.argv.includes('--write')&&touched){let next=source;const unique=[...new Map(edits.map(e=>[e.start+':'+e.end,e])).values()];const sorted=unique.filter(e=>!unique.some(other=>other!==e&&other.start>=e.start&&other.end<=e.end)).sort((a,b)=>b.start-a.start);for(let i=1;i<sorted.length;i++)if(sorted[i].end>sorted[i-1].start)throw Error('overlapping display edits: '+file);for(const e of sorted)next=next.slice(0,e.start)+e.text+next.slice(e.end);if(!source.includes("uiText,uiTemplate"))next="import {uiText,uiTemplate} from './systemLocale.js';\n"+next;fs.writeFileSync('src/'+file,next);}
}
fs.writeFileSync('/tmp/pharmacy-ui-copy.json',JSON.stringify([...catalog].sort(),null,2));fs.writeFileSync('/tmp/pharmacy-ui-all-strings.json',JSON.stringify([...allLiterals].filter(Boolean).sort(),null,2));console.log(JSON.stringify({jsxCopy:catalog.size,allStrings:allLiterals.size}));
