BEGIN;
INSERT INTO pharmacy_supplier_stage.pharmacy_currency_settings(id,usd_to_syp) VALUES(1,140);
INSERT INTO pharmacy_supplier_stage.pharmacy_settings(id) VALUES(1);
INSERT INTO pharmacy_supplier_stage.suppliers(id,name,notes) VALUES('11111111-1111-4111-8111-111111111111','مورد تجريبي — بيانات وهمية','للاختبار فقط');
INSERT INTO pharmacy_supplier_stage.products(id,name,barcode,sale_currency,sale_price,purchase_price,reorder_level,parts_per_unit) VALUES
 ('22222222-2222-4222-8222-222222222221','منتج تجريبي 1','QA1001','USD',1.5,140,10,10),
 ('22222222-2222-4222-8222-222222222222','منتج تجريبي 2','QA1002','USD',1.5,140,10,10),
 ('22222222-2222-4222-8222-222222222223','منتج تجريبي 3','QA1003','SYP',210,140,10,10);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
DO $seed$
DECLARE i integer;v_currency text;v_product uuid;v_qty numeric;v_price numeric;v_result jsonb;
BEGIN FOR i IN 1..3 LOOP
 v_currency:=CASE WHEN i<3 THEN 'USD' ELSE 'SYP' END;
 v_product:=('22222222-2222-4222-8222-22222222222'||i)::uuid;
 v_qty:=CASE WHEN i=2 THEN 50 ELSE 100 END;v_price:=CASE WHEN i<3 THEN 1 ELSE 140 END;
 v_result:=public.supplier_preview_original_admin_bridge('15cdd7b6-cbfa-4607-9364-2787447f7680','rpc',CASE WHEN i<3 THEN 'admin_create_purchase_usd_v1' ELSE 'admin_create_purchase_syp_v1' END,
 jsonb_build_object('args',jsonb_build_object('p_supplier_id','11111111-1111-4111-8111-111111111111','p_new_supplier',null,'p_invoice_number','QA-'||v_currency||'-'||i,'p_invoice_date',current_date,'p_notes','فاتورة تجريبية وهمية','p_items',jsonb_build_array(jsonb_build_object('product_id',v_product,'quantity',v_qty,'purchase_price',v_price,'sale_price',CASE WHEN i<3 THEN 1.5 ELSE 210 END,'sale_currency',v_currency,'expiry_date',current_date+730)),'p_payment_amount',0,'p_payment_method','cash','p_payment_notes',null,'p_discount_type','none','p_discount_value',0)));
END LOOP; END $seed$;
COMMIT;
