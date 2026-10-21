#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
node - <<'NODE'
const fs=require('fs');
const ts=require('/opt/nvm/versions/node/v22.16.0/lib/node_modules/typescript/lib/typescript.js');
const file='src/main.jsx'; const src=fs.readFileSync(file,'utf8');
const out=ts.transpileModule(src,{fileName:file,reportDiagnostics:true,compilerOptions:{jsx:ts.JsxEmit.ReactJSX,target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}});
const errors=(out.diagnostics||[]).filter(d=>d.category===ts.DiagnosticCategory.Error);
if(errors.length){for(const d of errors) console.error(ts.flattenDiagnosticMessageText(d.messageText,'\n'));process.exit(1)}
console.log('PASS: JSX/JavaScript parser (0 errors)');
NODE
python3 - <<'PY'
from pathlib import Path
import re
src=Path('src/main.jsx').read_text()
sql=Path('CURRENCY_V6_4_15_SAFE_MIGRATION.sql').read_text()
sql_code=re.sub(r'/\*.*?\*/|--[^\n]*', '', sql, flags=re.S)
checks={
 'frontend reads currency settings RPC': "admin_get_currency_settings" in src,
 'frontend saves currency rate RPC': "admin_set_usd_to_syp_rate" in src,
 'migration defines matching get RPC': bool(re.search(r'FUNCTION public\.admin_get_currency_settings\s*\(\)',sql,re.I)),
 'migration defines matching setter RPC': bool(re.search(r'FUNCTION public\.admin_set_usd_to_syp_rate\s*\(p_rate numeric, p_note text DEFAULT NULL\)',sql,re.I)),
 'migration defines POS currency RPC': 'FUNCTION public.complete_sale_accounting_currency(' in sql,
 'invalid exchange rate rejected server-side': "p_rate <= 1" in sql,
 'invalid/missing exchange rate blocks USD sale': "v_item_fx <= 1" in sql,
 'no DROP TABLE': not re.search(r'\bDROP\s+TABLE\b',sql_code,re.I),
 'no TRUNCATE': not re.search(r'\bTRUNCATE\b',sql_code,re.I),
 'no DELETE statements': not re.search(r'\bDELETE\s+FROM\b',sql_code,re.I),
 'no service_role key in source': 'service_role' not in src.lower(),
}
for k,v in checks.items(): print(('PASS' if v else 'FAIL')+': '+k)
if not all(checks.values()): raise SystemExit(1)
print(f'PASS: {len(checks)} static checks')
PY
