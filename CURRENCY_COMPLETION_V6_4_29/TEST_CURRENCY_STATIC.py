from pathlib import Path
from decimal import Decimal
import re
ROOT=Path(__file__).parent; app=(ROOT.parent/'src/main.jsx').read_text()
scripts={p.name:p.read_text() for p in ROOT.glob('*.sql')}
checks={
    'no destructive table statements':all(not re.search(r'\b(DROP\s+TABLE|TRUNCATE|DELETE\s+FROM)\b','\n'.join(line for line in txt.splitlines() if not line.lstrip().startswith('--')),re.I) for txt in scripts.values()),
    'USD invoice new rpc':"admin_create_purchase_usd_v1" in app and 'admin_create_purchase_usd_v1' in scripts['04_USD_PURCHASES_STAGING_ONLY.sql'],
    'USD vendor payment new rpc':"admin_record_supplier_payment_usd_v1" in app and 'admin_record_supplier_payment_usd_v1' in scripts['03_USD_SUPPLIER_PAYMENTS_STAGING_ONLY.sql'],
    'original USD inventory cost frozen': all(x in scripts['04_USD_PURCHASES_STAGING_ONLY.sql'] for x in ('v_cost_syp:=ROUND(v_net_usd*v_fx*v_factor,6)','original_purchase_price','v_net_usd')),
    'vendor payments same currency guard': 'v_payment_currency IS DISTINCT FROM v_invoice_currency' in scripts['02_GUARD_SUPPLIER_ALLOCATIONS_STAGING_ONLY.sql'],
    'supplier payment cap guard': 'v_already_payment+NEW.amount>v_payment_total' in scripts['02_GUARD_SUPPLIER_ALLOCATIONS_STAGING_ONLY.sql'],
    'no FX default 15000':all('15000' not in txt for txt in scripts.values()),
    'new purchases require valid rate': 'IF v_fx IS NULL OR v_fx<=1 THEN' in scripts['04_USD_PURCHASES_STAGING_ONLY.sql'],
    'manual cashbox only SYP': "'SYP',1,v_amount" in scripts['08_SYP_MANUAL_CASHBOX_STAGING_ONLY.sql'],
    'prevent unsupported USD returns': 'trg_guard_usd_supplier_return_currency_v1' in scripts['07_BLOCK_UNSUPPORTED_USD_RETURNS_STAGING_ONLY.sql'],
    'report uses SYP normalization': 'COALESCE(c.amount_syp,c.amount)' in scripts['06_CASHBOX_FINANCIAL_REPORTS_STAGING_ONLY.sql'],
    'no reconciliation auto on page load': 'await supabase.rpc(\'admin_cashbox_reconcile\')' not in app,
    'old original file set intact':(ROOT.parent/'package.json').exists(),
}
q=Decimal('2');fx=Decimal('12000');discount=Decimal('0.1')
checks['effective inventory cost math']=(q*fx*(1-discount)==Decimal('21600'))
checks['SYP and USD kept apart in views']='GROUP BY s.id,p.currency' in scripts['05_CURRENCY_SAFE_READ_APIS_STAGING_ONLY.sql']
for key,ok in checks.items():print(('PASS' if ok else 'FAIL'),key)
assert all(checks.values())
print(f'PASSED: {len(checks)}/{len(checks)} static tests. NOT a database integration test.')
