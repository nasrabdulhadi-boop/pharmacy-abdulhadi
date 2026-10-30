import {hasCapability} from './systemAccessPolicy.js';
export const MASKED_VALUE='••••';
export const ROLE_NAMES={system_owner:'مدير النظام',system_admin:'مدير النظام',employee:'موظف',technical_support:'الدعم الفني'};
const employeeSections=new Set(['dashboard','pos','pharmacyProducts','inventory','smart','purchases','suppliers','orders','returns']);
export function workspaceSectionAllowed(role,section){
 if(['system_owner','system_admin'].includes(role))return true;
 if(role==='employee')return employeeSections.has(section);
 return role==='technical_support'&&['dashboard','systemCenter'].includes(section);
}
export function workspaceCanReadMoney(role){return hasCapability(role,'finance.read')}
export function workspaceCanReadStock(role){return ['system_owner','system_admin','employee'].includes(role)}
export function workspaceCanWrite(role,operation){
 if(['system_owner','system_admin'].includes(role))return true;
 return role==='employee'&&['sale','purchase_draft','inventory_count','return_request','order_process'].includes(operation);
}
