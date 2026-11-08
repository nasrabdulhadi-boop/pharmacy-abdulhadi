// Unit harness for the real component's submit handler and button state.
// React hooks are seeded locally; no browser, account or database mutation.
import test from'node:test';import assert from'node:assert/strict';import{build}from'esbuild';import{createRequire}from'node:module';
const require=createRequire(import.meta.url),React=require('react');
const bundle=await build({entryPoints:['src/QaStaffAccountEditor.jsx'],bundle:true,write:false,platform:'node',format:'cjs',external:['react']});
function render({password='',confirmation=''}={}){const state=[{full_name:'موظف اصطناعي'},'staff@example.invalid','employee',password,confirmation,false,'',{}],setters=[],focus=[],calls=[];let cursor=0;
 const fake={...React,useEffect:()=>{},useId:()=>':test:',useRef:v=>({current:v}),useState:initial=>{const n=cursor++;return[n<state.length?state[n]:initial,v=>{setters.push([n,v]);}];}};
 const module={exports:{}};new Function('require','module','exports',bundle.outputFiles[0].text)(name=>name==='react'?fake:require(name),module,module.exports);
 const actorId='00000000-0000-4000-8000-000000000001';const client={auth:{getUser:async()=>({data:{user:{id:actorId}}})},functions:{invoke:async(name,p)=>{calls.push([name,p]);return{data:{completed:true,user_id:actorId,action:'create',email_sent:false}};}}};
 const tree=module.exports.default({client,projectUrl:'https://vpjxdsprfcpqclnhbeoh.supabase.co',actorId,actorRole:'system_admin'});
 const all=[];function visit(n){if(Array.isArray(n))n.forEach(visit);else if(n&&typeof n==='object'&&n.props){all.push(n);visit(n.props.children);}}visit(tree);
 return{all,setters,calls,focus,event:{preventDefault(){},currentTarget:{elements:{namedItem:n=>({focus:()=>focus.push(n)})}}}};
}
test('invalid creation remains clickable and reports fields instead of silently disabling the button',()=>{const h=render();const submit=h.all.find(n=>n.type==='button'&&n.props.type==='submit');assert.equal(submit.props.disabled,false);h.all.find(n=>n.type==='form').props.onSubmit(h.event);assert.ok(h.setters.some(([n,v])=>n===7&&v.password&&v.confirmation));assert.deepEqual(h.focus,['password']);assert.deepEqual(h.calls,[]);});
test('a valid component submission reaches the staff API and clears passwords after completion',async()=>{const h=render({password:'Synthetic-Only123!',confirmation:'Synthetic-Only123!'});h.all.find(n=>n.type==='form').props.onSubmit(h.event);await new Promise(resolve=>setImmediate(resolve));assert.equal(h.calls.length,1);assert.equal(h.calls[0][0],'qa-admin-staff-account');assert.ok(h.setters.some(([n,v])=>n===6&&typeof v==='string'&&v.includes('تم إنشاء الحساب')));assert.ok(h.setters.some(([n,v])=>n===3&&v===''));});
