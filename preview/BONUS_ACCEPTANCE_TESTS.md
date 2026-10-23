# Bonus-only purchase preview: acceptance checklist

**Safety:** Execute only on an isolated Supabase development database. The Vercel preview currently uses the production database until its environment variables are changed. Never submit a purchase through that preview before isolation.

## Required database functions
Apply `preview/bonus_only_purchase_preview.sql` to the isolated database (not production). Confirm functions `admin_create_purchase`, `admin_create_purchase_syp_v1`, `admin_create_purchase_usd_v1`, and `admin_bonus_batch_ids` exist.

## Test cases
1. SYP invoice: paid quantity=0, bonus=10, valid expiry, sale price>0, purchase price=0. Save. Invoice subtotal/total=0, purchase_items.quantity=0, bonus_quantity=10. Exactly one bonus batch has quantity=10 and purchase_price=0; no paid batch. Stock movement type purchase_bonus. The purchase item batch_id points to the bonus batch.
2. USD invoice: same case; zero USD subtotal/total, bonus batch currency USD, zero cost, no supplier payment.
3. Mixed invoice: paid=5, bonus=2, unit purchase cost=100; subtotal=500 (not 700), bonus batch cost=0, paid batch quantity=5.
4. POS: find product by primary and additional barcodes, sell one bonus unit, verify batch stock decreases and realized cost is zero for that unit. Check FEFO selection if paid and bonus batches coexist.
5. Inventory: bonus batch shows 🎁 بونص, normal batch does not. Search both primary and alternate barcodes.
6. Regression: paid-only purchase, supplier debt, SYP/USD conversions, discounts, existing invoices, inventory search pagination, returns.
7. Reject: paid=0 bonus=0, negative quantities, expired batch, and sale_price<=0.

## Verification queries (read-only)
```sql
select pi.purchase_id, pi.product_id, pi.quantity, pi.bonus_quantity, pi.batch_id,
       b.quantity as linked_batch_quantity, b.purchase_price as linked_batch_cost, b.batch_number
from public.purchase_items pi
left join public.batches b on b.id=pi.batch_id
where pi.purchase_id = '<TEST_PURCHASE_UUID>';

select b.id,b.product_id,b.quantity,b.purchase_price,b.batch_number,sm.movement_type
from public.batches b
left join public.stock_movements sm on sm.batch_id=b.id
where b.purchase_id='<TEST_PURCHASE_UUID>';

select id,subtotal,total,currency from public.purchases where id='<TEST_PURCHASE_UUID>';
```

## Acceptance gate
Do not merge or point production at these functions until an isolated database has passed all scenarios and deployment has built successfully.
