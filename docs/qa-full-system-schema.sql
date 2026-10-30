CREATE SCHEMA pharmacy_supplier_stage;
REVOKE ALL ON SCHEMA pharmacy_supplier_stage FROM PUBLIC,anon,authenticated;
SET LOCAL search_path=pharmacy_supplier_stage,pg_catalog,extensions;
SET LOCAL check_function_bodies=off;
CREATE SEQUENCE pharmacy_supplier_stage.order_public_seq;
CREATE SEQUENCE pharmacy_supplier_stage.pharmacy_settings_id_seq;
CREATE SEQUENCE pharmacy_supplier_stage.product_barcodes_id_seq;
CREATE TABLE pharmacy_supplier_stage.debtors (id uuid DEFAULT gen_random_uuid() NOT NULL, name text NOT NULL, phone text, address text, notes text, active boolean DEFAULT true NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE pharmacy_supplier_stage.debtors ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.offers (id uuid DEFAULT gen_random_uuid() NOT NULL, title text NOT NULL, description text, active boolean DEFAULT true NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE pharmacy_supplier_stage.offers ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.medicine_requests (id uuid DEFAULT gen_random_uuid() NOT NULL, name text NOT NULL, strength text, phone text NOT NULL, status text DEFAULT 'new'::text NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE pharmacy_supplier_stage.medicine_requests ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.audit_logs (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid, action text NOT NULL, entity_type text, entity_id uuid, details jsonb, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE pharmacy_supplier_stage.audit_logs ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.inventory_count_items (id uuid DEFAULT gen_random_uuid() NOT NULL, count_id uuid NOT NULL, batch_id uuid, expected_quantity numeric DEFAULT 0 NOT NULL, actual_quantity numeric, difference numeric GENERATED ALWAYS AS ((COALESCE(actual_quantity, (0)::numeric) - expected_quantity)) STORED, notes text, product_id uuid);
ALTER TABLE pharmacy_supplier_stage.inventory_count_items ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.inventory_counts (id uuid DEFAULT gen_random_uuid() NOT NULL, status text DEFAULT 'open'::text NOT NULL, started_at timestamp with time zone DEFAULT now() NOT NULL, completed_at timestamp with time zone, created_by uuid, notes text);
ALTER TABLE pharmacy_supplier_stage.inventory_counts ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.products (id uuid DEFAULT gen_random_uuid() NOT NULL, barcode text, name text NOT NULL, active_ingredient text, dosage_form text, strength text, manufacturer text, category text, unit text DEFAULT 'piece'::text NOT NULL, reorder_level numeric(12,2) DEFAULT 0 NOT NULL, customer_visible boolean DEFAULT true NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL, sale_price numeric DEFAULT 0 NOT NULL, parts_per_unit numeric DEFAULT 1 NOT NULL, purchase_price numeric DEFAULT 0 NOT NULL, active boolean DEFAULT true NOT NULL, sale_currency text DEFAULT 'SYP'::text NOT NULL);
ALTER TABLE pharmacy_supplier_stage.products ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.pos_shortcut_preferences (user_id uuid NOT NULL, items jsonb DEFAULT '[]'::jsonb NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE pharmacy_supplier_stage.pos_shortcut_preferences ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.returns (id uuid DEFAULT gen_random_uuid() NOT NULL, return_type text NOT NULL, sale_id uuid, sale_item_id uuid, purchase_id uuid, product_id uuid NOT NULL, batch_id uuid, quantity numeric NOT NULL, amount numeric DEFAULT 0 NOT NULL, reason text, created_by uuid, created_at timestamp with time zone DEFAULT now() NOT NULL, currency text DEFAULT 'SYP'::text NOT NULL, fx_rate numeric DEFAULT 1 NOT NULL, amount_syp numeric);
ALTER TABLE pharmacy_supplier_stage.returns ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.customers (id uuid DEFAULT gen_random_uuid() NOT NULL, name text NOT NULL, phone text, address text, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE pharmacy_supplier_stage.customers ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.order_items (id uuid DEFAULT gen_random_uuid() NOT NULL, order_id uuid NOT NULL, product_id uuid NOT NULL, quantity numeric(12,2) NOT NULL, unit_price numeric(12,2) DEFAULT 0 NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE pharmacy_supplier_stage.order_items ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.stock_movements (id uuid DEFAULT gen_random_uuid() NOT NULL, product_id uuid NOT NULL, batch_id uuid, movement_type text NOT NULL, quantity numeric(12,2) NOT NULL, reference_id uuid, note text, created_by uuid, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE pharmacy_supplier_stage.stock_movements ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.prescriptions (id uuid DEFAULT gen_random_uuid() NOT NULL, customer_id uuid, order_id uuid, file_path text NOT NULL, file_name text, mime_type text, file_size bigint, created_at timestamp with time zone DEFAULT now() NOT NULL, created_by uuid, status text DEFAULT 'new'::text NOT NULL, customer_name text, customer_phone text, notes text);
ALTER TABLE pharmacy_supplier_stage.prescriptions ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.orders (id uuid DEFAULT gen_random_uuid() NOT NULL, customer_id uuid, status text DEFAULT 'new'::text NOT NULL, notes text, total numeric(12,2) DEFAULT 0 NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL, public_code text DEFAULT ('ORD-'::text || nextval('order_public_seq'::regclass)));
ALTER TABLE pharmacy_supplier_stage.orders ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.suppliers (id uuid DEFAULT gen_random_uuid() NOT NULL, name text NOT NULL, phone text, address text, created_at timestamp with time zone DEFAULT now() NOT NULL, notes text);
ALTER TABLE pharmacy_supplier_stage.suppliers ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.pharmacy_settings (id bigint NOT NULL, pharmacy_name text DEFAULT 'صيدلية عبدالهادي'::text NOT NULL, pharmacist_name text DEFAULT 'نصر عبدالهادي'::text NOT NULL, phone text DEFAULT '0995008129'::text NOT NULL, whatsapp text DEFAULT '0995008129'::text NOT NULL, address text DEFAULT 'الحاضر_شارع سيرياتيل جانب معرض الحاضر كارز'::text NOT NULL, maps_url text, opening_time time without time zone DEFAULT '08:00:00'::time without time zone NOT NULL, closing_time time without time zone DEFAULT '00:00:00'::time without time zone NOT NULL, show_prices_to_customers boolean DEFAULT false NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE pharmacy_supplier_stage.pharmacy_settings ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.sale_items (id uuid DEFAULT gen_random_uuid() NOT NULL, sale_id uuid NOT NULL, product_id uuid NOT NULL, batch_id uuid NOT NULL, quantity numeric(12,2) NOT NULL, unit_price numeric(12,2) NOT NULL, unit_cost numeric(12,2) DEFAULT 0 NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, base_unit_price numeric, price_currency text DEFAULT 'SYP'::text NOT NULL, price_fx_rate numeric DEFAULT 1 NOT NULL);
ALTER TABLE pharmacy_supplier_stage.sale_items ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.pharmacy_currency_history (id uuid DEFAULT gen_random_uuid() NOT NULL, usd_to_syp numeric NOT NULL, changed_at timestamp with time zone DEFAULT now() NOT NULL, changed_by uuid, note text);
ALTER TABLE pharmacy_supplier_stage.pharmacy_currency_history ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.pharmacy_currency_settings (id integer NOT NULL, usd_to_syp numeric NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL, updated_by uuid);
ALTER TABLE pharmacy_supplier_stage.pharmacy_currency_settings ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.sales (id uuid DEFAULT gen_random_uuid() NOT NULL, customer_id uuid, subtotal numeric(12,2) DEFAULT 0 NOT NULL, discount numeric(12,2) DEFAULT 0 NOT NULL, total numeric(12,2) DEFAULT 0 NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, created_by uuid, payment_method text DEFAULT 'cash'::text NOT NULL, paid_amount numeric DEFAULT 0 NOT NULL, due_amount numeric DEFAULT 0 NOT NULL, payment_notes text, debtor_id uuid, currency text DEFAULT 'SYP'::text NOT NULL, fx_rate numeric DEFAULT 1 NOT NULL, total_syp numeric);
ALTER TABLE pharmacy_supplier_stage.sales ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.cashbox_entries (id uuid DEFAULT gen_random_uuid() NOT NULL, entry_type text NOT NULL, amount numeric NOT NULL, description text, sale_id uuid, debtor_transaction_id uuid, purchase_id uuid, created_by uuid, created_at timestamp with time zone DEFAULT now() NOT NULL, supplier_payment_id uuid, currency text DEFAULT 'SYP'::text NOT NULL, fx_rate numeric DEFAULT 1 NOT NULL, amount_syp numeric);
ALTER TABLE pharmacy_supplier_stage.cashbox_entries ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.supplier_payments (id uuid DEFAULT gen_random_uuid() NOT NULL, supplier_id uuid NOT NULL, amount numeric NOT NULL, payment_method text DEFAULT 'cash'::text NOT NULL, notes text, cashbox_entry_id uuid, created_by uuid, created_at timestamp with time zone DEFAULT now() NOT NULL, currency text DEFAULT 'SYP'::text NOT NULL, fx_rate numeric DEFAULT 1 NOT NULL, amount_syp numeric);
ALTER TABLE pharmacy_supplier_stage.supplier_payments ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.supplier_payment_allocations (id uuid DEFAULT gen_random_uuid() NOT NULL, payment_id uuid NOT NULL, purchase_id uuid NOT NULL, amount numeric NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, currency text DEFAULT 'SYP'::text NOT NULL, fx_rate numeric DEFAULT 1 NOT NULL, amount_syp numeric);
ALTER TABLE pharmacy_supplier_stage.supplier_payment_allocations ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.debtor_transactions (id uuid DEFAULT gen_random_uuid() NOT NULL, debtor_id uuid NOT NULL, transaction_type text NOT NULL, sale_id uuid, amount numeric NOT NULL, debit numeric DEFAULT 0 NOT NULL, credit numeric DEFAULT 0 NOT NULL, payment_method text, notes text, created_by uuid, created_at timestamp with time zone DEFAULT now() NOT NULL, currency text DEFAULT 'SYP'::text NOT NULL, fx_rate numeric DEFAULT 1 NOT NULL, amount_syp numeric);
ALTER TABLE pharmacy_supplier_stage.debtor_transactions ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.cashbox_counts (id uuid DEFAULT gen_random_uuid() NOT NULL, expected_balance numeric NOT NULL, actual_amount numeric NOT NULL, difference numeric NOT NULL, note text, counted_by uuid, counted_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE pharmacy_supplier_stage.cashbox_counts ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.supplier_refund_receipts (id uuid DEFAULT gen_random_uuid() NOT NULL, supplier_id uuid NOT NULL, purchase_id uuid NOT NULL, currency text NOT NULL, amount numeric NOT NULL, fx_rate numeric NOT NULL, amount_syp numeric NOT NULL, payment_method text NOT NULL, cashbox_entry_id uuid, notes text, created_by uuid, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE pharmacy_supplier_stage.supplier_refund_receipts ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.purchases (id uuid DEFAULT gen_random_uuid() NOT NULL, supplier_id uuid, invoice_number text, subtotal numeric(12,2) DEFAULT 0 NOT NULL, discount numeric(12,2) DEFAULT 0 NOT NULL, total numeric(12,2) DEFAULT 0 NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, created_by uuid, invoice_date date DEFAULT CURRENT_DATE, notes text, status text DEFAULT 'received'::text, paid_amount numeric DEFAULT 0 NOT NULL, due_amount numeric DEFAULT 0 NOT NULL, payment_status text DEFAULT 'unpaid'::text NOT NULL, discount_type text DEFAULT 'none'::text NOT NULL, discount_value numeric DEFAULT 0 NOT NULL, discount_amount numeric DEFAULT 0 NOT NULL, currency text DEFAULT 'SYP'::text NOT NULL, fx_rate numeric DEFAULT 1 NOT NULL, total_syp numeric, credit_amount numeric DEFAULT 0 NOT NULL);
ALTER TABLE pharmacy_supplier_stage.purchases ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.purchase_items (id uuid DEFAULT gen_random_uuid() NOT NULL, purchase_id uuid NOT NULL, product_id uuid NOT NULL, batch_id uuid, quantity numeric(12,2) NOT NULL, purchase_price numeric(12,2) NOT NULL, expiry_date date, created_at timestamp with time zone DEFAULT now() NOT NULL, sale_price numeric DEFAULT 0, bonus_quantity numeric DEFAULT 0 NOT NULL, purchase_currency text DEFAULT 'SYP'::text NOT NULL, purchase_fx_rate numeric DEFAULT 1 NOT NULL, purchase_price_syp numeric, sale_price_currency text DEFAULT 'SYP'::text NOT NULL);
ALTER TABLE pharmacy_supplier_stage.purchase_items ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.product_barcodes (id bigint NOT NULL, product_id uuid NOT NULL, barcode text NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE pharmacy_supplier_stage.product_barcodes ENABLE ROW LEVEL SECURITY;
CREATE TABLE pharmacy_supplier_stage.batches (id uuid DEFAULT gen_random_uuid() NOT NULL, product_id uuid NOT NULL, batch_number text, expiry_date date, quantity numeric(12,2) DEFAULT 0 NOT NULL, purchase_price numeric(12,2) DEFAULT 0 NOT NULL, received_date date DEFAULT CURRENT_DATE NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, supplier_id uuid, purchase_id uuid, purchase_item_id uuid, purchase_currency text DEFAULT 'SYP'::text NOT NULL, purchase_fx_rate numeric DEFAULT 1 NOT NULL, original_purchase_price numeric);
ALTER TABLE pharmacy_supplier_stage.batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_supplier_stage.pharmacy_currency_settings ADD CONSTRAINT pharmacy_currency_settings_id_check CHECK ((id = 1));
ALTER TABLE pharmacy_supplier_stage.order_items ADD CONSTRAINT order_items_quantity_check CHECK ((quantity > (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.suppliers ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.order_items ADD CONSTRAINT order_items_unit_price_check CHECK ((unit_price >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.order_items ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.purchases ADD CONSTRAINT purchases_payment_status_check CHECK ((payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text, 'paid'::text])));
ALTER TABLE pharmacy_supplier_stage.supplier_payments ADD CONSTRAINT supplier_payments_amount_check CHECK ((amount > (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.supplier_payments ADD CONSTRAINT supplier_payments_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.products ADD CONSTRAINT products_reorder_level_check CHECK ((reorder_level >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.products ADD CONSTRAINT products_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.products ADD CONSTRAINT products_barcode_key UNIQUE (barcode);
ALTER TABLE pharmacy_supplier_stage.batches ADD CONSTRAINT batches_quantity_check CHECK ((quantity >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.batches ADD CONSTRAINT batches_purchase_price_check CHECK ((purchase_price >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.batches ADD CONSTRAINT batches_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.customers ADD CONSTRAINT customers_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.orders ADD CONSTRAINT orders_status_check CHECK ((status = ANY (ARRAY['new'::text, 'confirmed'::text, 'preparing'::text, 'ready'::text, 'completed'::text, 'cancelled'::text])));
ALTER TABLE pharmacy_supplier_stage.orders ADD CONSTRAINT orders_total_check CHECK ((total >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.orders ADD CONSTRAINT orders_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.inventory_count_items ADD CONSTRAINT inventory_count_items_count_id_batch_id_key UNIQUE (count_id, batch_id);
ALTER TABLE pharmacy_supplier_stage.purchases ADD CONSTRAINT purchases_subtotal_check CHECK ((subtotal >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.purchases ADD CONSTRAINT purchases_discount_check CHECK ((discount >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.purchases ADD CONSTRAINT purchases_total_check CHECK ((total >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.purchases ADD CONSTRAINT purchases_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.purchase_items ADD CONSTRAINT purchase_items_quantity_check CHECK ((quantity > (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.purchase_items ADD CONSTRAINT purchase_items_purchase_price_check CHECK ((purchase_price >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.purchase_items ADD CONSTRAINT purchase_items_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.sales ADD CONSTRAINT sales_subtotal_check CHECK ((subtotal >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.sales ADD CONSTRAINT sales_discount_check CHECK ((discount >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.sales ADD CONSTRAINT sales_total_check CHECK ((total >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.sales ADD CONSTRAINT sales_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.sale_items ADD CONSTRAINT sale_items_quantity_check CHECK ((quantity > (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.sale_items ADD CONSTRAINT sale_items_unit_price_check CHECK ((unit_price >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.sale_items ADD CONSTRAINT sale_items_unit_cost_check CHECK ((unit_cost >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.sale_items ADD CONSTRAINT sale_items_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.prescriptions ADD CONSTRAINT prescriptions_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.stock_movements ADD CONSTRAINT stock_movements_quantity_check CHECK ((quantity <> (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.stock_movements ADD CONSTRAINT stock_movements_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.pharmacy_settings ADD CONSTRAINT pharmacy_settings_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.offers ADD CONSTRAINT offers_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.medicine_requests ADD CONSTRAINT medicine_requests_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.audit_logs ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.products ADD CONSTRAINT products_parts_per_unit_positive CHECK ((parts_per_unit >= (1)::numeric));
ALTER TABLE pharmacy_supplier_stage.inventory_counts ADD CONSTRAINT inventory_counts_status_check CHECK ((status = ANY (ARRAY['open'::text, 'completed'::text, 'cancelled'::text])));
ALTER TABLE pharmacy_supplier_stage.inventory_counts ADD CONSTRAINT inventory_counts_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.inventory_count_items ADD CONSTRAINT inventory_count_items_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.returns ADD CONSTRAINT returns_return_type_check CHECK ((return_type = ANY (ARRAY['customer'::text, 'supplier'::text])));
ALTER TABLE pharmacy_supplier_stage.returns ADD CONSTRAINT returns_quantity_check CHECK ((quantity > (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.returns ADD CONSTRAINT returns_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.sales ADD CONSTRAINT sales_payment_method_check CHECK ((payment_method = ANY (ARRAY['cash'::text, 'credit'::text])));
ALTER TABLE pharmacy_supplier_stage.debtors ADD CONSTRAINT debtors_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.debtor_transactions ADD CONSTRAINT debtor_transactions_transaction_type_check CHECK ((transaction_type = ANY (ARRAY['sale'::text, 'payment'::text, 'adjustment'::text])));
ALTER TABLE pharmacy_supplier_stage.debtor_transactions ADD CONSTRAINT debtor_transactions_amount_check CHECK ((amount >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.debtor_transactions ADD CONSTRAINT debtor_transactions_debit_check CHECK ((debit >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.debtor_transactions ADD CONSTRAINT debtor_transactions_credit_check CHECK ((credit >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.debtor_transactions ADD CONSTRAINT debtor_transactions_check CHECK ((((debit > (0)::numeric) AND (credit = (0)::numeric)) OR ((credit > (0)::numeric) AND (debit = (0)::numeric)) OR ((debit = (0)::numeric) AND (credit = (0)::numeric))));
ALTER TABLE pharmacy_supplier_stage.debtor_transactions ADD CONSTRAINT debtor_transactions_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.cashbox_entries ADD CONSTRAINT cashbox_entries_amount_check CHECK ((amount <> (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.cashbox_entries ADD CONSTRAINT cashbox_entries_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_amount_check CHECK ((amount > (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_payment_id_purchase_id_key UNIQUE (payment_id, purchase_id);
ALTER TABLE pharmacy_supplier_stage.products ADD CONSTRAINT products_purchase_price_nonnegative CHECK ((purchase_price >= (0)::numeric)) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.products ADD CONSTRAINT products_sale_price_nonnegative CHECK ((sale_price >= (0)::numeric)) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.products ADD CONSTRAINT products_reorder_level_nonnegative CHECK ((reorder_level >= (0)::numeric)) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.pharmacy_currency_settings ADD CONSTRAINT pharmacy_currency_settings_usd_to_syp_check CHECK ((usd_to_syp > (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.pharmacy_currency_settings ADD CONSTRAINT pharmacy_currency_settings_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.pharmacy_currency_history ADD CONSTRAINT pharmacy_currency_history_usd_to_syp_check CHECK ((usd_to_syp > (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.pharmacy_currency_history ADD CONSTRAINT pharmacy_currency_history_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.products ADD CONSTRAINT products_sale_currency_check CHECK ((sale_currency = ANY (ARRAY['SYP'::text, 'USD'::text])));
ALTER TABLE pharmacy_supplier_stage.cashbox_entries ADD CONSTRAINT cashbox_entries_entry_type_check CHECK ((entry_type = ANY (ARRAY['sale_cash'::text, 'debtor_payment'::text, 'expense'::text, 'income'::text, 'purchase_payment'::text, 'withdrawal'::text, 'deposit'::text, 'adjustment'::text, 'customer_return_refund'::text])));
ALTER TABLE pharmacy_supplier_stage.purchase_items ADD CONSTRAINT purchase_items_bonus_quantity_nonnegative CHECK ((bonus_quantity >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.sales ADD CONSTRAINT sales_currency_check CHECK ((currency = ANY (ARRAY['SYP'::text, 'USD'::text])));
ALTER TABLE pharmacy_supplier_stage.sales ADD CONSTRAINT sales_fx_rate_check CHECK ((fx_rate > (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.sale_items ADD CONSTRAINT sale_items_price_currency_check CHECK ((price_currency = ANY (ARRAY['SYP'::text, 'USD'::text])));
ALTER TABLE pharmacy_supplier_stage.sale_items ADD CONSTRAINT sale_items_price_fx_rate_check CHECK ((price_fx_rate > (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.cashbox_entries ADD CONSTRAINT cashbox_entries_currency_check CHECK ((currency = ANY (ARRAY['SYP'::text, 'USD'::text])));
ALTER TABLE pharmacy_supplier_stage.cashbox_entries ADD CONSTRAINT cashbox_entries_fx_rate_check CHECK ((fx_rate > (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.stock_movements ADD CONSTRAINT stock_movements_movement_type_check CHECK ((movement_type = ANY (ARRAY['adjustment'::text, 'customer_return'::text, 'disposal'::text, 'inventory_count'::text, 'purchase'::text, 'purchase_bonus'::text, 'sale'::text, 'supplier_return'::text])));
ALTER TABLE pharmacy_supplier_stage.purchases ADD CONSTRAINT purchases_discount_type_check CHECK ((discount_type = ANY (ARRAY['none'::text, 'percent'::text, 'amount'::text])));
ALTER TABLE pharmacy_supplier_stage.purchases ADD CONSTRAINT purchases_discount_value_nonnegative_check CHECK ((discount_value >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.purchases ADD CONSTRAINT purchases_discount_amount_valid_check CHECK (((discount_amount >= (0)::numeric) AND (discount_amount <= subtotal) AND (total >= (0)::numeric)));
ALTER TABLE pharmacy_supplier_stage.debtor_transactions ADD CONSTRAINT debtor_transactions_currency_check CHECK ((currency = ANY (ARRAY['SYP'::text, 'USD'::text])));
ALTER TABLE pharmacy_supplier_stage.debtor_transactions ADD CONSTRAINT debtor_transactions_fx_rate_check CHECK ((fx_rate > (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.cashbox_counts ADD CONSTRAINT cashbox_counts_actual_amount_check CHECK ((actual_amount >= (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.cashbox_counts ADD CONSTRAINT cashbox_counts_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.supplier_refund_receipts ADD CONSTRAINT supplier_refund_receipts_currency_check CHECK ((currency = ANY (ARRAY['SYP'::text, 'USD'::text])));
ALTER TABLE pharmacy_supplier_stage.supplier_refund_receipts ADD CONSTRAINT supplier_refund_receipts_amount_check CHECK ((amount > (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.supplier_refund_receipts ADD CONSTRAINT supplier_refund_receipts_fx_rate_check CHECK ((fx_rate > (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.supplier_refund_receipts ADD CONSTRAINT supplier_refund_receipts_amount_syp_check CHECK ((amount_syp > (0)::numeric));
ALTER TABLE pharmacy_supplier_stage.supplier_refund_receipts ADD CONSTRAINT supplier_refund_receipts_payment_method_check CHECK ((payment_method = ANY (ARRAY['cash'::text, 'other'::text])));
ALTER TABLE pharmacy_supplier_stage.supplier_refund_receipts ADD CONSTRAINT supplier_refund_receipts_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.purchases ADD CONSTRAINT chk_ab_purchase_credits_valid CHECK (((credit_amount >= (0)::numeric) AND (credit_amount <= (total + 0.05)))) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.purchases ADD CONSTRAINT chk_ab_currency_purchases CHECK ((currency = ANY (ARRAY['SYP'::text, 'USD'::text]))) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.purchases ADD CONSTRAINT chk_ab_fx_purchases CHECK ((fx_rate > (0)::numeric)) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.purchase_items ADD CONSTRAINT chk_ab_currency_purchase_items CHECK ((purchase_currency = ANY (ARRAY['SYP'::text, 'USD'::text]))) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.purchase_items ADD CONSTRAINT chk_ab_fx_purchase_items CHECK ((purchase_fx_rate > (0)::numeric)) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.batches ADD CONSTRAINT chk_ab_currency_batches CHECK ((purchase_currency = ANY (ARRAY['SYP'::text, 'USD'::text]))) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.batches ADD CONSTRAINT chk_ab_fx_batches CHECK ((purchase_fx_rate > (0)::numeric)) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.supplier_payments ADD CONSTRAINT chk_ab_currency_supplier_payments CHECK ((currency = ANY (ARRAY['SYP'::text, 'USD'::text]))) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.supplier_payments ADD CONSTRAINT chk_ab_fx_supplier_payments CHECK ((fx_rate > (0)::numeric)) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.supplier_payment_allocations ADD CONSTRAINT chk_ab_currency_supplier_payment_allocations CHECK ((currency = ANY (ARRAY['SYP'::text, 'USD'::text]))) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.supplier_payment_allocations ADD CONSTRAINT chk_ab_fx_supplier_payment_allocations CHECK ((fx_rate > (0)::numeric)) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.returns ADD CONSTRAINT chk_ab_currency_returns CHECK ((currency = ANY (ARRAY['SYP'::text, 'USD'::text]))) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.returns ADD CONSTRAINT chk_ab_fx_returns CHECK ((fx_rate > (0)::numeric)) NOT VALID;
ALTER TABLE pharmacy_supplier_stage.product_barcodes ADD CONSTRAINT product_barcodes_nonempty CHECK (((barcode = btrim(barcode)) AND (length(barcode) > 0)));
ALTER TABLE pharmacy_supplier_stage.product_barcodes ADD CONSTRAINT product_barcodes_pkey PRIMARY KEY (id);
ALTER TABLE pharmacy_supplier_stage.product_barcodes ADD CONSTRAINT product_barcodes_barcode_key UNIQUE (barcode);
ALTER TABLE pharmacy_supplier_stage.pos_shortcut_preferences ADD CONSTRAINT pos_shortcut_items_array CHECK ((jsonb_typeof(items) = 'array'::text));
ALTER TABLE pharmacy_supplier_stage.pos_shortcut_preferences ADD CONSTRAINT pos_shortcut_items_limit CHECK ((jsonb_array_length(items) <= 30));
ALTER TABLE pharmacy_supplier_stage.pos_shortcut_preferences ADD CONSTRAINT pos_shortcut_preferences_pkey PRIMARY KEY (user_id);
ALTER TABLE pharmacy_supplier_stage.purchase_items ADD CONSTRAINT purchase_items_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES batches(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.orders ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.order_items ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE;
ALTER TABLE pharmacy_supplier_stage.order_items ADD CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT;
ALTER TABLE pharmacy_supplier_stage.supplier_payments ADD CONSTRAINT supplier_payments_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE;
ALTER TABLE pharmacy_supplier_stage.supplier_payments ADD CONSTRAINT supplier_payments_cashbox_entry_id_fkey FOREIGN KEY (cashbox_entry_id) REFERENCES cashbox_entries(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.batches ADD CONSTRAINT batches_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT;
ALTER TABLE pharmacy_supplier_stage.purchases ADD CONSTRAINT purchases_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.purchase_items ADD CONSTRAINT purchase_items_purchase_id_fkey FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE;
ALTER TABLE pharmacy_supplier_stage.purchase_items ADD CONSTRAINT purchase_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT;
ALTER TABLE pharmacy_supplier_stage.sales ADD CONSTRAINT sales_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.sale_items ADD CONSTRAINT sale_items_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE;
ALTER TABLE pharmacy_supplier_stage.sale_items ADD CONSTRAINT sale_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT;
ALTER TABLE pharmacy_supplier_stage.sale_items ADD CONSTRAINT sale_items_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES batches(id) ON DELETE RESTRICT;
ALTER TABLE pharmacy_supplier_stage.prescriptions ADD CONSTRAINT prescriptions_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.prescriptions ADD CONSTRAINT prescriptions_order_id_fkey FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.stock_movements ADD CONSTRAINT stock_movements_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id);
ALTER TABLE pharmacy_supplier_stage.stock_movements ADD CONSTRAINT stock_movements_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES batches(id);
ALTER TABLE pharmacy_supplier_stage.batches ADD CONSTRAINT batches_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.batches ADD CONSTRAINT batches_purchase_id_fkey FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.batches ADD CONSTRAINT batches_purchase_item_id_fkey FOREIGN KEY (purchase_item_id) REFERENCES purchase_items(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.inventory_count_items ADD CONSTRAINT inventory_count_items_count_id_fkey FOREIGN KEY (count_id) REFERENCES inventory_counts(id) ON DELETE CASCADE;
ALTER TABLE pharmacy_supplier_stage.inventory_count_items ADD CONSTRAINT inventory_count_items_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES batches(id) ON DELETE CASCADE;
ALTER TABLE pharmacy_supplier_stage.returns ADD CONSTRAINT returns_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.returns ADD CONSTRAINT returns_sale_item_id_fkey FOREIGN KEY (sale_item_id) REFERENCES sale_items(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.returns ADD CONSTRAINT returns_purchase_id_fkey FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.returns ADD CONSTRAINT returns_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id);
ALTER TABLE pharmacy_supplier_stage.returns ADD CONSTRAINT returns_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES batches(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.sales ADD CONSTRAINT sales_debtor_id_fkey FOREIGN KEY (debtor_id) REFERENCES debtors(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.debtor_transactions ADD CONSTRAINT debtor_transactions_debtor_id_fkey FOREIGN KEY (debtor_id) REFERENCES debtors(id) ON DELETE CASCADE;
ALTER TABLE pharmacy_supplier_stage.debtor_transactions ADD CONSTRAINT debtor_transactions_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.cashbox_entries ADD CONSTRAINT cashbox_entries_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.cashbox_entries ADD CONSTRAINT cashbox_entries_debtor_transaction_id_fkey FOREIGN KEY (debtor_transaction_id) REFERENCES debtor_transactions(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.cashbox_entries ADD CONSTRAINT cashbox_entries_purchase_id_fkey FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES supplier_payments(id) ON DELETE CASCADE;
ALTER TABLE pharmacy_supplier_stage.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_purchase_id_fkey FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE;
ALTER TABLE pharmacy_supplier_stage.cashbox_entries ADD CONSTRAINT cashbox_entries_supplier_payment_id_fkey FOREIGN KEY (supplier_payment_id) REFERENCES supplier_payments(id) ON DELETE SET NULL;
ALTER TABLE pharmacy_supplier_stage.inventory_count_items ADD CONSTRAINT inventory_count_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
ALTER TABLE pharmacy_supplier_stage.supplier_refund_receipts ADD CONSTRAINT supplier_refund_receipts_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id);
ALTER TABLE pharmacy_supplier_stage.supplier_refund_receipts ADD CONSTRAINT supplier_refund_receipts_purchase_id_fkey FOREIGN KEY (purchase_id) REFERENCES purchases(id);
ALTER TABLE pharmacy_supplier_stage.supplier_refund_receipts ADD CONSTRAINT supplier_refund_receipts_cashbox_entry_id_fkey FOREIGN KEY (cashbox_entry_id) REFERENCES cashbox_entries(id);
ALTER TABLE pharmacy_supplier_stage.product_barcodes ADD CONSTRAINT product_barcodes_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.ab_apply_supplier_return_credit_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
BEGIN
 IF NEW.return_type='supplier' AND NEW.purchase_id IS NOT NULL THEN
  UPDATE pharmacy_supplier_stage.purchases SET credit_amount=credit_amount+NEW.amount WHERE id=NEW.purchase_id;
  PERFORM pharmacy_supplier_stage.admin_refresh_purchase_balance(NEW.purchase_id);
 END IF;
 RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.ab_immutable_supplier_return_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
BEGIN
 IF OLD.return_type='supplier' THEN
  RAISE EXCEPTION 'لا يمكن تعديل أو حذف إشعار دائن مسجل. استخدم تسوية موثقة بدلاً من ذلك';
 END IF;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.ab_validate_supplier_return_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_currency text;v_rate numeric;v_total numeric;v_subtotal numeric;v_credit numeric;
 v_batch_price numeric;v_pi_cost numeric;v_batch_purchase uuid;v_expected numeric;
BEGIN
 IF NEW.return_type<>'supplier' OR NEW.purchase_id IS NULL THEN RETURN NEW; END IF;
 SELECT currency,fx_rate,total,subtotal,credit_amount INTO v_currency,v_rate,v_total,v_subtotal,v_credit
 FROM pharmacy_supplier_stage.purchases WHERE id=NEW.purchase_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'فاتورة المرتجع غير موجودة'; END IF;
 SELECT b.purchase_price,b.purchase_id,pi.purchase_price_syp
 INTO v_batch_price,v_batch_purchase,v_pi_cost
 FROM pharmacy_supplier_stage.batches b LEFT JOIN pharmacy_supplier_stage.purchase_items pi ON pi.id=b.purchase_item_id
 WHERE b.id=NEW.batch_id;
 IF NOT FOUND OR v_batch_purchase IS DISTINCT FROM NEW.purchase_id THEN
  RAISE EXCEPTION 'دفعة المرتجع لا تتبع لفاتورة المورد'; END IF;
 IF NEW.currency IS DISTINCT FROM v_currency OR NEW.fx_rate IS DISTINCT FROM v_rate THEN
  RAISE EXCEPTION 'عملة أو سعر صرف المرتجع لا يطابق فاتورة المورد'; END IF;
 IF NEW.quantity IS NULL OR NEW.quantity<=0 THEN RAISE EXCEPTION 'كمية المرتجع غير صالحة'; END IF;
 v_expected:=CASE WHEN v_currency='USD' THEN
    ROUND(NEW.quantity*v_batch_price/v_rate,2)
   WHEN v_pi_cost IS NOT NULL THEN ROUND(NEW.quantity*v_batch_price,2)
   ELSE ROUND(NEW.quantity*v_batch_price*
       CASE WHEN v_subtotal>0 THEN v_total/v_subtotal ELSE 1 END,2) END;
 -- The last returned line may be rounded down to the invoice's remaining creditable total.
 v_expected:=LEAST(v_expected,GREATEST(v_total-v_credit,0));
 IF NEW.amount IS NULL OR ABS(NEW.amount-v_expected)>0.01 THEN
  RAISE EXCEPTION 'قيمة إشعار الدائن لا تطابق تكلفة المرتجع المحاسبية'; END IF;
 IF NEW.amount_syp IS DISTINCT FROM (CASE WHEN v_currency='USD'
      THEN ROUND(NEW.amount*v_rate,2) ELSE NEW.amount END) THEN
  RAISE EXCEPTION 'تحويل إشعار الدائن إلى الليرة غير مطابق'; END IF;
 RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.adjust_stock(p_batch_id uuid, p_delta numeric, p_note text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  b pharmacy_supplier_stage.batches%rowtype;
  old_qty numeric;
  new_qty numeric;
  product_name text;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF COALESCE(p_delta,0)=0 THEN RAISE EXCEPTION 'Stock adjustment cannot be zero'; END IF;
  SELECT * INTO b FROM pharmacy_supplier_stage.batches WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Batch not found'; END IF;
  old_qty:=COALESCE(b.quantity,0); new_qty:=old_qty+p_delta;
  IF new_qty<0 THEN RAISE EXCEPTION 'Insufficient stock: الكمية بعد التعديل لا يمكن أن تكون سالبة'; END IF;
  UPDATE pharmacy_supplier_stage.batches SET quantity=new_qty WHERE id=p_batch_id;
  INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
  VALUES(b.product_id,b.id,'adjustment',p_delta,p_note,auth.uid());
  SELECT name INTO product_name FROM pharmacy_supplier_stage.products WHERE id=b.product_id;
  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'adjust_stock','batch',b.id,jsonb_build_object(
    'product_id',b.product_id,'product_name',COALESCE(product_name,'—'),
    'old_quantity',old_qty,'new_quantity',new_qty,'delta',p_delta,'note',p_note
  ));
  RETURN new_qty;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_accounting_report(p_start timestamp with time zone, p_end timestamp with time zone, p_compare_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_compare_end timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v jsonb; f jsonb; cf jsonb;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 f:=pharmacy_supplier_stage.admin_dashboard_financial_summary(p_start,p_end);
 cf:=CASE WHEN p_compare_start IS NULL OR p_compare_end IS NULL THEN NULL ELSE pharmacy_supplier_stage.admin_dashboard_financial_summary(p_compare_start,p_compare_end) END;
 SELECT jsonb_build_object(
  'period',jsonb_build_object('start',p_start,'end',p_end),
  'summary',jsonb_build_object('sales',COALESCE((f->>'sales')::numeric,0),'cash_sales',COALESCE((SELECT SUM(total) FROM pharmacy_supplier_stage.sales WHERE payment_method='cash' AND created_at>=p_start AND created_at<p_end),0),'credit_sales',COALESCE((SELECT SUM(total) FROM pharmacy_supplier_stage.sales WHERE payment_method='credit' AND created_at>=p_start AND created_at<p_end),0),'debt_collections',COALESCE((f->>'debtor_payments')::numeric,0),'new_debt',COALESCE((SELECT SUM(debit) FROM pharmacy_supplier_stage.debtor_transactions WHERE transaction_type='sale' AND created_at>=p_start AND created_at<p_end),0),'purchases',COALESCE((f->>'purchases')::numeric,0),'gross_profit',COALESCE((f->>'profit')::numeric,0),'return_profit',COALESCE((f->>'customer_return_cost')::numeric,0),'supplier_returns',COALESCE((SELECT SUM(amount) FROM pharmacy_supplier_stage.returns WHERE return_type='supplier' AND created_at>=p_start AND created_at<p_end),0),'net_purchases',COALESCE((f->>'purchases')::numeric,0)-COALESCE((SELECT SUM(amount) FROM pharmacy_supplier_stage.returns WHERE return_type='supplier' AND created_at>=p_start AND created_at<p_end),0),'profit',COALESCE((f->>'profit')::numeric,0),'margin',COALESCE((f->>'margin')::numeric,0),'cash_in',COALESCE((f->>'cash_in')::numeric,0),'cash_out',COALESCE((f->>'cash_out')::numeric,0),'cash_net',COALESCE((f->>'cash_net')::numeric,0),'cash_balance',COALESCE((SELECT SUM(amount) FROM pharmacy_supplier_stage.cashbox_entries),0),'outstanding_debt',COALESCE((SELECT SUM(debit-credit) FROM pharmacy_supplier_stage.debtor_transactions),0),'sales_count',COALESCE((f->>'invoice_count')::bigint,0),'purchase_count',COALESCE((f->>'purchase_count')::bigint,0),'customer_returns',COALESCE((f->>'customer_returns')::numeric,0),'net_sales',COALESCE((f->>'net_sales')::numeric,0),'cost_of_goods',COALESCE((f->>'cost_of_goods')::numeric,0)),
  'comparison',CASE WHEN cf IS NULL THEN NULL ELSE jsonb_build_object('sales',COALESCE((cf->>'sales')::numeric,0),'net_sales',COALESCE((cf->>'net_sales')::numeric,0),'purchases',COALESCE((cf->>'purchases')::numeric,0),'profit',COALESCE((cf->>'profit')::numeric,0),'new_debt',COALESCE((SELECT SUM(debit) FROM pharmacy_supplier_stage.debtor_transactions WHERE transaction_type='sale' AND created_at>=p_compare_start AND created_at<p_compare_end),0),'debt_collections',COALESCE((cf->>'debtor_payments')::numeric,0)) END,
  'sales_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'created_at',s.created_at,'total',s.total,'payment_method',s.payment_method,'paid_amount',s.paid_amount,'due_amount',s.due_amount,'debtor_id',s.debtor_id,'debtor_name',d.name) ORDER BY s.created_at DESC) FROM pharmacy_supplier_stage.sales s LEFT JOIN pharmacy_supplier_stage.debtors d ON d.id=s.debtor_id WHERE s.created_at>=p_start AND s.created_at<p_end),'[]'::jsonb),
  'purchase_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'created_at',p.created_at,'invoice_number',p.invoice_number,'supplier_name',s.name,'total',p.total,'bonus_quantity',COALESCE((SELECT SUM(pi.bonus_quantity) FROM pharmacy_supplier_stage.purchase_items pi WHERE pi.purchase_id=p.id),0)) ORDER BY p.created_at DESC) FROM pharmacy_supplier_stage.purchases p LEFT JOIN pharmacy_supplier_stage.suppliers s ON s.id=p.supplier_id WHERE p.created_at>=p_start AND p.created_at<p_end),'[]'::jsonb),
  'debt_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'created_at',t.created_at,'type',t.transaction_type,'debtor_name',d.name,'amount',t.amount,'debit',t.debit,'credit',t.credit,'notes',t.notes) ORDER BY t.created_at DESC) FROM pharmacy_supplier_stage.debtor_transactions t JOIN pharmacy_supplier_stage.debtors d ON d.id=t.debtor_id WHERE t.created_at>=p_start AND t.created_at<p_end),'[]'::jsonb),
  'cash_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'created_at',c.created_at,'type',c.entry_type,'amount',c.amount,'description',c.description) ORDER BY c.created_at DESC) FROM pharmacy_supplier_stage.cashbox_entries c WHERE c.created_at>=p_start AND c.created_at<p_end),'[]'::jsonb),
  'return_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'created_at',r.created_at,'type',r.return_type,'product_name',p.name,'quantity',r.quantity,'amount',r.amount,'reason',r.reason) ORDER BY r.created_at DESC) FROM pharmacy_supplier_stage.returns r LEFT JOIN pharmacy_supplier_stage.products p ON p.id=r.product_id WHERE r.created_at>=p_start AND r.created_at<p_end),'[]'::jsonb),
  'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_id',x.product_id,'product_name',x.product_name,'quantity',x.quantity,'sales',x.sales,'cost',x.cost,'gross_profit',x.gross_profit,'return_amount',x.return_amount,'return_profit',x.return_profit,'net_sales',x.sales-x.return_amount,'net_profit',x.gross_profit-x.return_profit) ORDER BY (x.sales-x.return_amount) DESC) FROM (SELECT p.id product_id,p.name product_name,SUM(si.quantity) quantity,SUM(si.quantity*si.unit_price) sales,SUM(si.quantity*si.unit_cost) cost,SUM(si.quantity*(si.unit_price-si.unit_cost)) gross_profit,COALESCE((SELECT SUM(r.amount) FROM pharmacy_supplier_stage.returns r WHERE r.return_type='customer' AND r.product_id=p.id AND r.created_at>=p_start AND r.created_at<p_end),0) return_amount,COALESCE((SELECT SUM(r.quantity*(si2.unit_price-si2.unit_cost)) FROM pharmacy_supplier_stage.returns r JOIN pharmacy_supplier_stage.sale_items si2 ON si2.id=r.sale_item_id WHERE r.return_type='customer' AND r.product_id=p.id AND r.created_at>=p_start AND r.created_at<p_end),0) return_profit FROM pharmacy_supplier_stage.sale_items si JOIN pharmacy_supplier_stage.products p ON p.id=si.product_id JOIN pharmacy_supplier_stage.sales s ON s.id=si.sale_id WHERE s.created_at>=p_start AND s.created_at<p_end GROUP BY p.id,p.name) x),'[]'::jsonb),
  'checks',jsonb_build_object('sales_split_delta',COALESCE((SELECT SUM(total) FROM pharmacy_supplier_stage.sales WHERE created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(total) FROM pharmacy_supplier_stage.sales WHERE payment_method='cash' AND created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(total) FROM pharmacy_supplier_stage.sales WHERE payment_method='credit' AND created_at>=p_start AND created_at<p_end),0),'sales_item_mismatch_count',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.sales s WHERE s.created_at>=p_start AND s.created_at<p_end AND ABS(COALESCE((SELECT SUM(si.quantity*si.unit_price) FROM pharmacy_supplier_stage.sale_items si WHERE si.sale_id=s.id),0)-(COALESCE(s.total,0)+COALESCE(s.discount,0)))>0.01),0),'customer_return_mismatch_count',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.returns r JOIN pharmacy_supplier_stage.sale_items si ON si.id=r.sale_item_id WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end AND r.quantity>(si.quantity+0.000001)),0),'supplier_return_mismatch_count',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.returns r JOIN pharmacy_supplier_stage.purchase_items pi ON pi.id=(SELECT b2.purchase_item_id FROM pharmacy_supplier_stage.batches b2 WHERE b2.id=r.batch_id) WHERE r.return_type='supplier' AND r.created_at>=p_start AND r.created_at<p_end AND r.quantity>(pi.quantity+pi.bonus_quantity+0.000001)),0),'cash_delta',0)
 ) INTO v;
 RETURN v;
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_batch_trace(p_batch_id uuid)
 RETURNS TABLE(batch_id uuid, supplier_id uuid, supplier_name text, purchase_id uuid, invoice_number text, invoice_date date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  SELECT b.id,b.supplier_id,s.name,b.purchase_id,p.invoice_number,p.invoice_date
  FROM pharmacy_supplier_stage.batches b
  LEFT JOIN pharmacy_supplier_stage.suppliers s ON s.id=b.supplier_id
  LEFT JOIN pharmacy_supplier_stage.purchases p ON p.id=b.purchase_id
  WHERE pharmacy_supplier_stage.is_admin() AND b.id=p_batch_id;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_bulk_sale_price_change(p_currency text, p_percent numeric, p_apply boolean DEFAULT false, p_expected_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
declare v_currency text:=upper(trim(coalesce(p_currency,'')));v_count integer;v_token text;v_examples jsonb;v_changed integer;
begin
 if not pharmacy_supplier_stage.is_admin() then raise exception 'غير مصرح';end if;
 if v_currency not in ('SYP','USD','ALL') then raise exception 'عملة غير صالحة';end if;
 if p_percent is null or p_percent<=-100 or p_percent>100 then raise exception 'النسبة يجب أن تكون أكبر من -100 وأقل من أو تساوي 100';end if;
 if p_apply then
  if p_expected_token is null then raise exception 'يجب معاينة التغييرات قبل التأكيد';end if;
  perform 1 from pharmacy_supplier_stage.products where active=true and sale_price>0 and (v_currency='ALL' or upper(coalesce(sale_currency,'SYP'))=v_currency) order by id for update;
 end if;
 select count(*),md5(coalesce(string_agg(id::text||':'||sale_price::text||':'||upper(coalesce(sale_currency,'SYP')),'|' order by id),'')||':'||v_currency||':'||p_percent::text)
 into v_count,v_token from pharmacy_supplier_stage.products where active=true and sale_price>0 and (v_currency='ALL' or upper(coalesce(sale_currency,'SYP'))=v_currency);
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into v_examples from (
 select name,barcode,sale_currency,sale_price as old_price,round(sale_price*(1+p_percent/100),2) as new_price
 from pharmacy_supplier_stage.products where active=true and sale_price>0 and (v_currency='ALL' or upper(coalesce(sale_currency,'SYP'))=v_currency)
 order by name,id limit 8) t;
 if not p_apply then return jsonb_build_object('count',v_count,'token',v_token,'examples',v_examples,'currency',v_currency,'percent',p_percent);end if;
 if v_token<>p_expected_token then raise exception 'تغيرت الأسعار بعد المعاينة. يرجى إعادة المعاينة';end if;
 update pharmacy_supplier_stage.products set sale_price=round(sale_price*(1+p_percent/100),2),updated_at=now()
 where active=true and sale_price>0 and (v_currency='ALL' or upper(coalesce(sale_currency,'SYP'))=v_currency);
 get diagnostics v_changed=row_count;
 insert into pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,details) values(auth.uid(),'bulk_sale_price_change','products',jsonb_build_object('currency',v_currency,'percent',p_percent,'affected',v_changed,'preview_token',v_token));
 return jsonb_build_object('updated',v_changed,'currency',v_currency,'percent',p_percent);
end;$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_cashbox_count_history(p_limit integer DEFAULT 10)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  RETURN QUERY
    SELECT jsonb_build_object('id', c.id, 'expected_balance', c.expected_balance,
      'actual_amount', c.actual_amount, 'difference', c.difference,
      'note', c.note, 'counted_at', c.counted_at)
    FROM pharmacy_supplier_stage.cashbox_counts c
    ORDER BY c.counted_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 10), 1), 100);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_cashbox_entry(p_type text, p_amount numeric, p_description text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_id uuid; v_amount numeric;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_amount IS NULL OR p_amount=0 THEN RAISE EXCEPTION 'المبلغ لا يمكن أن يكون صفراً'; END IF;
 IF p_type NOT IN ('expense','income','withdrawal','deposit','adjustment') THEN RAISE EXCEPTION 'نوع حركة صندوق غير صالح'; END IF;
 v_amount:=CASE WHEN p_type IN ('expense','withdrawal') THEN -abs(p_amount) ELSE abs(p_amount) END;
 INSERT INTO pharmacy_supplier_stage.cashbox_entries(entry_type,amount,description,created_by,currency,fx_rate,amount_syp)
 VALUES(p_type,v_amount,p_description,auth.uid(),'SYP',1,v_amount) RETURNING id INTO v_id;
 INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'cashbox_entry','cashbox',v_id,
 jsonb_build_object('type',p_type,'amount',p_amount,'signed_amount',v_amount,'currency','SYP','description',p_description));
 RETURN v_id;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_cashbox_manual_entry(p_type text, p_amount numeric, p_description text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_id uuid; v_amount numeric;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_type NOT IN ('expense','income','withdrawal','deposit','adjustment') THEN RAISE EXCEPTION 'نوع حركة صندوق غير صالح'; END IF;
 IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر'; END IF;
 v_amount:=CASE WHEN p_type IN ('expense','withdrawal') THEN -abs(p_amount) ELSE abs(p_amount) END;
 INSERT INTO pharmacy_supplier_stage.cashbox_entries(entry_type,amount,description,created_by,currency,fx_rate,amount_syp)
 VALUES(p_type,v_amount,NULLIF(trim(COALESCE(p_description,'')),''),auth.uid(),'SYP',1,v_amount)
 RETURNING id INTO v_id;
 INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'cashbox_entry','cashbox',v_id,
 jsonb_build_object('type',p_type,'amount',abs(p_amount),'signed_amount',v_amount,'currency','SYP','description',p_description));
 RETURN jsonb_build_object('id',v_id,'type',p_type,'amount',v_amount);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_cashbox_reconcile()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 RETURN jsonb_build_object('sales_added',0,'debt_payments_added',0,
  'customer_returns_added',0,'supplier_payments_added',0,
  'automatic_reconciliation_disabled',true);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_cashbox_summary(p_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
 SELECT pharmacy_supplier_stage.admin_cashbox_summary_v2(p_start,p_end);
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_cashbox_summary_v2(p_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE s timestamptz:=COALESCE(p_start,'1900-01-01'::timestamptz);
 e timestamptz:=COALESCE(p_end,'2999-12-31'::timestamptz); v jsonb;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF e<=s THEN RAISE EXCEPTION 'فترة الصندوق غير صالحة'; END IF;
 IF EXISTS(SELECT 1 FROM pharmacy_supplier_stage.cashbox_entries WHERE currency='USD' AND amount_syp IS NULL) THEN
   RAISE EXCEPTION 'حركات دولار بلا مقابل ليرة؛ أوقف التقرير وصحح المصدر'; END IF;
 SELECT jsonb_build_object(
  'cash_in',COALESCE(SUM(GREATEST(COALESCE(c.amount_syp,c.amount),0)),0),
  'cash_out',COALESCE(SUM(GREATEST(-COALESCE(c.amount_syp,c.amount),0)),0),
  'net',COALESCE(SUM(COALESCE(c.amount_syp,c.amount)),0),
  'balance',COALESCE((SELECT SUM(COALESCE(x.amount_syp,x.amount)) FROM pharmacy_supplier_stage.cashbox_entries x),0),
  'entries',COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'id',x.id,'type',x.entry_type,'amount',COALESCE(x.amount_syp,x.amount),
    'original_amount',x.amount,'currency',x.currency,'fx_rate',x.fx_rate,
    'description',x.description,'created_at',x.created_at
  ) ORDER BY x.created_at DESC) FROM pharmacy_supplier_stage.cashbox_entries x WHERE x.created_at>=s AND x.created_at<e),'[]'::jsonb)
 ) INTO v FROM pharmacy_supplier_stage.cashbox_entries c WHERE c.created_at>=s AND c.created_at<e;
 RETURN v;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_complete_inventory_count(p_count_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  r record;
  b record;
  v_diff numeric := 0;
  v_changes integer := 0;
  v_remaining numeric;
  v_take numeric;
  v_current numeric;
  v_target numeric;
  v_product uuid;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pharmacy_supplier_stage.inventory_counts WHERE id=p_count_id) THEN
    RAISE EXCEPTION 'جرد المخزون غير موجود';
  END IF;
  IF EXISTS (SELECT 1 FROM pharmacy_supplier_stage.inventory_counts WHERE id=p_count_id AND status<>'open') THEN
    RAISE EXCEPTION 'Inventory count is not open';
  END IF;
  IF EXISTS (SELECT 1 FROM pharmacy_supplier_stage.inventory_count_items WHERE count_id=p_count_id AND actual_quantity IS NULL) THEN
    RAISE EXCEPTION 'أدخل الكمية الفعلية لكل منتج';
  END IF;

  FOR r IN SELECT * FROM pharmacy_supplier_stage.inventory_count_items WHERE count_id=p_count_id ORDER BY id LOOP
    IF r.product_id IS NOT NULL THEN
      v_product := r.product_id;
      v_target := GREATEST(0, r.actual_quantity);
      SELECT COALESCE(SUM(quantity),0) INTO v_current
      FROM pharmacy_supplier_stage.batches
      WHERE product_id=v_product;

      IF v_target <> v_current THEN
        IF v_target > v_current THEN
          SELECT id INTO b
          FROM pharmacy_supplier_stage.batches
          WHERE product_id=v_product
          ORDER BY expiry_date NULLS LAST, received_date NULLS LAST, id
          LIMIT 1
          FOR UPDATE;

          IF b.id IS NULL THEN
            RAISE EXCEPTION 'لا توجد دفعة موجودة للمنتج لإضافة الكمية. أضف دفعة أولاً ثم أعد الجرد.';
          END IF;

          v_take := v_target-v_current;
          UPDATE pharmacy_supplier_stage.batches SET quantity=quantity+v_take WHERE id=b.id;
          INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
          VALUES(v_product,b.id,'inventory_count',v_take,'تسوية جرد إجمالي للمنتج',auth.uid());
          v_changes := v_changes+1;
        ELSE
          v_remaining := v_current-v_target;
          FOR b IN
            SELECT id,quantity
            FROM pharmacy_supplier_stage.batches
            WHERE product_id=v_product AND quantity>0
            ORDER BY expiry_date DESC NULLS LAST, received_date DESC NULLS LAST, id DESC
            FOR UPDATE
          LOOP
            EXIT WHEN v_remaining<=0;
            v_take := LEAST(b.quantity,v_remaining);
            UPDATE pharmacy_supplier_stage.batches SET quantity=quantity-v_take WHERE id=b.id;
            INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
            VALUES(v_product,b.id,'inventory_count',-v_take,'تسوية جرد إجمالي للمنتج',auth.uid());
            v_remaining := v_remaining-v_take;
            v_changes := v_changes+1;
          END LOOP;
        END IF;
        v_diff := v_diff + (v_target-v_current);
      END IF;
    ELSE
      IF r.difference<>0 THEN
        UPDATE pharmacy_supplier_stage.batches SET quantity=GREATEST(0,r.actual_quantity) WHERE id=r.batch_id;
        SELECT product_id INTO v_product FROM pharmacy_supplier_stage.batches WHERE id=r.batch_id;
        INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
        VALUES(v_product,r.batch_id,'inventory_count',r.difference,'تسوية جرد v5.16',auth.uid());
        v_diff := v_diff+r.difference;
        v_changes := v_changes+1;
      END IF;
    END IF;
  END LOOP;

  UPDATE pharmacy_supplier_stage.inventory_counts
  SET status='completed', completed_at=now()
  WHERE id=p_count_id;

  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(
    auth.uid(),
    'inventory_count_complete',
    'inventory_count',
    p_count_id,
    jsonb_build_object('changes',v_changes,'net_difference',v_diff,'mode','aggregate_product_v5_16')
  );

  RETURN jsonb_build_object('id',p_count_id,'changes',v_changes,'net_difference',v_diff);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_create_debtor(p_name text, p_phone text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_id uuid;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF NULLIF(trim(COALESCE(p_name,'')),'') IS NULL THEN RAISE EXCEPTION 'اسم المتدين مطلوب'; END IF;
 INSERT INTO pharmacy_supplier_stage.debtors(name,phone,address,notes) VALUES(trim(p_name),NULLIF(trim(COALESCE(p_phone,'')),''),NULLIF(trim(COALESCE(p_address,'')),''),NULLIF(trim(COALESCE(p_notes,'')),'')) RETURNING id INTO v_id;
 INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details) VALUES(auth.uid(),'admin_create_debtor','debtor',v_id,jsonb_build_object('name',trim(p_name),'phone',p_phone));
 RETURN v_id;
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_create_purchase(p_supplier_id uuid, p_invoice_number text DEFAULT NULL::text, p_invoice_date date DEFAULT CURRENT_DATE, p_notes text DEFAULT NULL::text, p_items jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  v_purchase_id uuid:=gen_random_uuid(); v_item jsonb; v_item_id uuid;
  v_batch_id uuid; v_bonus_batch_id uuid; v_total numeric:=0;
  v_qty numeric; v_bonus numeric; v_purchase_price numeric; v_sale_price numeric;
  v_product_id uuid; v_expiry date; v_invoice text; v_bonus_total numeric:=0;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_supplier_id IS NULL OR NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.suppliers WHERE id=p_supplier_id) THEN RAISE EXCEPTION 'Supplier not found'; END IF;
  IF jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 THEN RAISE EXCEPTION 'Purchase invoice must contain at least one item'; END IF;
  v_invoice:=NULLIF(trim(COALESCE(p_invoice_number,'')),'');
  IF v_invoice IS NULL THEN v_invoice:='PUR-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'); END IF;

  INSERT INTO pharmacy_supplier_stage.purchases(supplier_id,invoice_number,invoice_date,notes,status,total)
  VALUES(p_supplier_id,v_invoice,COALESCE(p_invoice_date,CURRENT_DATE),NULLIF(trim(COALESCE(p_notes,'')),''),'received',0)
  RETURNING id INTO v_purchase_id;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id:=NULLIF(v_item->>'product_id','')::uuid;
    v_qty:=COALESCE((v_item->>'quantity')::numeric,0);
    v_bonus:=GREATEST(COALESCE((v_item->>'bonus_quantity')::numeric,0),0);
    v_purchase_price:=COALESCE((v_item->>'purchase_price')::numeric,0);
    v_sale_price:=COALESCE((v_item->>'sale_price')::numeric,0);
    v_expiry:=NULLIF(v_item->>'expiry_date','')::date;
    IF v_product_id IS NULL OR NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.products WHERE id=v_product_id) THEN RAISE EXCEPTION 'Invalid product in purchase invoice'; END IF;
    IF v_qty<=0 THEN RAISE EXCEPTION 'Purchase quantity must be greater than zero'; END IF;
    IF v_expiry IS NULL THEN RAISE EXCEPTION 'Expiry date is required for every purchase item'; END IF;
    IF v_purchase_price<0 OR v_sale_price<0 THEN RAISE EXCEPTION 'Prices cannot be negative'; END IF;

    INSERT INTO pharmacy_supplier_stage.purchase_items(purchase_id,product_id,quantity,bonus_quantity,purchase_price,expiry_date,sale_price)
    VALUES(v_purchase_id,v_product_id,v_qty,v_bonus,v_purchase_price,v_expiry,v_sale_price)
    RETURNING id INTO v_item_id;

    -- Paid stock: normal purchase cost.
    v_batch_id:=gen_random_uuid();
    INSERT INTO pharmacy_supplier_stage.batches(id,product_id,batch_number,expiry_date,quantity,purchase_price,received_date,supplier_id,purchase_id,purchase_item_id)
    VALUES(v_batch_id,v_product_id,'AUTO-'||substr(replace(v_item_id::text,'-',''),1,12),v_expiry,v_qty,v_purchase_price,COALESCE(p_invoice_date,CURRENT_DATE),p_supplier_id,v_purchase_id,v_item_id);
    UPDATE pharmacy_supplier_stage.purchase_items SET batch_id=v_batch_id WHERE id=v_item_id;
    INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
    VALUES(v_product_id,v_batch_id,'purchase',v_qty,'استلام فاتورة شراء '||v_invoice,auth.uid());

    -- Bonus stock: separate zero-cost batch, same expiry/purchase traceability.
    IF v_bonus>0 THEN
      v_bonus_batch_id:=gen_random_uuid();
      INSERT INTO pharmacy_supplier_stage.batches(id,product_id,batch_number,expiry_date,quantity,purchase_price,received_date,supplier_id,purchase_id,purchase_item_id)
      VALUES(v_bonus_batch_id,v_product_id,'AUTO-'||substr(replace(v_item_id::text,'-',''),1,12)||'-BONUS',v_expiry,v_bonus,0,COALESCE(p_invoice_date,CURRENT_DATE),p_supplier_id,v_purchase_id,v_item_id);
      INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
      VALUES(v_product_id,v_bonus_batch_id,'purchase_bonus',v_bonus,'بونص مجاني من فاتورة شراء '||v_invoice,auth.uid());
    END IF;

    -- Product defaults are based on the paid invoice price only; bonus never changes them.
    UPDATE pharmacy_supplier_stage.products
    SET purchase_price=v_purchase_price,
        sale_price=CASE WHEN v_sale_price>0 THEN v_sale_price ELSE sale_price END,
        updated_at=now()
    WHERE id=v_product_id;

    v_total:=v_total+(v_qty*v_purchase_price);
    v_bonus_total:=v_bonus_total+v_bonus;
  END LOOP;

  UPDATE pharmacy_supplier_stage.purchases SET total=v_total WHERE id=v_purchase_id;
  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'admin_create_purchase','purchase',v_purchase_id,
         jsonb_build_object('supplier_id',p_supplier_id,'invoice_number',v_invoice,'total',v_total,'bonus_quantity',v_bonus_total,'items_count',jsonb_array_length(p_items)));
  RETURN jsonb_build_object('id',v_purchase_id,'public_code',v_invoice,'total',v_total,'bonus_quantity',v_bonus_total);
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_create_purchase_syp_v1(p_supplier_id uuid, p_new_supplier jsonb, p_invoice_number text, p_invoice_date date, p_notes text, p_items jsonb, p_payment_amount numeric, p_payment_method text, p_payment_notes text, p_discount_type text, p_discount_value numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_result jsonb;v_purchase_id uuid;v_factor numeric;v_item jsonb;v_pid uuid;
 v_currency text;v_fx numeric;v_sale_price numeric;v_used uuid[]:=ARRAY[]::uuid[];
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 THEN
  RAISE EXCEPTION 'فاتورة الشراء فارغة'; END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
  v_pid:=NULLIF(v_item->>'product_id','')::uuid;
  v_currency:=upper(COALESCE(NULLIF(v_item->>'sale_currency',''),'SYP'));
  v_sale_price:=NULLIF(v_item->>'sale_price','')::numeric;
  IF v_pid IS NULL OR v_pid=ANY(v_used) OR v_currency NOT IN ('USD','SYP') THEN
   RAISE EXCEPTION 'صنف مكرر أو عملة بيع غير صالحة'; END IF;
  IF v_sale_price IS NULL OR v_sale_price<=0 THEN RAISE EXCEPTION 'سعر البيع غير صالح'; END IF;
  v_used:=array_append(v_used,v_pid);
 END LOOP;
 SELECT usd_to_syp INTO v_fx FROM pharmacy_supplier_stage.pharmacy_currency_settings WHERE id=1 FOR SHARE;
 IF v_fx IS NULL THEN RAISE EXCEPTION 'إعداد العملة غير موجود'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_items) x WHERE upper(COALESCE(NULLIF(x->>'sale_currency',''),'SYP'))='USD')
     AND v_fx<=1 THEN RAISE EXCEPTION 'سعر صرف الدولار غير مضبوط لتسعير البيع'; END IF;
 v_result:=pharmacy_supplier_stage.admin_create_purchase_with_payment_discount(
  p_supplier_id,p_new_supplier,p_invoice_number,p_invoice_date,p_notes,p_items,
  p_payment_amount,p_payment_method,p_payment_notes,p_discount_type,p_discount_value);
 v_purchase_id:=(v_result->>'id')::uuid;
 IF v_purchase_id IS NULL THEN RAISE EXCEPTION 'لم يتم إرجاع رقم فاتورة الشراء'; END IF;
 SELECT CASE WHEN subtotal>0 THEN total/subtotal ELSE 1 END INTO v_factor
 FROM pharmacy_supplier_stage.purchases WHERE id=v_purchase_id FOR UPDATE;
 IF v_factor<0 OR v_factor>1 THEN RAISE EXCEPTION 'نسبة خصم الفاتورة غير صالحة'; END IF;
 -- Only NEW invoice lines are updated, never existing stock batches.
 UPDATE pharmacy_supplier_stage.batches b
 SET original_purchase_price=b.purchase_price,
     purchase_price=ROUND(b.purchase_price*v_factor,6),
     purchase_currency='SYP',purchase_fx_rate=1
 WHERE b.purchase_id=v_purchase_id AND b.purchase_price>0;
 UPDATE pharmacy_supplier_stage.purchase_items pi
 SET purchase_price_syp=ROUND(pi.purchase_price*v_factor,6),
     purchase_currency='SYP',purchase_fx_rate=1,
     sale_price_currency=upper(COALESCE(NULLIF(x.item->>'sale_currency',''),'SYP'))
 FROM (SELECT value item FROM jsonb_array_elements(p_items)) x
 WHERE pi.purchase_id=v_purchase_id AND pi.product_id=(x.item->>'product_id')::uuid;
 UPDATE pharmacy_supplier_stage.products pr SET
  purchase_price=ROUND(pi.purchase_price*v_factor,6),
  sale_price=pi.sale_price,sale_currency=pi.sale_price_currency,
  updated_at=now()
 FROM pharmacy_supplier_stage.purchase_items pi WHERE pi.purchase_id=v_purchase_id AND pi.product_id=pr.id;
 UPDATE pharmacy_supplier_stage.purchases SET currency='SYP',fx_rate=1,total_syp=total WHERE id=v_purchase_id;
 INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'purchase_syp_currency_aware','purchase',v_purchase_id,
    jsonb_build_object('cost_discount_factor',v_factor,'sale_currency_independent',true));
 RETURN v_result||jsonb_build_object('currency','SYP','fx_rate',1);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_create_purchase_usd_v1(p_supplier_id uuid, p_new_supplier jsonb, p_invoice_number text, p_invoice_date date, p_notes text, p_items jsonb, p_payment_amount numeric, p_payment_method text, p_payment_notes text, p_discount_type text, p_discount_value numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
 v_supplier uuid:=p_supplier_id; v_supplier_name text; v_id uuid:=gen_random_uuid();
 v_invoice text; v_fx numeric; v_sum numeric:=0; v_discount numeric:=0; v_total numeric:=0;
 v_factor numeric; v_due numeric; v_paid numeric:=COALESCE(p_payment_amount,0);
 v_discount_type text:=COALESCE(NULLIF(p_discount_type,''),'none');
 v_discount_value numeric:=COALESCE(p_discount_value,0);
 v_json jsonb; v_product uuid; v_qty numeric; v_bonus numeric; v_net_usd numeric;
 v_sale_price numeric; v_sale_currency text; v_cost_syp numeric;
 v_expiry date; v_line uuid; v_batch uuid; v_batch_bonus uuid;
 v_payment jsonb:=NULL; v_count int:=0; v_p record; v_seen uuid[]:=ARRAY[]::uuid[];
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT usd_to_syp INTO v_fx FROM pharmacy_supplier_stage.pharmacy_currency_settings WHERE id=1 FOR SHARE;
 IF v_fx IS NULL OR v_fx<=1 THEN RAISE EXCEPTION 'سعر صرف الدولار غير مضبوط، لا يمكن إنشاء فاتورة'; END IF;
 IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items)=0 THEN
  RAISE EXCEPTION 'فاتورة الشراء تحتاج صنفاً واحداً على الأقل'; END IF;
 IF v_discount_type NOT IN ('none','percent','amount') OR v_discount_value<0 OR
  (v_discount_type='percent' AND v_discount_value>100) THEN RAISE EXCEPTION 'خصم الفاتورة غير صالح'; END IF;
 IF v_paid<0 OR v_paid<>ROUND(v_paid,2) OR p_payment_method NOT IN ('cash','other') THEN RAISE EXCEPTION 'طريقة الدفع أو المبلغ غير صالح'; END IF;
 IF v_supplier IS NULL THEN
   IF jsonb_typeof(p_new_supplier) IS DISTINCT FROM 'object' OR
      NULLIF(trim(p_new_supplier->>'name'),'') IS NULL THEN RAISE EXCEPTION 'اسم المورد مطلوب'; END IF;
   IF EXISTS (SELECT 1 FROM pharmacy_supplier_stage.suppliers WHERE lower(trim(name))=lower(trim(p_new_supplier->>'name'))) THEN
     RAISE EXCEPTION 'اسم المورد موجود مسبقاً، اختر المورد الحالي'; END IF;
   INSERT INTO pharmacy_supplier_stage.suppliers(name,phone,address,notes)
   VALUES(trim(p_new_supplier->>'name'),NULLIF(trim(p_new_supplier->>'phone'),''),
    NULLIF(trim(p_new_supplier->>'address'),''),NULLIF(trim(p_new_supplier->>'notes'),''))
   RETURNING id,name INTO v_supplier,v_supplier_name;
 ELSE
   SELECT name INTO v_supplier_name FROM pharmacy_supplier_stage.suppliers WHERE id=v_supplier;
   IF NOT FOUND THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
 END IF;
 -- First pass calculates USD subtotal, validates all products, amounts and expiry.
 FOR v_json IN SELECT value FROM jsonb_array_elements(p_items) LOOP
   v_product:=NULLIF(v_json->>'product_id','')::uuid;
   v_qty:=NULLIF(v_json->>'quantity','')::numeric;
   v_bonus:=COALESCE(NULLIF(v_json->>'bonus_quantity','')::numeric,0);
   v_net_usd:=NULLIF(v_json->>'purchase_price','')::numeric;
   v_sale_price:=NULLIF(v_json->>'sale_price','')::numeric;
   v_expiry:=NULLIF(v_json->>'expiry_date','')::date;
   IF v_product IS NULL OR v_qty IS NULL OR v_qty<=0 OR v_bonus<0 OR v_net_usd IS NULL
      OR v_net_usd<=0 OR v_sale_price IS NULL OR v_sale_price<=0 OR v_expiry IS NULL THEN
     RAISE EXCEPTION 'بيانات صنف الشراء غير مكتملة أو غير صالحة'; END IF;
   IF v_product=ANY(v_seen) THEN RAISE EXCEPTION 'لا يمكن تكرار الدواء في نفس فاتورة المورد'; END IF;
   v_seen:=array_append(v_seen,v_product);
   IF v_expiry<CURRENT_DATE THEN RAISE EXCEPTION 'لا يمكن شراء دفعة منتهية الصلاحية'; END IF;
   SELECT sale_currency INTO v_sale_currency FROM pharmacy_supplier_stage.products WHERE id=v_product AND COALESCE(active,true);
   IF NOT FOUND THEN RAISE EXCEPTION 'الدواء المحدد غير موجود أو غير فعّال'; END IF;
   v_sale_currency:=upper(COALESCE(NULLIF(v_json->>'sale_currency',''),v_sale_currency,'SYP'));
   IF v_sale_currency NOT IN ('SYP','USD') THEN RAISE EXCEPTION 'عملة سعر مبيع الصنف غير صالحة'; END IF;
   v_sum:=v_sum+v_qty*v_net_usd; v_count:=v_count+1;
 END LOOP;
 v_sum:=ROUND(v_sum,2);
 IF v_discount_type='percent' THEN v_discount:=ROUND(v_sum*v_discount_value/100,2);
 ELSIF v_discount_type='amount' THEN v_discount:=ROUND(v_discount_value,2); END IF;
 IF v_discount>v_sum THEN RAISE EXCEPTION 'الخصم يتجاوز إجمالي الفاتورة'; END IF;
 v_total:=ROUND(v_sum-v_discount,2); v_due:=v_total-v_paid;
 IF v_paid>v_total THEN RAISE EXCEPTION 'المدفوع أكبر من قيمة الفاتورة بالدولار'; END IF;
 v_factor:=CASE WHEN v_sum>0 THEN v_total/v_sum ELSE 1 END;
 v_invoice:=NULLIF(trim(COALESCE(p_invoice_number,'')),'');
 IF v_invoice IS NULL THEN v_invoice:='USD-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'); END IF;
 INSERT INTO pharmacy_supplier_stage.purchases(id,supplier_id,invoice_number,invoice_date,notes,status,
   currency,fx_rate,subtotal,discount_type,discount_value,discount_amount,total,total_syp)
 VALUES(v_id,v_supplier,v_invoice,COALESCE(p_invoice_date,CURRENT_DATE),NULLIF(trim(COALESCE(p_notes,'')),''),
  'received','USD',v_fx,v_sum,v_discount_type,v_discount_value,v_discount,v_total,ROUND(v_total*v_fx,2));
 FOR v_json IN SELECT value FROM jsonb_array_elements(p_items) LOOP
   v_product:=(v_json->>'product_id')::uuid;
   v_qty:=(v_json->>'quantity')::numeric;
   v_bonus:=COALESCE(NULLIF(v_json->>'bonus_quantity','')::numeric,0);
   v_net_usd:=(v_json->>'purchase_price')::numeric;
   v_sale_price:=(v_json->>'sale_price')::numeric;
   v_expiry:=(v_json->>'expiry_date')::date;
   SELECT sale_currency INTO v_sale_currency FROM pharmacy_supplier_stage.products WHERE id=v_product FOR UPDATE;
   v_sale_currency:=upper(COALESCE(NULLIF(v_json->>'sale_currency',''),v_sale_currency,'SYP'));
   -- Net paid inventory cost per item: after invoice discount, in SYP, rate frozen.
   v_cost_syp:=ROUND(v_net_usd*v_fx*v_factor,6);
   INSERT INTO pharmacy_supplier_stage.purchase_items(purchase_id,product_id,quantity,bonus_quantity,purchase_price,
      expiry_date,sale_price,sale_price_currency,purchase_currency,purchase_fx_rate,purchase_price_syp)
   VALUES(v_id,v_product,v_qty,v_bonus,v_net_usd,v_expiry,v_sale_price,v_sale_currency,'USD',v_fx,v_cost_syp)
   RETURNING id INTO v_line;
   v_batch:=gen_random_uuid();
   INSERT INTO pharmacy_supplier_stage.batches(id,product_id,batch_number,expiry_date,quantity,purchase_price,
     received_date,supplier_id,purchase_id,purchase_item_id,purchase_currency,purchase_fx_rate,original_purchase_price)
   VALUES(v_batch,v_product,'USD-'||substr(replace(v_line::text,'-',''),1,12),v_expiry,v_qty,v_cost_syp,
     COALESCE(p_invoice_date,CURRENT_DATE),v_supplier,v_id,v_line,'USD',v_fx,v_net_usd);
   UPDATE pharmacy_supplier_stage.purchase_items SET batch_id=v_batch WHERE id=v_line;
   INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
   VALUES(v_product,v_batch,'purchase',v_qty,'فاتورة دولار '||v_invoice,auth.uid());
   IF v_bonus>0 THEN
     v_batch_bonus:=gen_random_uuid();
     INSERT INTO pharmacy_supplier_stage.batches(id,product_id,batch_number,expiry_date,quantity,purchase_price,
       received_date,supplier_id,purchase_id,purchase_item_id,purchase_currency,purchase_fx_rate,original_purchase_price)
     VALUES(v_batch_bonus,v_product,'USD-'||substr(replace(v_line::text,'-',''),1,12)||'-BONUS',v_expiry,v_bonus,0,
       COALESCE(p_invoice_date,CURRENT_DATE),v_supplier,v_id,v_line,'USD',v_fx,0);
     INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
     VALUES(v_product,v_batch_bonus,'purchase_bonus',v_bonus,'بونص فاتورة دولار '||v_invoice,auth.uid());
   END IF;
   -- Existing sale prices change only when the invoice explicitly specifies sale_price.
   UPDATE pharmacy_supplier_stage.products SET purchase_price=v_cost_syp,sale_price=v_sale_price,
      sale_currency=v_sale_currency,updated_at=now() WHERE id=v_product;
 END LOOP;
 IF v_paid>0 THEN
   v_payment:=pharmacy_supplier_stage.admin_record_supplier_payment_usd_v1(v_supplier,v_paid,v_id,p_payment_method,p_payment_notes);
 ELSE
   PERFORM pharmacy_supplier_stage.admin_refresh_purchase_balance(v_id);
 END IF;
 INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'create_purchase_usd','purchase',v_id,
 jsonb_build_object('invoice_number',v_invoice,'supplier_id',v_supplier,'subtotal_usd',v_sum,
 'discount_usd',v_discount,'total_usd',v_total,'paid_usd',v_paid,'fx_rate',v_fx,'total_syp',ROUND(v_total*v_fx,2)));
 RETURN jsonb_build_object('id',v_id,'public_code',v_invoice,'supplier_id',v_supplier,
  'supplier_name',v_supplier_name,'currency','USD','fx_rate',v_fx,'total',v_total,
  'total_syp',ROUND(v_total*v_fx,2),'paid_amount',v_paid,'due_amount',v_due,
  'discount_amount',v_discount,'payment',v_payment);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_create_purchase_with_payment(p_supplier_id uuid DEFAULT NULL::uuid, p_new_supplier jsonb DEFAULT NULL::jsonb, p_invoice_number text DEFAULT NULL::text, p_invoice_date date DEFAULT CURRENT_DATE, p_notes text DEFAULT NULL::text, p_items jsonb DEFAULT '[]'::jsonb, p_payment_amount numeric DEFAULT 0, p_payment_method text DEFAULT 'cash'::text, p_payment_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  v_supplier_id uuid := p_supplier_id;
  v_supplier_name text;
  v_purchase jsonb;
  v_payment jsonb := NULL;
  v_total numeric := 0;
  v_paid numeric := greatest(coalesce(p_payment_amount,0),0);
  v_due numeric := 0;
  v_new_name text;
  v_new_phone text;
  v_new_address text;
  v_new_notes text;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;

  IF coalesce(v_paid,0) < 0 THEN
    RAISE EXCEPTION 'Invalid payment amount';
  END IF;

  IF p_payment_method NOT IN ('cash','other') THEN
    RAISE EXCEPTION 'طريقة الدفع غير صالحة';
  END IF;

  -- Create the supplier inside the same transaction when requested.
  IF v_supplier_id IS NULL THEN
    IF p_new_supplier IS NULL OR jsonb_typeof(p_new_supplier) <> 'object' THEN
      RAISE EXCEPTION 'يجب اختيار مورد أو إدخال بيانات مورد جديد';
    END IF;

    v_new_name := nullif(trim(coalesce(p_new_supplier->>'name','')), '');
    v_new_phone := nullif(trim(coalesce(p_new_supplier->>'phone','')), '');
    v_new_address := nullif(trim(coalesce(p_new_supplier->>'address','')), '');
    v_new_notes := nullif(trim(coalesce(p_new_supplier->>'notes','')), '');

    IF v_new_name IS NULL THEN
      RAISE EXCEPTION 'اسم المورد الجديد مطلوب';
    END IF;

    IF EXISTS (
      SELECT 1 FROM pharmacy_supplier_stage.suppliers
      WHERE lower(trim(name)) = lower(v_new_name)
    ) THEN
      RAISE EXCEPTION 'يوجد مورد بهذا الاسم مسبقاً. اختر المورد الموجود بدلاً من إنشاء نسخة مكررة';
    END IF;

    INSERT INTO pharmacy_supplier_stage.suppliers(name,phone,address,notes)
    VALUES(v_new_name,v_new_phone,v_new_address,v_new_notes)
    RETURNING id,name INTO v_supplier_id,v_supplier_name;

    INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
    VALUES(
      auth.uid(),'admin_create_supplier','supplier',v_supplier_id,
      jsonb_build_object('name',v_new_name,'phone',v_new_phone,'address',v_new_address,'notes',v_new_notes,'source','purchase_invoice')
    );
  ELSE
    SELECT name INTO v_supplier_name
    FROM pharmacy_supplier_stage.suppliers
    WHERE id=v_supplier_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Supplier not found';
    END IF;
  END IF;

  -- Existing purchase RPC remains the single source for purchase/batch/stock creation.
  v_purchase := pharmacy_supplier_stage.admin_create_purchase(
    v_supplier_id,
    p_invoice_number,
    coalesce(p_invoice_date,current_date),
    p_notes,
    p_items
  );

  v_total := coalesce((v_purchase->>'total')::numeric,0);

  IF v_paid > v_total THEN
    RAISE EXCEPTION 'المبلغ المدفوع أكبر من إجمالي الفاتورة: %', v_total;
  END IF;

  v_due := greatest(v_total-v_paid,0);

  IF v_paid > 0 THEN
    v_payment := pharmacy_supplier_stage.admin_record_supplier_payment(
      v_supplier_id,
      v_paid,
      (v_purchase->>'id')::uuid,
      p_payment_method,
      p_payment_notes
    );
  ELSE
    -- A zero-payment invoice must still get its true outstanding balance.
    PERFORM pharmacy_supplier_stage.admin_refresh_purchase_balance((v_purchase->>'id')::uuid);
  END IF;

  RETURN jsonb_build_object(
    'id',(v_purchase->>'id')::uuid,
    'public_code',v_purchase->>'public_code',
    'supplier_id',v_supplier_id,
    'supplier_name',v_supplier_name,
    'total',v_total,
    'paid_amount',v_paid,
    'due_amount',v_due,
    'payment_method',CASE WHEN v_paid>0 THEN p_payment_method ELSE NULL END,
    'payment',v_payment
  );
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_create_purchase_with_payment_discount(p_supplier_id uuid DEFAULT NULL::uuid, p_new_supplier jsonb DEFAULT NULL::jsonb, p_invoice_number text DEFAULT NULL::text, p_invoice_date date DEFAULT CURRENT_DATE, p_notes text DEFAULT NULL::text, p_items jsonb DEFAULT '[]'::jsonb, p_payment_amount numeric DEFAULT 0, p_payment_method text DEFAULT 'cash'::text, p_payment_notes text DEFAULT NULL::text, p_discount_type text DEFAULT 'none'::text, p_discount_value numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  v_supplier_id uuid := p_supplier_id;
  v_supplier_name text;
  v_purchase jsonb;
  v_payment jsonb := NULL;
  v_subtotal numeric := 0;
  v_discount_value numeric := GREATEST(COALESCE(p_discount_value,0),0);
  v_discount_amount numeric := 0;
  v_total numeric := 0;
  v_paid numeric := GREATEST(COALESCE(p_payment_amount,0),0);
  v_due numeric := 0;
  v_new_name text;
  v_new_phone text;
  v_new_address text;
  v_new_notes text;
  v_discount_type text := COALESCE(NULLIF(trim(p_discount_type),''),'none');
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;

  IF v_discount_type NOT IN ('none','percent','amount') THEN
    RAISE EXCEPTION 'نوع الخصم غير صالح';
  END IF;
  IF v_discount_value < 0 THEN
    RAISE EXCEPTION 'قيمة الخصم لا يمكن أن تكون سالبة';
  END IF;
  IF v_discount_type='percent' AND v_discount_value > 100 THEN
    RAISE EXCEPTION 'نسبة الخصم يجب أن تكون بين 0 و100٪';
  END IF;
  IF v_discount_type='none' THEN
    v_discount_value := 0;
  END IF;
  IF p_payment_method NOT IN ('cash','other') THEN
    RAISE EXCEPTION 'طريقة الدفع غير صالحة';
  END IF;

  IF v_supplier_id IS NULL THEN
    IF p_new_supplier IS NULL OR jsonb_typeof(p_new_supplier) <> 'object' THEN
      RAISE EXCEPTION 'يجب اختيار مورد أو إدخال بيانات مورد جديد';
    END IF;
    v_new_name := NULLIF(trim(COALESCE(p_new_supplier->>'name','')), '');
    v_new_phone := NULLIF(trim(COALESCE(p_new_supplier->>'phone','')), '');
    v_new_address := NULLIF(trim(COALESCE(p_new_supplier->>'address','')), '');
    v_new_notes := NULLIF(trim(COALESCE(p_new_supplier->>'notes','')), '');
    IF v_new_name IS NULL THEN RAISE EXCEPTION 'اسم المورد الجديد مطلوب'; END IF;
    IF EXISTS (SELECT 1 FROM pharmacy_supplier_stage.suppliers WHERE lower(trim(name))=lower(v_new_name)) THEN
      RAISE EXCEPTION 'يوجد مورد بهذا الاسم مسبقاً. اختر المورد الموجود بدلاً من إنشاء نسخة مكررة';
    END IF;
    INSERT INTO pharmacy_supplier_stage.suppliers(name,phone,address,notes)
    VALUES(v_new_name,v_new_phone,v_new_address,v_new_notes)
    RETURNING id,name INTO v_supplier_id,v_supplier_name;
    INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
    VALUES(auth.uid(),'admin_create_supplier','supplier',v_supplier_id,
      jsonb_build_object('name',v_new_name,'phone',v_new_phone,'address',v_new_address,'notes',v_new_notes,'source','purchase_invoice'));
  ELSE
    SELECT name INTO v_supplier_name FROM pharmacy_supplier_stage.suppliers WHERE id=v_supplier_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Supplier not found'; END IF;
  END IF;

  -- This remains the single source for item/batch/stock creation.
  v_purchase := pharmacy_supplier_stage.admin_create_purchase(
    v_supplier_id,
    p_invoice_number,
    COALESCE(p_invoice_date,CURRENT_DATE),
    p_notes,
    p_items
  );

  v_subtotal := ROUND(COALESCE((v_purchase->>'total')::numeric,0),2);
  IF v_discount_type='percent' THEN
    v_discount_amount := ROUND(v_subtotal * v_discount_value / 100,2);
  ELSIF v_discount_type='amount' THEN
    v_discount_amount := ROUND(v_discount_value,2);
  ELSE
    v_discount_amount := 0;
  END IF;
  IF v_discount_amount > v_subtotal THEN
    RAISE EXCEPTION 'قيمة الخصم لا يمكن أن تتجاوز إجمالي الفاتورة';
  END IF;
  v_total := ROUND(GREATEST(v_subtotal-v_discount_amount,0),2);

  UPDATE pharmacy_supplier_stage.purchases
  SET subtotal=v_subtotal,
      discount_type=v_discount_type,
      discount_value=v_discount_value,
      discount_amount=v_discount_amount,
      total=v_total
  WHERE id=(v_purchase->>'id')::uuid;

  IF v_paid > v_total THEN
    RAISE EXCEPTION 'المبلغ المدفوع أكبر من إجمالي الفاتورة بعد الخصم: %', v_total;
  END IF;
  v_due := GREATEST(v_total-v_paid,0);

  IF v_paid > 0 THEN
    v_payment := pharmacy_supplier_stage.admin_record_supplier_payment(
      v_supplier_id,
      v_paid,
      (v_purchase->>'id')::uuid,
      p_payment_method,
      p_payment_notes
    );
  ELSE
    PERFORM pharmacy_supplier_stage.admin_refresh_purchase_balance((v_purchase->>'id')::uuid);
  END IF;

  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'admin_create_purchase_discount','purchase',(v_purchase->>'id')::uuid,
    jsonb_build_object('subtotal',v_subtotal,'discount_type',v_discount_type,'discount_value',v_discount_value,'discount_amount',v_discount_amount,'total_after_discount',v_total));

  RETURN jsonb_build_object(
    'id',(v_purchase->>'id')::uuid,
    'public_code',v_purchase->>'public_code',
    'supplier_id',v_supplier_id,
    'supplier_name',v_supplier_name,
    'subtotal',v_subtotal,
    'discount_type',v_discount_type,
    'discount_value',v_discount_value,
    'discount_amount',v_discount_amount,
    'total',v_total,
    'paid_amount',v_paid,
    'due_amount',v_due,
    'payment_method',CASE WHEN v_paid>0 THEN p_payment_method ELSE NULL END,
    'payment',v_payment
  );
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_create_purchase_with_payment_discount_currency(p_supplier_id uuid DEFAULT NULL::uuid, p_new_supplier jsonb DEFAULT NULL::jsonb, p_invoice_number text DEFAULT NULL::text, p_invoice_date date DEFAULT CURRENT_DATE, p_notes text DEFAULT NULL::text, p_items jsonb DEFAULT '[]'::jsonb, p_payment_amount numeric DEFAULT 0, p_payment_method text DEFAULT 'cash'::text, p_payment_notes text DEFAULT NULL::text, p_discount_type text DEFAULT 'none'::text, p_discount_value numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_result jsonb; v_purchase_id uuid; v_item jsonb; v_currency text; v_product uuid;
BEGIN
IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
IF jsonb_typeof(p_items) <> 'array' THEN RAISE EXCEPTION 'Purchase items must be an array'; END IF;
FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
v_currency:=upper(coalesce(nullif(trim(v_item->>'sale_currency'),''),nullif(trim(v_item->>'sale_price_currency'),''),'SYP'));
IF v_currency NOT IN ('USD','SYP') THEN RAISE EXCEPTION 'Invalid sale currency: %',v_currency; END IF;
END LOOP;
v_result:=pharmacy_supplier_stage.admin_create_purchase_with_payment_discount(p_supplier_id,p_new_supplier,p_invoice_number,p_invoice_date,p_notes,p_items,p_payment_amount,p_payment_method,p_payment_notes,p_discount_type,p_discount_value);
v_purchase_id:=(v_result->>'id')::uuid;
FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
v_product:=(v_item->>'product_id')::uuid;
v_currency:=upper(coalesce(nullif(trim(v_item->>'sale_currency'),''),nullif(trim(v_item->>'sale_price_currency'),''),'SYP'));
UPDATE pharmacy_supplier_stage.purchase_items SET sale_price_currency=v_currency WHERE purchase_id=v_purchase_id AND product_id=v_product;
UPDATE pharmacy_supplier_stage.products SET sale_currency=v_currency WHERE id=v_product;
END LOOP;
RETURN v_result;
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_create_supplier(p_name text, p_phone text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS suppliers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v pharmacy_supplier_stage.suppliers;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF nullif(trim(coalesce(p_name,'')), '') IS NULL THEN RAISE EXCEPTION 'Supplier name is required'; END IF;
  INSERT INTO pharmacy_supplier_stage.suppliers(name, phone, address, notes)
  VALUES (trim(p_name), nullif(trim(coalesce(p_phone,'')),''), nullif(trim(coalesce(p_address,'')),''), nullif(trim(coalesce(p_notes,'')),''))
  RETURNING * INTO v;
  RETURN v;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_currency_accounting_report_v1(p_start timestamp with time zone, p_end timestamp with time zone, p_compare_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_compare_end timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v jsonb; v_supplier_returns numeric; v_purchase_total numeric; v_cash_balance numeric;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 v:=pharmacy_supplier_stage.admin_accounting_report(p_start,p_end,p_compare_start,p_compare_end);
 SELECT COALESCE(SUM(COALESCE(amount_syp,amount)),0) INTO v_supplier_returns
  FROM pharmacy_supplier_stage.returns WHERE return_type='supplier' AND created_at>=p_start AND created_at<p_end;
 SELECT COALESCE(SUM(COALESCE(total_syp,total)),0) INTO v_purchase_total
  FROM pharmacy_supplier_stage.purchases WHERE created_at>=p_start AND created_at<p_end;
 SELECT COALESCE(SUM(COALESCE(amount_syp,amount)),0) INTO v_cash_balance FROM pharmacy_supplier_stage.cashbox_entries;
 v:=jsonb_set(v,'{summary,supplier_returns}',to_jsonb(v_supplier_returns));
 v:=jsonb_set(v,'{summary,net_purchases}',to_jsonb(v_purchase_total-v_supplier_returns));
 v:=jsonb_set(v,'{summary,cash_balance}',to_jsonb(v_cash_balance));
 v:=jsonb_set(v,'{purchase_rows}',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'id',p.id,'created_at',p.created_at,'invoice_number',p.invoice_number,'supplier_name',s.name,
 'total',COALESCE(p.total_syp,p.total),'original_total',p.total,'currency',p.currency,
 'fx_rate',p.fx_rate,'bonus_quantity',COALESCE((SELECT SUM(pi.bonus_quantity) FROM pharmacy_supplier_stage.purchase_items pi WHERE pi.purchase_id=p.id),0)
 ) ORDER BY p.created_at DESC) FROM pharmacy_supplier_stage.purchases p LEFT JOIN pharmacy_supplier_stage.suppliers s ON s.id=p.supplier_id
 WHERE p.created_at>=p_start AND p.created_at<p_end),'[]'::jsonb)); v:=jsonb_set(v,'{cash_rows}',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'id',c.id,'created_at',c.created_at,'type',c.entry_type,
 'amount',COALESCE(c.amount_syp,c.amount),'original_amount',c.amount,
 'currency',c.currency,'fx_rate',c.fx_rate,'description',c.description
 ) ORDER BY c.created_at DESC) FROM pharmacy_supplier_stage.cashbox_entries c
 WHERE c.created_at>=p_start AND c.created_at<p_end),'[]'::jsonb));
 v:=jsonb_set(v,'{return_rows}',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'id',r.id,'created_at',r.created_at,'type',r.return_type,'product_name',p.name,
 'quantity',r.quantity,'amount',COALESCE(r.amount_syp,r.amount),
 'original_amount',r.amount,'currency',r.currency,'fx_rate',r.fx_rate,'reason',r.reason
 ) ORDER BY r.created_at DESC) FROM pharmacy_supplier_stage.returns r LEFT JOIN pharmacy_supplier_stage.products p ON p.id=r.product_id
 WHERE r.created_at>=p_start AND r.created_at<p_end),'[]'::jsonb));
 RETURN v;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_currency_backend_contract_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_rate numeric;v_writes boolean;v_reads boolean;v_columns boolean;
 v_triggers boolean;v_balances boolean;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT usd_to_syp INTO v_rate FROM pharmacy_supplier_stage.pharmacy_currency_settings WHERE id=1;
 v_writes:=
  to_regprocedure('pharmacy_supplier_stage.admin_create_purchase_usd_v1(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric)') IS NOT NULL AND
  to_regprocedure('pharmacy_supplier_stage.admin_create_purchase_syp_v1(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric)') IS NOT NULL AND
  to_regprocedure('pharmacy_supplier_stage.admin_record_supplier_payment_usd_v1(uuid,numeric,uuid,text,text)') IS NOT NULL AND
  to_regprocedure('pharmacy_supplier_stage.admin_currency_supplier_return_v2(uuid,text,jsonb,text)') IS NOT NULL AND
  to_regprocedure('pharmacy_supplier_stage.admin_currency_supplier_refund_receipt_v1(uuid,numeric,text,text)') IS NOT NULL;
 v_reads:=
  to_regprocedure('pharmacy_supplier_stage.admin_currency_purchase_list_v1()') IS NOT NULL AND
  to_regprocedure('pharmacy_supplier_stage.admin_currency_supplier_debt_list_v1()') IS NOT NULL AND
  to_regprocedure('pharmacy_supplier_stage.admin_currency_supplier_ledger_v1(uuid,text)') IS NOT NULL AND
  to_regprocedure('pharmacy_supplier_stage.admin_currency_purchase_detail_v1(uuid)') IS NOT NULL AND
  to_regprocedure('pharmacy_supplier_stage.admin_currency_return_list_v1()') IS NOT NULL AND
  to_regprocedure('pharmacy_supplier_stage.admin_currency_supplier_return_options_v1()') IS NOT NULL AND
  to_regprocedure('pharmacy_supplier_stage.admin_currency_supplier_purchase_history_v1(uuid)') IS NOT NULL AND
  to_regprocedure('pharmacy_supplier_stage.admin_currency_accounting_report_v1(timestamptz,timestamptz,timestamptz,timestamptz)') IS NOT NULL; v_columns:=
  (SELECT COUNT(*)=4 FROM information_schema.columns WHERE table_schema='pharmacy_supplier_stage' AND table_name='purchases' AND column_name IN ('currency','fx_rate','total_syp','credit_amount'))
  AND (SELECT COUNT(*)=3 FROM information_schema.columns WHERE table_schema='pharmacy_supplier_stage' AND table_name='supplier_payments' AND column_name IN ('currency','fx_rate','amount_syp'))
  AND to_regclass('pharmacy_supplier_stage.supplier_refund_receipts') IS NOT NULL;
 v_triggers:=
  EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='pharmacy_supplier_stage.supplier_payment_allocations'::regclass
    AND tgname='trg_ab_allocation_metadata_guard_v1' AND tgenabled IN ('O','A'))
  AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='pharmacy_supplier_stage.returns'::regclass
    AND tgname='trg_ab_validate_supplier_return_v1' AND tgenabled IN ('O','A'))
  AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='pharmacy_supplier_stage.returns'::regclass
    AND tgname='trg_ab_apply_supplier_return_credit_v1' AND tgenabled IN ('O','A'));
 v_balances:=
  NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.purchases p WHERE ABS(
   COALESCE(p.due_amount,0)-GREATEST(p.total-p.paid_amount-p.credit_amount,0))>0.01)
  AND NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.supplier_payment_allocations a
    JOIN pharmacy_supplier_stage.supplier_payments sp ON sp.id=a.payment_id JOIN pharmacy_supplier_stage.purchases p ON p.id=a.purchase_id
    WHERE sp.supplier_id IS DISTINCT FROM p.supplier_id OR sp.currency IS DISTINCT FROM p.currency OR a.currency IS DISTINCT FROM p.currency)
  AND NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.cashbox_entries WHERE currency='SYP' AND amount_syp IS DISTINCT FROM amount)
  AND NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.purchases WHERE currency='USD' AND (fx_rate<=1 OR total_syp IS NULL))
  AND NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.supplier_payments WHERE currency='USD' AND (fx_rate<=1 OR amount_syp IS NULL))
  AND NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.returns WHERE currency='USD' AND amount_syp IS NULL)
  AND NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.supplier_refund_receipts WHERE currency='USD' AND (fx_rate<=1 OR amount_syp IS NULL));
 RETURN jsonb_build_object('ready',v_writes AND v_reads AND v_columns AND v_triggers AND v_balances AND v_rate>1,
  'writes',v_writes,'reads',v_reads,'columns',v_columns,'guards',v_triggers,
  'balances',v_balances,'rate_valid',COALESCE(v_rate>1,false),
  'usd_supplier_returns_supported',v_writes AND v_triggers,
  'supplier_refunds_supported',v_writes AND v_columns);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_currency_history()
 RETURNS SETOF pharmacy_currency_history
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  SELECT * FROM pharmacy_supplier_stage.pharmacy_currency_history
  WHERE pharmacy_supplier_stage.is_admin()
  ORDER BY changed_at DESC LIMIT 100;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_currency_purchase_detail_v1(p_purchase_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v jsonb;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object('id',p.id,'supplier_id',p.supplier_id,'supplier_name',s.name,
  'invoice_number',p.invoice_number,'invoice_date',p.invoice_date,'subtotal',p.subtotal,
  'discount_type',p.discount_type,'discount_value',p.discount_value,'discount_amount',p.discount_amount,
  'total',p.total,'paid_amount',p.paid_amount,'credit_amount',p.credit_amount,
  'due_amount',p.due_amount,'payment_status',p.payment_status,
  'status',p.status,'notes',p.notes,'created_at',p.created_at,'currency',p.currency,'fx_rate',p.fx_rate,
  'total_syp',CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END,
  'refunded_amount',(SELECT COALESCE(SUM(sr.amount),0) FROM pharmacy_supplier_stage.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),
  'refund_due',GREATEST(p.paid_amount+p.credit_amount-p.total-
    (SELECT COALESCE(SUM(sr.amount),0) FROM pharmacy_supplier_stage.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),0),
  'bonus_quantity',(SELECT COALESCE(SUM(pi.bonus_quantity),0) FROM pharmacy_supplier_stage.purchase_items pi WHERE pi.purchase_id=p.id),
  'items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',pi.id,'product_id',pi.product_id,'product_name',pr.name,'barcode',pr.barcode,
   'active_ingredient',pr.active_ingredient,'quantity',pi.quantity,'bonus_quantity',pi.bonus_quantity,
   'purchase_price',pi.purchase_price,'purchase_price_syp',pi.purchase_price_syp,'sale_price',pi.sale_price,
   'sale_currency',pi.sale_price_currency,'expiry_date',pi.expiry_date,'batch_id',pi.batch_id))
   FROM pharmacy_supplier_stage.purchase_items pi JOIN pharmacy_supplier_stage.products pr ON pr.id=pi.product_id
   WHERE pi.purchase_id=p.id),'[]'::jsonb),
  'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',sp.id,'amount',a.amount,'currency',sp.currency,'fx_rate',sp.fx_rate,
   'payment_method',sp.payment_method,'notes',sp.notes,'created_at',sp.created_at,
   'cashbox_entry_id',sp.cashbox_entry_id))
   FROM pharmacy_supplier_stage.supplier_payment_allocations a JOIN pharmacy_supplier_stage.supplier_payments sp ON sp.id=a.payment_id
   WHERE a.purchase_id=p.id),'[]'::jsonb)) INTO v
 FROM pharmacy_supplier_stage.purchases p LEFT JOIN pharmacy_supplier_stage.suppliers s ON s.id=p.supplier_id WHERE p.id=p_purchase_id;
 RETURN v;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_currency_purchase_list_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
 'id',p.id,'supplier_id',p.supplier_id,'supplier_name',s.name,'invoice_number',p.invoice_number,
 'invoice_date',p.invoice_date,'created_at',p.created_at,'status',p.status,'notes',p.notes,
 'subtotal',p.subtotal,'discount_type',p.discount_type,'discount_value',p.discount_value,
 'discount_amount',p.discount_amount,'total',p.total,'paid_amount',p.paid_amount,'credit_amount',p.credit_amount,
 'due_amount',p.due_amount,'payment_status',p.payment_status,'item_count',
 (SELECT COUNT(*) FROM pharmacy_supplier_stage.purchase_items pi WHERE pi.purchase_id=p.id),
 'bonus_quantity',(SELECT COALESCE(SUM(bonus_quantity),0) FROM pharmacy_supplier_stage.purchase_items pi WHERE pi.purchase_id=p.id),
 'currency',p.currency,'fx_rate',p.fx_rate,'total_syp',CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END,
 'refunded_amount',(SELECT COALESCE(SUM(sr.amount),0) FROM pharmacy_supplier_stage.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),
 'refund_due',GREATEST(p.paid_amount+p.credit_amount-p.total-
    (SELECT COALESCE(SUM(sr.amount),0) FROM pharmacy_supplier_stage.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),0)
 ) ORDER BY p.created_at DESC),'[]'::jsonb)
 FROM pharmacy_supplier_stage.purchases p LEFT JOIN pharmacy_supplier_stage.suppliers s ON s.id=p.supplier_id
 WHERE pharmacy_supplier_stage.is_admin();
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_currency_return_list_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',r.id,'return_type',r.return_type,
  'product_name',p.name,'quantity',r.quantity,'amount',r.amount,'amount_syp',COALESCE(r.amount_syp,r.amount),
  'currency',r.currency,'fx_rate',r.fx_rate,'reason',r.reason,'created_at',r.created_at,
  'purchase_id',r.purchase_id,'sale_id',r.sale_id) ORDER BY r.created_at DESC),'[]'::jsonb)
 FROM (SELECT * FROM pharmacy_supplier_stage.returns ORDER BY created_at DESC LIMIT 500) r
 LEFT JOIN pharmacy_supplier_stage.products p ON p.id=r.product_id WHERE pharmacy_supplier_stage.is_admin();
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_currency_supplier_debt_list_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
 'id',x.id,'name',x.name,'phone',x.phone,'address',x.address,'currency',x.currency,
 'invoice_total',x.invoice_total,'paid_total',x.paid_total,'credit_total',x.credit_total,
 'balance',x.balance,'refund_due',x.refund_due,'invoice_count',x.invoice_count,
 'payment_count',x.payment_count,'last_payment',x.last_payment,'last_invoice',x.last_invoice
 ) ORDER BY x.name,x.currency),'[]'::jsonb)
 FROM (
 SELECT s.id,s.name,s.phone,s.address,p.currency,
 SUM(p.total) invoice_total,SUM(p.paid_amount) paid_total,SUM(p.credit_amount) credit_total,
 SUM(p.due_amount) balance,
 SUM(GREATEST(p.paid_amount+p.credit_amount-p.total-
  (SELECT COALESCE(SUM(sr.amount),0) FROM pharmacy_supplier_stage.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),0)) refund_due,
 COUNT(*) invoice_count,
 (SELECT COUNT(*) FROM pharmacy_supplier_stage.supplier_payments sp WHERE sp.supplier_id=s.id AND sp.currency=p.currency) payment_count,
 (SELECT MAX(sp.created_at) FROM pharmacy_supplier_stage.supplier_payments sp WHERE sp.supplier_id=s.id AND sp.currency=p.currency) last_payment,
 MAX(p.created_at) last_invoice
 FROM pharmacy_supplier_stage.suppliers s JOIN pharmacy_supplier_stage.purchases p ON p.supplier_id=s.id
 WHERE pharmacy_supplier_stage.is_admin() GROUP BY s.id,p.currency
 ) x;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_currency_supplier_ledger_v1(p_supplier_id uuid, p_currency text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_currency text:=upper(COALESCE(p_currency,''));v jsonb;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF v_currency NOT IN ('USD','SYP') THEN RAISE EXCEPTION 'عملة المورد غير صالحة'; END IF;
 SELECT jsonb_build_object(
  'supplier',to_jsonb(s)||jsonb_build_object('currency',v_currency),
  'summary',jsonb_build_object(
   'invoice_total',COALESCE((SELECT SUM(total) FROM pharmacy_supplier_stage.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
   'paid_total',COALESCE((SELECT SUM(paid_amount) FROM pharmacy_supplier_stage.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
   'credit_total',COALESCE((SELECT SUM(credit_amount) FROM pharmacy_supplier_stage.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
   'balance',COALESCE((SELECT SUM(due_amount) FROM pharmacy_supplier_stage.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
   'refund_due',COALESCE((SELECT SUM(GREATEST(p.paid_amount+p.credit_amount-p.total-
     (SELECT COALESCE(SUM(sr.amount),0) FROM pharmacy_supplier_stage.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),0))
     FROM pharmacy_supplier_stage.purchases p WHERE p.supplier_id=s.id AND p.currency=v_currency),0)),
  'invoices',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',p.id,'invoice_number',p.invoice_number,'invoice_date',p.invoice_date,
   'created_at',p.created_at,'total',p.total,'paid_amount',p.paid_amount,
   'credit_amount',p.credit_amount,'due_amount',p.due_amount,'payment_status',p.payment_status,
   'currency',p.currency,'fx_rate',p.fx_rate,'notes',p.notes,'total_syp',CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END,
   'refunded_amount',(SELECT COALESCE(SUM(sr.amount),0) FROM pharmacy_supplier_stage.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),
   'refund_due',GREATEST(p.paid_amount+p.credit_amount-p.total-
    (SELECT COALESCE(SUM(sr.amount),0) FROM pharmacy_supplier_stage.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),0),
   'items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'product_name',pr.name,'barcode',pr.barcode,'quantity',pi.quantity,'bonus_quantity',pi.bonus_quantity,
    'purchase_price',pi.purchase_price,'purchase_price_syp',pi.purchase_price_syp,
    'sale_price',pi.sale_price,'sale_currency',pi.sale_price_currency,
    'expiry_date',pi.expiry_date,'batch_id',pi.batch_id))
    FROM pharmacy_supplier_stage.purchase_items pi JOIN pharmacy_supplier_stage.products pr ON pr.id=pi.product_id
    WHERE pi.purchase_id=p.id),'[]'::jsonb)) ORDER BY p.created_at DESC)
    FROM pharmacy_supplier_stage.purchases p WHERE p.supplier_id=s.id AND p.currency=v_currency),'[]'::jsonb),
  'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',sp.id,'amount',sp.amount,'currency',sp.currency,'fx_rate',sp.fx_rate,'amount_syp',sp.amount_syp,
   'payment_method',sp.payment_method,'notes',sp.notes,'created_at',sp.created_at,
   'allocations',COALESCE((SELECT jsonb_agg(jsonb_build_object('purchase_id',a.purchase_id,'amount',a.amount,
    'invoice_number',p2.invoice_number)) FROM pharmacy_supplier_stage.supplier_payment_allocations a
    JOIN pharmacy_supplier_stage.purchases p2 ON p2.id=a.purchase_id WHERE a.payment_id=sp.id),'[]'::jsonb))
    ORDER BY sp.created_at DESC) FROM pharmacy_supplier_stage.supplier_payments sp
    WHERE sp.supplier_id=s.id AND sp.currency=v_currency),'[]'::jsonb),
  'credit_notes',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',r.id,'purchase_id',r.purchase_id,'invoice_number',p.invoice_number,'quantity',r.quantity,
   'amount',r.amount,'amount_syp',r.amount_syp,'currency',r.currency,'created_at',r.created_at,'reason',r.reason)
   ORDER BY r.created_at DESC) FROM pharmacy_supplier_stage.returns r JOIN pharmacy_supplier_stage.purchases p ON p.id=r.purchase_id
   WHERE r.return_type='supplier' AND p.supplier_id=s.id AND p.currency=v_currency),'[]'::jsonb),
  'refunds',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',sr.id,'purchase_id',sr.purchase_id,'amount',sr.amount,'amount_syp',sr.amount_syp,
   'currency',sr.currency,'fx_rate',sr.fx_rate,'created_at',sr.created_at,
   'payment_method',sr.payment_method,'notes',sr.notes)
   ORDER BY sr.created_at DESC) FROM pharmacy_supplier_stage.supplier_refund_receipts sr
   WHERE sr.supplier_id=s.id AND sr.currency=v_currency),'[]'::jsonb))
 INTO v FROM pharmacy_supplier_stage.suppliers s WHERE s.id=p_supplier_id;
 IF v IS NULL THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
 RETURN v;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_currency_supplier_purchase_history_v1(p_supplier_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
 'id',x.id,'invoice_number',x.invoice_number,'invoice_date',x.invoice_date,
 'total',x.total,'status',x.status,'paid_amount',x.paid_amount,'due_amount',x.due_amount,
 'payment_status',x.payment_status,'created_at',x.created_at,'item_count',x.item_count,
 'currency',x.currency,'fx_rate',x.fx_rate,'total_syp',x.total_syp
 ) ORDER BY x.created_at DESC),'[]'::jsonb)
 FROM (
 SELECT p.id,p.invoice_number,p.invoice_date,p.total,p.status,p.paid_amount,p.due_amount,
 p.payment_status,p.created_at,p.currency,p.fx_rate,
 CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END total_syp,
 COUNT(pi.id)::bigint item_count
 FROM pharmacy_supplier_stage.purchases p LEFT JOIN pharmacy_supplier_stage.purchase_items pi ON pi.purchase_id=p.id
 WHERE pharmacy_supplier_stage.is_admin() AND p.supplier_id=p_supplier_id GROUP BY p.id
 ) x;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_currency_supplier_refund_receipt_v1(p_purchase_id uuid, p_amount numeric, p_payment_method text DEFAULT 'cash'::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE inv record; v_refunded numeric;v_available numeric;v_rate numeric;v_amount_syp numeric;
 v_refund_id uuid; v_cash_id uuid;v_supplier_name text;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_amount IS NULL OR p_amount<=0 OR p_amount<>ROUND(p_amount,2) THEN
  RAISE EXCEPTION 'المبلغ المسترد يجب أن يكون موجباً وبحد أقصى منزلتين عشريتين'; END IF;
 IF p_payment_method NOT IN ('cash','other') THEN RAISE EXCEPTION 'طريقة الاسترداد غير صالحة'; END IF;
 SELECT * INTO inv FROM pharmacy_supplier_stage.purchases WHERE id=p_purchase_id FOR UPDATE;
 IF NOT FOUND OR inv.supplier_id IS NULL THEN RAISE EXCEPTION 'فاتورة المورد غير موجودة'; END IF;
 SELECT name INTO v_supplier_name FROM pharmacy_supplier_stage.suppliers WHERE id=inv.supplier_id;
 SELECT COALESCE(SUM(amount),0) INTO v_refunded FROM pharmacy_supplier_stage.supplier_refund_receipts WHERE purchase_id=p_purchase_id;
 v_available:=GREATEST(inv.paid_amount+COALESCE(inv.credit_amount,0)-inv.total-v_refunded,0);
 IF p_amount>v_available+0.000001 THEN RAISE EXCEPTION 'قيمة الاسترداد تتجاوز المبلغ المستحق من المورد: %',v_available; END IF;
 IF inv.currency='USD' THEN
  SELECT usd_to_syp INTO v_rate FROM pharmacy_supplier_stage.pharmacy_currency_settings WHERE id=1 FOR SHARE;
  IF v_rate IS NULL OR v_rate<=1 THEN RAISE EXCEPTION 'سعر صرف الدولار غير مضبوط'; END IF;
 ELSE v_rate:=1; END IF;
 v_amount_syp:=ROUND(p_amount*v_rate,2);
 INSERT INTO pharmacy_supplier_stage.supplier_refund_receipts(supplier_id,purchase_id,currency,amount,fx_rate,amount_syp,
   payment_method,notes,created_by)
 VALUES(inv.supplier_id,p_purchase_id,inv.currency,p_amount,v_rate,v_amount_syp,
   p_payment_method,NULLIF(trim(COALESCE(p_notes,'')),''),auth.uid()) RETURNING id INTO v_refund_id;
 IF p_payment_method='cash' THEN
  INSERT INTO pharmacy_supplier_stage.cashbox_entries(entry_type,amount,description,purchase_id,created_by,currency,fx_rate,amount_syp)
  VALUES('income',p_amount,'استرداد نقدي من المورد: '||v_supplier_name||' — إشعار دائن فاتورة '||
    COALESCE(inv.invoice_number,'—'),p_purchase_id,auth.uid(),inv.currency,v_rate,v_amount_syp)
  RETURNING id INTO v_cash_id;
  UPDATE pharmacy_supplier_stage.supplier_refund_receipts SET cashbox_entry_id=v_cash_id WHERE id=v_refund_id;
 END IF;
 INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'supplier_refund_receipt','purchase',p_purchase_id,
   jsonb_build_object('id',v_refund_id,'amount',p_amount,'currency',inv.currency,'fx_rate',v_rate,
   'amount_syp',v_amount_syp,'payment_method',p_payment_method,'cashbox_entry_id',v_cash_id,'notes',p_notes));
 RETURN jsonb_build_object('id',v_refund_id,'purchase_id',p_purchase_id,'supplier_id',inv.supplier_id,
    'currency',inv.currency,'amount',p_amount,'fx_rate',v_rate,'amount_syp',v_amount_syp,
    'cashbox_entry_id',v_cash_id,'refund_due',v_available-p_amount);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_currency_supplier_return_options_v1()
 RETURNS TABLE(purchase_id uuid, invoice_number text, supplier_name text, purchase_date date, purchase_item_id uuid, batch_id uuid, product_id uuid, product_name text, purchased_quantity numeric, available_quantity numeric, purchase_price numeric, expiry_date date, currency text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
 SELECT p.id,p.invoice_number,s.name,p.invoice_date,pi.id,b.id,pr.id,pr.name,
   CASE WHEN b.id=pi.batch_id THEN pi.quantity ELSE pi.bonus_quantity END,
   COALESCE(b.quantity,0),CASE WHEN b.id=pi.batch_id THEN pi.purchase_price ELSE 0 END,b.expiry_date,p.currency
 FROM pharmacy_supplier_stage.purchase_items pi JOIN pharmacy_supplier_stage.purchases p ON p.id=pi.purchase_id
 JOIN pharmacy_supplier_stage.products pr ON pr.id=pi.product_id
 LEFT JOIN pharmacy_supplier_stage.suppliers s ON s.id=p.supplier_id
 JOIN pharmacy_supplier_stage.batches b ON b.purchase_item_id=pi.id
 WHERE pharmacy_supplier_stage.is_admin() AND b.id IS NOT NULL AND COALESCE(b.quantity,0)>0
 ORDER BY p.created_at DESC NULLS LAST,pr.name;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_currency_supplier_return_v2(p_purchase_id uuid, p_mode text, p_items jsonb DEFAULT '[]'::jsonb, p_reason text DEFAULT 'مرتجع إلى المورد'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE inv record; r record;it jsonb;v_batch uuid;v_qty numeric;v_amount numeric;
 v_expected numeric;v_total numeric:=0;v_count integer:=0;v_lines jsonb:='[]'::jsonb;
 v_seen uuid[]:=ARRAY[]::uuid[];
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_purchase_id IS NULL OR p_mode NOT IN ('full','count_1','count_2','count_3','selected') THEN
  RAISE EXCEPTION 'نوع المرتجع غير صالح'; END IF;
 SELECT * INTO inv FROM pharmacy_supplier_stage.purchases WHERE id=p_purchase_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'فاتورة الشراء غير موجودة'; END IF;
 IF p_mode<>'full' AND jsonb_typeof(COALESCE(p_items,'[]'::jsonb))<>'array' THEN
  RAISE EXCEPTION 'بيانات المرتجع يجب أن تكون قائمة'; END IF;
 IF p_mode IN ('count_1','count_2','count_3') AND
   jsonb_array_length(COALESCE(p_items,'[]'::jsonb)) <> split_part(p_mode,'_',2)::int THEN
  RAISE EXCEPTION 'عدد الأصناف المحدد لا يطابق نوع المرتجع'; END IF;
 IF p_mode='selected' AND jsonb_array_length(COALESCE(p_items,'[]'::jsonb))=0 THEN
  RAISE EXCEPTION 'اختر مادة واحدة على الأقل'; END IF;
 IF p_mode='full' THEN
  FOR r IN SELECT b.id batch_id,b.product_id,pr.name product_name,b.quantity available,
    b.purchase_price,pi.purchase_price_syp,pi.quantity paid_qty,pi.bonus_quantity,b.batch_number
    FROM pharmacy_supplier_stage.purchase_items pi JOIN pharmacy_supplier_stage.batches b ON b.purchase_item_id=pi.id
    JOIN pharmacy_supplier_stage.products pr ON pr.id=pi.product_id
    WHERE pi.purchase_id=p_purchase_id AND b.quantity>0 ORDER BY b.id FOR UPDATE OF b
  LOOP
   v_qty:=r.available;
   v_expected:=CASE WHEN inv.currency='USD' THEN ROUND(v_qty*r.purchase_price/inv.fx_rate,2)
       WHEN r.purchase_price_syp IS NOT NULL THEN ROUND(v_qty*r.purchase_price,2)
       ELSE ROUND(v_qty*r.purchase_price*CASE WHEN inv.subtotal>0 THEN inv.total/inv.subtotal ELSE 1 END,2) END;
   v_amount:=LEAST(v_expected,GREATEST(inv.total-inv.credit_amount-v_total,0));
   UPDATE pharmacy_supplier_stage.batches SET quantity=quantity-v_qty WHERE id=r.batch_id;
   INSERT INTO pharmacy_supplier_stage.returns(return_type,purchase_id,product_id,batch_id,quantity,amount,amount_syp,currency,fx_rate,reason,created_by)
   VALUES('supplier',p_purchase_id,r.product_id,r.batch_id,v_qty,v_amount,
     CASE WHEN inv.currency='USD' THEN ROUND(v_amount*inv.fx_rate,2) ELSE v_amount END,
     inv.currency,inv.fx_rate,COALESCE(p_reason,'مرتجع للمورد'),auth.uid());   INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,note,created_by)
   VALUES(r.product_id,r.batch_id,'supplier_return',-v_qty,p_purchase_id,COALESCE(p_reason,'مرتجع للمورد'),auth.uid());
   v_total:=v_total+v_amount;v_count:=v_count+1;
   v_lines:=v_lines||jsonb_build_object('product_name',r.product_name,'quantity',v_qty,'amount',v_amount,'batch_id',r.batch_id);
  END LOOP;
 ELSE
  FOR it IN SELECT value FROM jsonb_array_elements(COALESCE(p_items,'[]'::jsonb)) LOOP
   v_batch:=NULLIF(it->>'batch_id','')::uuid;
   v_qty:=NULLIF(it->>'quantity','')::numeric;
   IF v_batch IS NULL OR v_qty IS NULL OR v_qty<=0 OR v_batch=ANY(v_seen) THEN
    RAISE EXCEPTION 'دفعة مرتجع مكررة أو كمية غير صالحة'; END IF;
   v_seen:=array_append(v_seen,v_batch);
   SELECT b.id batch_id,b.product_id,pr.name product_name,b.quantity available,
     b.purchase_price,pi.purchase_price_syp,pi.quantity paid_qty,pi.bonus_quantity,b.batch_number
     INTO r FROM pharmacy_supplier_stage.purchase_items pi JOIN pharmacy_supplier_stage.batches b ON b.purchase_item_id=pi.id
     JOIN pharmacy_supplier_stage.products pr ON pr.id=pi.product_id
     WHERE pi.purchase_id=p_purchase_id AND b.id=v_batch FOR UPDATE OF b;
   IF NOT FOUND THEN RAISE EXCEPTION 'دفعة المرتجع لا تتبع هذه الفاتورة'; END IF;
   IF v_qty>r.available+0.000001 THEN RAISE EXCEPTION 'الكمية تتجاوز مخزون الدفعة'; END IF;
   v_expected:=CASE WHEN inv.currency='USD' THEN ROUND(v_qty*r.purchase_price/inv.fx_rate,2)
       WHEN r.purchase_price_syp IS NOT NULL THEN ROUND(v_qty*r.purchase_price,2)
       ELSE ROUND(v_qty*r.purchase_price*CASE WHEN inv.subtotal>0 THEN inv.total/inv.subtotal ELSE 1 END,2) END;
   v_amount:=LEAST(v_expected,GREATEST(inv.total-inv.credit_amount-v_total,0));
   UPDATE pharmacy_supplier_stage.batches SET quantity=quantity-v_qty WHERE id=v_batch;
   INSERT INTO pharmacy_supplier_stage.returns(return_type,purchase_id,product_id,batch_id,quantity,amount,amount_syp,currency,fx_rate,reason,created_by)
   VALUES('supplier',p_purchase_id,r.product_id,v_batch,v_qty,v_amount,
     CASE WHEN inv.currency='USD' THEN ROUND(v_amount*inv.fx_rate,2) ELSE v_amount END,
     inv.currency,inv.fx_rate,COALESCE(p_reason,'مرتجع للمورد'),auth.uid());
   INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,note,created_by)
   VALUES(r.product_id,v_batch,'supplier_return',-v_qty,p_purchase_id,COALESCE(p_reason,'مرتجع للمورد'),auth.uid());
   v_total:=v_total+v_amount;v_count:=v_count+1;
   v_lines:=v_lines||jsonb_build_object('product_name',r.product_name,'quantity',v_qty,'amount',v_amount,'batch_id',v_batch);
  END LOOP;
 END IF;
 IF v_count=0 THEN RAISE EXCEPTION 'لا توجد دفعات متاحة للإرجاع'; END IF;
 INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'supplier_credit_note','purchase',p_purchase_id,
  jsonb_build_object('currency',inv.currency,'fx_rate',inv.fx_rate,'amount',v_total,'items',v_lines,'reason',p_reason));
 RETURN jsonb_build_object('purchase_id',p_purchase_id,'currency',inv.currency,'credit_amount',v_total,
   'items_count',v_count,'items',v_lines);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_customer_history(p_customer_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v jsonb;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object('customer',to_jsonb(c),'orders',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',o.id,'public_code',o.public_code,'status',o.status,'total',o.total,'created_at',o.created_at,'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_name',p.name,'quantity',oi.quantity,'unit_price',oi.unit_price)) FROM pharmacy_supplier_stage.order_items oi JOIN pharmacy_supplier_stage.products p ON p.id=oi.product_id WHERE oi.order_id=o.id),'[]'::jsonb)) ORDER BY o.created_at DESC) FROM pharmacy_supplier_stage.orders o WHERE o.customer_id=c.id),'[]'::jsonb)) INTO v FROM pharmacy_supplier_stage.customers c WHERE c.id=p_customer_id;
 RETURN v;
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_customer_profiles()
 RETURNS TABLE(id uuid, name text, phone text, address text, created_at timestamp with time zone, orders_count bigint, total_spent numeric, last_order_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
 SELECT c.id,c.name,c.phone,c.address,c.created_at,COUNT(DISTINCT o.id),COALESCE(SUM(o.total),0),MAX(o.created_at)
 FROM pharmacy_supplier_stage.customers c LEFT JOIN pharmacy_supplier_stage.orders o ON o.customer_id=c.id AND o.status<>'cancelled'
 WHERE pharmacy_supplier_stage.is_admin() GROUP BY c.id ORDER BY MAX(o.created_at) DESC NULLS LAST,c.created_at DESC LIMIT 500;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_customer_return(p_sale_item_id uuid, p_quantity numeric, p_reason text DEFAULT 'مرتجع من الزبون'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  v record; v_returned numeric; v_remaining numeric; v_amount numeric;
  v_gross numeric; v_factor numeric;
  v_cash_id uuid; v_tx uuid;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF COALESCE(p_quantity,0)<=0 THEN RAISE EXCEPTION 'كمية المرتجع يجب أن تكون أكبر من صفر'; END IF;

  SELECT si.id,si.sale_id,si.product_id,si.batch_id,si.quantity,si.unit_price,si.unit_cost,
         s.payment_method,s.debtor_id,s.total AS sale_total,COALESCE(s.discount,0) AS discount
  INTO v
  FROM pharmacy_supplier_stage.sale_items si JOIN pharmacy_supplier_stage.sales s ON s.id=si.sale_id
  WHERE si.id=p_sale_item_id FOR UPDATE OF si;
  IF NOT FOUND THEN RAISE EXCEPTION 'صنف البيع غير موجود'; END IF;

  SELECT COALESCE(SUM(r.quantity),0) INTO v_returned
  FROM pharmacy_supplier_stage.returns r WHERE r.return_type='customer' AND r.sale_item_id=v.id;
  v_remaining:=v.quantity-v_returned;
  IF p_quantity>v_remaining+0.000001 THEN
    RAISE EXCEPTION 'كمية المرتجع تتجاوز الكمية المتبقية القابلة للإرجاع: %',GREATEST(v_remaining,0);
  END IF;

  -- Prorate invoice discount across this sale line so a full invoice return
  -- cannot create a refund larger than the recorded invoice total.
  SELECT COALESCE(SUM(x.quantity*x.unit_price),0) INTO v_gross
  FROM pharmacy_supplier_stage.sale_items x WHERE x.sale_id=v.sale_id;
  v_factor:=CASE WHEN v_gross>0 THEN GREATEST(0,1-(v.discount/v_gross)) ELSE 1 END;
  v_amount:=ROUND(p_quantity*v.unit_price*v_factor,2);

  UPDATE pharmacy_supplier_stage.batches SET quantity=quantity+p_quantity WHERE id=v.batch_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'دفعة البيع الأصلية غير موجودة'; END IF;

  INSERT INTO pharmacy_supplier_stage.returns(return_type,sale_id,sale_item_id,product_id,batch_id,quantity,amount,reason,created_by)
  VALUES('customer',v.sale_id,v.id,v.product_id,v.batch_id,p_quantity,v_amount,COALESCE(p_reason,'مرتجع من الزبون'),auth.uid());

  INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,note,created_by)
  VALUES(v.product_id,v.batch_id,'customer_return',p_quantity,v.sale_id,COALESCE(p_reason,'مرتجع من الزبون'),auth.uid());

  IF v.payment_method='cash' THEN
    INSERT INTO pharmacy_supplier_stage.cashbox_entries(entry_type,amount,description,sale_id,created_by)
    VALUES('customer_return_refund',-abs(v_amount),'استرداد مرتجع زبون',v.sale_id,auth.uid()) RETURNING id INTO v_cash_id;
  ELSIF v.payment_method='credit' AND v.debtor_id IS NOT NULL THEN
    INSERT INTO pharmacy_supplier_stage.debtor_transactions(debtor_id,transaction_type,sale_id,amount,debit,credit,payment_method,notes,created_by)
    VALUES(v.debtor_id,'adjustment',v.sale_id,v_amount,0,v_amount,'credit','تخفيض دين بسبب مرتجع زبون',auth.uid()) RETURNING id INTO v_tx;
  END IF;

  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'customer_return','sale',v.sale_id,jsonb_build_object(
    'sale_item_id',v.id,'product_id',v.product_id,'quantity',p_quantity,'amount',v_amount,
    'payment_method',v.payment_method,'cashbox_entry_id',v_cash_id,'debtor_transaction_id',v_tx,
    'remaining_returnable',v_remaining-p_quantity,'reason',p_reason));

  RETURN jsonb_build_object('sale_id',v.sale_id,'sale_item_id',v.id,'quantity',p_quantity,'amount',v_amount,
    'remaining_returnable',v_remaining-p_quantity,'cashbox_entry_id',v_cash_id,'debtor_transaction_id',v_tx);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_dashboard_day_details(p_start timestamp with time zone, p_end timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v jsonb;f jsonb;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN RAISE EXCEPTION 'Invalid dashboard day range'; END IF;
 f:=pharmacy_supplier_stage.admin_dashboard_financial_summary(p_start,p_end);
 SELECT jsonb_build_object(
  'period',jsonb_build_object('start',p_start,'end',p_end),'summary',f,
  'sales',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'created_at',s.created_at,
   'invoice_number',s.id::text,'total',COALESCE(s.total_syp,s.total),
   'currency',s.currency,'payment_method',s.payment_method,
   'paid_amount',CASE WHEN s.currency='USD' THEN s.paid_amount*s.fx_rate ELSE s.paid_amount END,
   'due_amount',CASE WHEN s.currency='USD' THEN s.due_amount*s.fx_rate ELSE s.due_amount END,
   'debtor_name',d.name,'items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'product_name',p.name,'barcode',p.barcode,'quantity',si.quantity,
    'unit_price',si.unit_price,'base_unit_price',si.base_unit_price,
    'line_total',si.quantity*si.unit_price) ORDER BY p.name)
    FROM pharmacy_supplier_stage.sale_items si LEFT JOIN pharmacy_supplier_stage.products p ON p.id=si.product_id WHERE si.sale_id=s.id),'[]'::jsonb)
   ) ORDER BY s.created_at DESC) FROM pharmacy_supplier_stage.sales s LEFT JOIN pharmacy_supplier_stage.debtors d ON d.id=s.debtor_id
   WHERE s.created_at>=p_start AND s.created_at<p_end),'[]'::jsonb),
  'purchases',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'created_at',p.created_at,
   'invoice_number',p.invoice_number,'supplier_name',sp.name,
   'total',COALESCE(p.total_syp,p.total),'original_total',p.total,
   'paid_amount',CASE WHEN p.currency='USD' THEN ROUND(p.paid_amount*p.fx_rate,2) ELSE p.paid_amount END,
   'due_amount',CASE WHEN p.currency='USD' THEN ROUND(p.due_amount*p.fx_rate,2) ELSE p.due_amount END,
   'currency',p.currency,'fx_rate',p.fx_rate,'payment_status',p.payment_status,
   'item_count',(SELECT COUNT(*) FROM pharmacy_supplier_stage.purchase_items pi WHERE pi.purchase_id=p.id),
   'bonus_quantity',(SELECT COALESCE(SUM(pi2.bonus_quantity),0) FROM pharmacy_supplier_stage.purchase_items pi2 WHERE pi2.purchase_id=p.id))
   ORDER BY p.created_at DESC) FROM pharmacy_supplier_stage.purchases p LEFT JOIN pharmacy_supplier_stage.suppliers sp ON sp.id=p.supplier_id
   WHERE p.created_at>=p_start AND p.created_at<p_end),'[]'::jsonb),
  'cashbox',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'created_at',c.created_at,
    'type',c.entry_type,'amount',COALESCE(c.amount_syp,c.amount),'original_amount',c.amount,
    'currency',c.currency,'description',c.description) ORDER BY c.created_at DESC)
    FROM pharmacy_supplier_stage.cashbox_entries c WHERE c.created_at>=p_start AND c.created_at<p_end),'[]'::jsonb),
  'returns',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'created_at',r.created_at,
    'type',r.return_type,'product_name',pr.name,'quantity',r.quantity,
    'amount',COALESCE(r.amount_syp,r.amount),'original_amount',r.amount,'currency',r.currency,'reason',r.reason)
    ORDER BY r.created_at DESC) FROM pharmacy_supplier_stage.returns r LEFT JOIN pharmacy_supplier_stage.products pr ON pr.id=r.product_id
    WHERE r.created_at>=p_start AND r.created_at<p_end),'[]'::jsonb),
  'debtor_payments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'created_at',t.created_at,
    'debtor_name',d.name,'amount',COALESCE(t.amount_syp,t.credit),
    'payment_method',t.payment_method,'notes',t.notes) ORDER BY t.created_at DESC)
    FROM pharmacy_supplier_stage.debtor_transactions t JOIN pharmacy_supplier_stage.debtors d ON d.id=t.debtor_id
    WHERE t.transaction_type='payment' AND t.created_at>=p_start AND t.created_at<p_end),'[]'::jsonb),
  'orders',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',o.id,'created_at',o.created_at,
    'public_code',o.public_code,'customer_name',c.name,'customer_phone',c.phone,
    'status',o.status,'total',o.total) ORDER BY o.created_at DESC)
    FROM pharmacy_supplier_stage.orders o LEFT JOIN pharmacy_supplier_stage.customers c ON c.id=o.customer_id
    WHERE o.created_at>=p_start AND o.created_at<p_end),'[]'::jsonb),
  'prescriptions',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',pr.id,'created_at',pr.created_at,
    'customer_name',pr.customer_name,'customer_phone',pr.customer_phone,'status',pr.status,
    'file_name',pr.file_name) ORDER BY pr.created_at DESC)
    FROM pharmacy_supplier_stage.prescriptions pr WHERE pr.created_at>=p_start AND pr.created_at<p_end),'[]'::jsonb),
  'supplier_payments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',sp.id,'created_at',sp.created_at,
    'supplier_name',s.name,'amount',COALESCE(sp.amount_syp,sp.amount),
    'original_amount',sp.amount,'currency',sp.currency,'payment_method',sp.payment_method,
    'notes',sp.notes) ORDER BY sp.created_at DESC)
    FROM pharmacy_supplier_stage.supplier_payments sp JOIN pharmacy_supplier_stage.suppliers s ON s.id=sp.supplier_id
    WHERE sp.created_at>=p_start AND sp.created_at<p_end),'[]'::jsonb)
 ) INTO v;
 RETURN v;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_dashboard_financial_summary(p_start timestamp with time zone, p_end timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_sales numeric:=0;v_gross_cost numeric:=0;v_returns numeric:=0;
 v_return_cost numeric:=0;v_purchases numeric:=0;v_profit numeric:=0;v_net_cost numeric:=0;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN RAISE EXCEPTION 'Invalid financial period'; END IF;
 IF EXISTS(SELECT 1 FROM pharmacy_supplier_stage.cashbox_entries WHERE currency='USD' AND amount_syp IS NULL) OR
    EXISTS(SELECT 1 FROM pharmacy_supplier_stage.supplier_payments WHERE currency='USD' AND amount_syp IS NULL) OR
    EXISTS(SELECT 1 FROM pharmacy_supplier_stage.purchases WHERE currency='USD' AND total_syp IS NULL) OR
    EXISTS(SELECT 1 FROM pharmacy_supplier_stage.returns WHERE currency='USD' AND amount_syp IS NULL) THEN
  RAISE EXCEPTION 'سجلات دولار بلا تحويل بالليرة؛ التقرير المالي متوقف للحماية'; END IF;
 SELECT COALESCE(SUM(COALESCE(s.total_syp,s.total)),0) INTO v_sales
 FROM pharmacy_supplier_stage.sales s WHERE s.created_at>=p_start AND s.created_at<p_end;
 SELECT COALESCE(SUM(si.quantity*si.unit_cost),0) INTO v_gross_cost
 FROM pharmacy_supplier_stage.sale_items si JOIN pharmacy_supplier_stage.sales s ON s.id=si.sale_id
 WHERE s.created_at>=p_start AND s.created_at<p_end;
 SELECT COALESCE(SUM(COALESCE(r.amount_syp,r.amount)),0) INTO v_returns
 FROM pharmacy_supplier_stage.returns r WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end;
 SELECT COALESCE(SUM(r.quantity*si.unit_cost),0) INTO v_return_cost
 FROM pharmacy_supplier_stage.returns r JOIN pharmacy_supplier_stage.sale_items si ON si.id=r.sale_item_id
 WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end;
 SELECT COALESCE(SUM(COALESCE(p.total_syp,p.total)),0) INTO v_purchases
 FROM pharmacy_supplier_stage.purchases p WHERE p.created_at>=p_start AND p.created_at<p_end;
 v_net_cost:=v_gross_cost-v_return_cost;
 v_profit:=v_sales-v_returns-v_net_cost;
 RETURN jsonb_build_object(
  'sales',v_sales,'cost_of_goods',v_net_cost,'gross_cost_of_goods',v_gross_cost,
  'customer_returns',v_returns,'customer_return_cost',v_return_cost,
  'net_sales',v_sales-v_returns,'profit',v_profit,
  'margin',CASE WHEN (v_sales-v_returns)=0 THEN 0 ELSE ROUND(v_profit/(v_sales-v_returns)*100,2) END,
  'purchases',v_purchases,
  'invoice_count',(SELECT COUNT(*) FROM pharmacy_supplier_stage.sales WHERE created_at>=p_start AND created_at<p_end),
  'purchase_count',(SELECT COUNT(*) FROM pharmacy_supplier_stage.purchases WHERE created_at>=p_start AND created_at<p_end),
  'cash_in',COALESCE((SELECT SUM(COALESCE(amount_syp,amount)) FROM pharmacy_supplier_stage.cashbox_entries
     WHERE COALESCE(amount_syp,amount)>0 AND created_at>=p_start AND created_at<p_end),0),
  'cash_out',COALESCE((SELECT SUM(-COALESCE(amount_syp,amount)) FROM pharmacy_supplier_stage.cashbox_entries
     WHERE COALESCE(amount_syp,amount)<0 AND created_at>=p_start AND created_at<p_end),0),
  'cash_net',COALESCE((SELECT SUM(COALESCE(amount_syp,amount)) FROM pharmacy_supplier_stage.cashbox_entries
     WHERE created_at>=p_start AND created_at<p_end),0),
  'debtor_payments',COALESCE((SELECT SUM(COALESCE(amount_syp,amount))
     FROM pharmacy_supplier_stage.debtor_transactions WHERE transaction_type='payment'
     AND created_at>=p_start AND created_at<p_end),0),
  'supplier_payments',COALESCE((SELECT SUM(COALESCE(amount_syp,amount))
     FROM pharmacy_supplier_stage.supplier_payments WHERE created_at>=p_start AND created_at<p_end),0),
  'orders_count',(SELECT COUNT(*) FROM pharmacy_supplier_stage.orders WHERE created_at>=p_start AND created_at<p_end),
  'prescriptions_count',(SELECT COUNT(*) FROM pharmacy_supplier_stage.prescriptions WHERE created_at>=p_start AND created_at<p_end)
 );
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_dashboard_sales_day(p_start timestamp with time zone, p_end timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v jsonb; f jsonb;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  f:=pharmacy_supplier_stage.admin_dashboard_financial_summary(p_start,p_end);
  SELECT jsonb_build_object(
    'start',p_start,'end',p_end,'summary',f,
    'sales',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'created_at',s.created_at,'total',s.total,'payment_method',s.payment_method,'paid_amount',s.paid_amount,'due_amount',s.due_amount) ORDER BY s.created_at DESC) FROM pharmacy_supplier_stage.sales s WHERE s.created_at>=p_start AND s.created_at<p_end),'[]'::jsonb)
  ) INTO v;
  RETURN v;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_debtor_ledger(p_debtor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v jsonb;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object(
  'debtor',to_jsonb(d),
  'balance',COALESCE((SELECT SUM(debit-credit) FROM pharmacy_supplier_stage.debtor_transactions WHERE debtor_id=d.id),0),
  'transactions',COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'id',t.id,'type',t.transaction_type,'sale_id',t.sale_id,'amount',t.amount,'debit',t.debit,'credit',t.credit,
    'payment_method',t.payment_method,'notes',t.notes,'created_at',t.created_at,'sale_total',s.total,
    'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_name',p.name,'quantity',si.quantity,'unit_price',si.unit_price,'unit_cost',si.unit_cost) ORDER BY p.name) FROM pharmacy_supplier_stage.sale_items si JOIN pharmacy_supplier_stage.products p ON p.id=si.product_id WHERE si.sale_id=t.sale_id),'[]'::jsonb)
  ) ORDER BY t.created_at DESC) FROM pharmacy_supplier_stage.debtor_transactions t LEFT JOIN pharmacy_supplier_stage.sales s ON s.id=t.sale_id WHERE t.debtor_id=d.id),'[]'::jsonb)
 ) INTO v FROM pharmacy_supplier_stage.debtors d WHERE d.id=p_debtor_id;
 IF v IS NULL THEN RAISE EXCEPTION 'Debtor not found'; END IF;
 RETURN v;
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_delete_batch(p_batch_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  b pharmacy_supplier_stage.batches%rowtype;
  v_product_name text;
  v_purchase_items bigint;
  v_movements bigint;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  SELECT * INTO b FROM pharmacy_supplier_stage.batches WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  SELECT name INTO v_product_name FROM pharmacy_supplier_stage.products WHERE id=b.product_id;
  IF EXISTS(SELECT 1 FROM pharmacy_supplier_stage.sale_items WHERE batch_id=p_batch_id) THEN
    RAISE EXCEPTION 'لا يمكن حذف هذه الدفعة لأنها مرتبطة بمبيعات سابقة. للحفاظ على سجل المبيعات، عدّل الكمية بدلاً من حذفها.';
  END IF;
  SELECT count(*) INTO v_purchase_items FROM pharmacy_supplier_stage.purchase_items WHERE batch_id=p_batch_id;
  SELECT count(*) INTO v_movements FROM pharmacy_supplier_stage.stock_movements WHERE batch_id=p_batch_id;

  -- Preserve purchase invoices while removing the batch record.
  UPDATE pharmacy_supplier_stage.purchase_items SET batch_id=NULL WHERE batch_id=p_batch_id;
  -- Open inventory-count snapshots may reference this batch; detach them safely.
  UPDATE pharmacy_supplier_stage.inventory_count_items SET batch_id=NULL, product_id=COALESCE(product_id,b.product_id) WHERE batch_id=p_batch_id;
  DELETE FROM pharmacy_supplier_stage.stock_movements WHERE batch_id=p_batch_id;
  DELETE FROM pharmacy_supplier_stage.batches WHERE id=p_batch_id;

  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'admin_delete_batch','batch',p_batch_id,jsonb_build_object(
    'product_id',b.product_id,'product_name',COALESCE(v_product_name,'—'),
    'batch_number',COALESCE(b.batch_number,'—'),'quantity_before_delete',b.quantity,
    'purchase_items_detached',v_purchase_items,'stock_movements_removed',v_movements
  ));
  RETURN true;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_delete_order(p_order_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  v_code text;
  v_customer_id uuid;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;

  SELECT public_code, customer_id
  INTO v_code, v_customer_id
  FROM pharmacy_supplier_stage.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  DELETE FROM pharmacy_supplier_stage.order_items WHERE order_id = p_order_id;
  DELETE FROM pharmacy_supplier_stage.orders WHERE id = p_order_id;

  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id, action, entity_type, entity_id, details)
  VALUES (
    auth.uid(),
    'admin_delete_order',
    'order',
    p_order_id,
    jsonb_build_object('public_code', v_code, 'customer_id', v_customer_id)
  );

  RETURN true;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_delete_pharmacy_product(p_product_id uuid)
 RETURNS TABLE(deleted boolean, archived boolean, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'غير مصرح'; END IF;

  BEGIN
    DELETE FROM pharmacy_supplier_stage.products WHERE id=p_product_id;
    IF NOT FOUND THEN
      RETURN QUERY SELECT false, false, 'المنتج غير موجود';
      RETURN;
    END IF;
    RETURN QUERY SELECT true, false, 'تم حذف المنتج نهائياً';
  EXCEPTION WHEN foreign_key_violation THEN
    UPDATE pharmacy_supplier_stage.products
       SET active=false, customer_visible=false
     WHERE id=p_product_id;
    RETURN QUERY SELECT false, true, 'للمنتج سجلات مرتبطة بالمخزون أو المبيعات، لذلك تم أرشفته بدلاً من حذف السجل التاريخي';
  END;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_delete_purchase(p_purchase_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  v_supplier_id uuid;
  v_supplier_name text;
  v_invoice text;
  v_total numeric;
  v_invoice_date date;
  v_notes text;
  v_items jsonb;
  v_sold_count integer;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;

  SELECT p.supplier_id, s.name, p.invoice_number, p.total, p.invoice_date, p.notes
    INTO v_supplier_id, v_supplier_name, v_invoice, v_total, v_invoice_date, v_notes
  FROM pharmacy_supplier_stage.purchases p
  LEFT JOIN pharmacy_supplier_stage.suppliers s ON s.id=p.supplier_id
  WHERE p.id=p_purchase_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Purchase invoice not found'; END IF;

  PERFORM 1 FROM pharmacy_supplier_stage.purchases WHERE id=p_purchase_id FOR UPDATE;
  IF EXISTS (SELECT 1 FROM pharmacy_supplier_stage.purchases WHERE id=p_purchase_id AND
      (coalesce(paid_amount,0)<>0 OR coalesce(credit_amount,0)<>0))
  THEN RAISE EXCEPTION 'لا يمكن حذف فاتورة عليها دفعات أو إشعارات دائن'; END IF;
  IF EXISTS (SELECT 1 FROM pharmacy_supplier_stage.supplier_payment_allocations WHERE purchase_id=p_purchase_id)
  THEN RAISE EXCEPTION 'لا يمكن حذف فاتورة مرتبطة بتسديدات المورد'; END IF;
  IF EXISTS (SELECT 1 FROM pharmacy_supplier_stage.returns WHERE purchase_id=p_purchase_id)
  THEN RAISE EXCEPTION 'لا يمكن حذف فاتورة مرتبطة بمرتجعات'; END IF;
  IF EXISTS (SELECT 1 FROM pharmacy_supplier_stage.batches b JOIN pharmacy_supplier_stage.stock_movements sm ON sm.batch_id=b.id
      WHERE b.purchase_id=p_purchase_id AND sm.movement_type NOT IN ('purchase','purchase_bonus'))
  THEN RAISE EXCEPTION 'لا يمكن حذف فاتورة: تم سحب أو تحريك كمية من دفعاتها'; END IF;
  IF EXISTS (SELECT 1 FROM pharmacy_supplier_stage.batches b JOIN pharmacy_supplier_stage.sale_items si ON si.batch_id=b.id
      WHERE b.purchase_id=p_purchase_id)
  THEN RAISE EXCEPTION 'لا يمكن حذف فاتورة بيعت منها كميات'; END IF;
  IF EXISTS (SELECT 1 FROM pharmacy_supplier_stage.batches b WHERE b.purchase_id=p_purchase_id
      AND b.quantity IS DISTINCT FROM coalesce((
         SELECT sum(coalesce(pi.quantity,0)+coalesce(pi.bonus_quantity,0))
         FROM pharmacy_supplier_stage.purchase_items pi WHERE pi.batch_id=b.id),0))
  THEN RAISE EXCEPTION 'لا يمكن حذف فاتورة: كمية المخزون لم تعد تطابق الكمية المستلمة'; END IF;

  SELECT count(*)::integer INTO v_sold_count
  FROM pharmacy_supplier_stage.sale_items si
  JOIN pharmacy_supplier_stage.batches b ON b.id=si.batch_id
  WHERE b.purchase_id=p_purchase_id;

  IF v_sold_count > 0 THEN
    RAISE EXCEPTION 'Cannot delete this purchase invoice because one or more batches have already been sold';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'product_name',pr.name,
    'quantity',pi.quantity,
    'purchase_price',pi.purchase_price,
    'expiry_date',pi.expiry_date
  ) ORDER BY pi.id),'[]'::jsonb)
  INTO v_items
  FROM pharmacy_supplier_stage.purchase_items pi
  JOIN pharmacy_supplier_stage.products pr ON pr.id=pi.product_id
  WHERE pi.purchase_id=p_purchase_id;

  -- Remove the stock movement generated by this receipt, then its batch/items.
  DELETE FROM pharmacy_supplier_stage.stock_movements sm
  USING pharmacy_supplier_stage.batches b
  WHERE sm.batch_id=b.id AND b.purchase_id=p_purchase_id;
  DELETE FROM pharmacy_supplier_stage.purchase_items WHERE purchase_id=p_purchase_id;
  DELETE FROM pharmacy_supplier_stage.batches WHERE purchase_id=p_purchase_id;
  DELETE FROM pharmacy_supplier_stage.purchases WHERE id=p_purchase_id;

  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(
    auth.uid(),'admin_delete_purchase','purchase',p_purchase_id,
    jsonb_build_object(
      'supplier_id',v_supplier_id,
      'supplier_name',v_supplier_name,
      'invoice_number',v_invoice,
      'invoice_date',v_invoice_date,
      'notes',v_notes,
      'total',v_total,
      'items_count',jsonb_array_length(v_items),
      'items',v_items
    )
  );

  RETURN jsonb_build_object('id',p_purchase_id,'invoice_number',v_invoice,'deleted',true);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_delete_supplier(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  DELETE FROM pharmacy_supplier_stage.suppliers WHERE id=p_id;
  RETURN FOUND;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_dispose_stock(p_batch_id uuid, p_quantity numeric, p_reason text DEFAULT 'تالف/منتهي الصلاحية'::text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_product uuid; v_old numeric; v_new numeric;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_quantity<=0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;
 SELECT product_id,quantity INTO v_product,v_old FROM pharmacy_supplier_stage.batches WHERE id=p_batch_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Batch not found'; END IF;
 IF p_quantity>v_old THEN RAISE EXCEPTION 'Insufficient batch stock'; END IF;
 v_new:=v_old-p_quantity;
 UPDATE pharmacy_supplier_stage.batches SET quantity=v_new WHERE id=p_batch_id;
 INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by) VALUES(v_product,p_batch_id,'disposal',-p_quantity,p_reason,auth.uid());
 INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details) VALUES(auth.uid(),'admin_dispose_stock','batch',p_batch_id,jsonb_build_object('quantity',p_quantity,'reason',p_reason,'old_quantity',v_old,'new_quantity',v_new));
 RETURN v_new;
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_financial_integrity_check()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v jsonb;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  SELECT jsonb_build_object(
    'missing_cash_sales',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.sales s WHERE s.payment_method='cash' AND COALESCE(s.total,0)>0 AND NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.cashbox_entries c WHERE c.sale_id=s.id AND c.entry_type='sale_cash')),0),
    'missing_cash_debtor_payments',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.debtor_transactions t WHERE t.transaction_type='payment' AND t.payment_method='cash' AND t.credit>0 AND NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.cashbox_entries c WHERE c.debtor_transaction_id=t.id AND c.entry_type='debtor_payment')),0),
    'missing_cash_supplier_payments',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.supplier_payments sp WHERE sp.payment_method='cash' AND sp.amount>0 AND NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.cashbox_entries c WHERE c.supplier_payment_id=sp.id AND c.entry_type='purchase_payment')),0),
    'missing_customer_refunds',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.returns r JOIN pharmacy_supplier_stage.sales s ON s.id=r.sale_id WHERE r.return_type='customer' AND s.payment_method='cash' AND r.amount>0 AND NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.cashbox_entries c WHERE c.sale_id=r.sale_id AND c.entry_type='customer_return_refund' AND c.created_at BETWEEN r.created_at-interval '2 seconds' AND r.created_at+interval '2 seconds')),0),
    'sales_without_items',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.sales s WHERE NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.sale_items si WHERE si.sale_id=s.id)),0),
    'purchases_without_items',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.purchases p WHERE NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.purchase_items pi WHERE pi.purchase_id=p.id)),0),
    'supplier_payments_without_allocations',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.supplier_payments sp WHERE NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.supplier_payment_allocations spa WHERE spa.payment_id=sp.id)),0),
    'returns_without_stock_movement',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.returns r WHERE NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.stock_movements sm WHERE sm.product_id=r.product_id AND sm.movement_type=CASE WHEN r.return_type='customer' THEN 'customer_return' ELSE 'supplier_return' END AND sm.created_at BETWEEN r.created_at-interval '3 seconds' AND r.created_at+interval '3 seconds')),0),
    'purchase_balance_mismatches',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.purchases p WHERE ABS(COALESCE(p.paid_amount,0)-LEAST(COALESCE(p.total,0),COALESCE((SELECT SUM(spa.amount) FROM pharmacy_supplier_stage.supplier_payment_allocations spa WHERE spa.purchase_id=p.id),0)))>0.01 OR ABS(COALESCE(p.due_amount,0)-GREATEST(COALESCE(p.total,0)-COALESCE(p.paid_amount,0),0))>0.01),0),
    'cashbox_balance',COALESCE((SELECT SUM(amount) FROM pharmacy_supplier_stage.cashbox_entries),0),
    'supplier_debt',COALESCE((SELECT SUM(GREATEST(COALESCE(p.total,0)-COALESCE(p.paid_amount,0),0)) FROM pharmacy_supplier_stage.purchases p),0),
    'debtor_debt',COALESCE((SELECT SUM(debit-credit) FROM pharmacy_supplier_stage.debtor_transactions),0)
  ) INTO v;
  RETURN v;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_get_currency_settings()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE r pharmacy_supplier_stage.pharmacy_currency_settings;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  SELECT * INTO r FROM pharmacy_supplier_stage.pharmacy_currency_settings WHERE id=1;
  RETURN jsonb_build_object('usd_to_syp',r.usd_to_syp,'updated_at',r.updated_at);
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_get_inventory()
 RETURNS TABLE(batch_id uuid, product_id uuid, expiry_date date, quantity numeric, purchase_price numeric, received_date date, name text, barcode text, active_ingredient text, reorder_level numeric, sale_price numeric, product_purchase_price numeric, manufacturer text, strength text, dosage_form text, parts_per_unit numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  SELECT b.id, p.id, b.expiry_date, b.quantity, b.purchase_price, b.received_date,
         p.name, p.barcode, p.active_ingredient, p.reorder_level, p.sale_price,
         p.purchase_price, p.manufacturer, p.strength, p.dosage_form, p.parts_per_unit
  FROM pharmacy_supplier_stage.batches b
  JOIN pharmacy_supplier_stage.products p ON p.id = b.product_id
  WHERE pharmacy_supplier_stage.is_admin()
  ORDER BY b.expiry_date NULLS LAST, p.name;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_get_inventory_page_v1(p_limit integer DEFAULT 100, p_offset integer DEFAULT 0, p_query text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
declare v_total bigint;v_rows jsonb;v_q text:=nullif(trim(coalesce(p_query,'')),'');
begin
 if not pharmacy_supplier_stage.is_admin() then raise exception 'غير مصرح';end if;
 if p_limit<1 or p_limit>200 or p_offset<0 then raise exception 'Invalid pagination';end if;
 select count(*) into v_total from pharmacy_supplier_stage.batches b join pharmacy_supplier_stage.products p on p.id=b.product_id
 where v_q is null or p.name ilike '%'||v_q||'%' or p.barcode ilike '%'||v_q||'%' or p.active_ingredient ilike '%'||v_q||'%' or p.strength ilike '%'||v_q||'%' or p.dosage_form ilike '%'||v_q||'%' or exists(select 1 from pharmacy_supplier_stage.product_barcodes pb where pb.product_id=p.id and pb.barcode ilike '%'||v_q||'%');
 select coalesce(jsonb_agg(to_jsonb(z)),'[]'::jsonb) into v_rows from (
 select b.id as batch_id,p.id as product_id,b.expiry_date,b.quantity,b.purchase_price,b.received_date,p.name,p.barcode,p.active_ingredient,p.reorder_level,p.sale_price,p.purchase_price as product_purchase_price,p.manufacturer,p.strength,p.dosage_form,p.parts_per_unit
 from pharmacy_supplier_stage.batches b join pharmacy_supplier_stage.products p on p.id=b.product_id
 where v_q is null or p.name ilike '%'||v_q||'%' or p.barcode ilike '%'||v_q||'%' or p.active_ingredient ilike '%'||v_q||'%' or p.strength ilike '%'||v_q||'%' or p.dosage_form ilike '%'||v_q||'%' or exists(select 1 from pharmacy_supplier_stage.product_barcodes pb where pb.product_id=p.id and pb.barcode ilike '%'||v_q||'%')
 order by b.expiry_date nulls last,p.name,b.id limit p_limit offset p_offset) z;
 return jsonb_build_object('total',v_total,'rows',v_rows);
end;$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_get_product_barcodes(p_product_id uuid)
 RETURNS TABLE(barcode text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
begin
 if not pharmacy_supplier_stage.is_admin() then raise exception 'غير مصرح'; end if;
 return query select pb.barcode from pharmacy_supplier_stage.product_barcodes pb where pb.product_id=p_product_id order by pb.id;
end $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_get_products()
 RETURNS SETOF products
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  SELECT p.* FROM pharmacy_supplier_stage.products p
  WHERE pharmacy_supplier_stage.is_admin() AND COALESCE(p.active,true)=true
  ORDER BY p.name;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_get_products_page(p_limit integer DEFAULT 500, p_offset integer DEFAULT 0, p_customer_visible boolean DEFAULT NULL::boolean)
 RETURNS SETOF products
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  SELECT p.*
  FROM pharmacy_supplier_stage.products p
  WHERE pharmacy_supplier_stage.is_admin()
    AND COALESCE(p.active,true)=true
    AND (p_customer_visible IS NULL OR p.customer_visible=p_customer_visible)
  ORDER BY p.name, p.id
  LIMIT LEAST(GREATEST(COALESCE(p_limit,500),1),500)
  OFFSET GREATEST(COALESCE(p_offset,0),0);
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_get_purchase_detail(p_purchase_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v jsonb;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  SELECT jsonb_build_object(
    'id',p.id,'supplier_id',p.supplier_id,'supplier_name',s.name,'invoice_number',p.invoice_number,
    'invoice_date',p.invoice_date,'subtotal',COALESCE(p.subtotal,p.total),'discount_type',COALESCE(p.discount_type,'none'),
    'discount_value',COALESCE(p.discount_value,0),'discount_amount',COALESCE(p.discount_amount,0),'total',p.total,
    'paid_amount',p.paid_amount,'due_amount',p.due_amount,'payment_status',p.payment_status,
    'status',p.status,'notes',p.notes,'created_at',p.created_at,
    'bonus_quantity',COALESCE((SELECT SUM(pi2.bonus_quantity) FROM pharmacy_supplier_stage.purchase_items pi2 WHERE pi2.purchase_id=p.id),0),
    'items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',pi.id,'product_id',pi.product_id,'product_name',pr.name,'barcode',pr.barcode,
      'active_ingredient',pr.active_ingredient,'quantity',pi.quantity,'bonus_quantity',pi.bonus_quantity,
      'total_quantity',pi.quantity+pi.bonus_quantity,'purchase_price',pi.purchase_price,
      'sale_price',pi.sale_price,'expiry_date',pi.expiry_date,'batch_id',pi.batch_id
    ) ORDER BY pi.id) FROM pharmacy_supplier_stage.purchase_items pi JOIN pharmacy_supplier_stage.products pr ON pr.id=pi.product_id WHERE pi.purchase_id=p.id),'[]'::jsonb),
    'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',sp.id,'amount',sp.amount,'payment_method',sp.payment_method,'notes',sp.notes,'created_at',sp.created_at,
      'cashbox_entry_id',sp.cashbox_entry_id
    ) ORDER BY sp.created_at DESC)
    FROM pharmacy_supplier_stage.supplier_payment_allocations spa JOIN pharmacy_supplier_stage.supplier_payments sp ON sp.id=spa.payment_id
    WHERE spa.purchase_id=p.id),'[]'::jsonb)
  ) INTO v
  FROM pharmacy_supplier_stage.purchases p LEFT JOIN pharmacy_supplier_stage.suppliers s ON s.id=p.supplier_id
  WHERE p.id=p_purchase_id;
  RETURN v;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_get_purchase_detail_currency(p_purchase_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
SELECT CASE WHEN NOT pharmacy_supplier_stage.is_admin() THEN NULL ELSE
jsonb_set(d.data,'{items}',COALESCE((
SELECT jsonb_agg(item.value || jsonb_build_object('sale_price_currency',coalesce(pi.sale_price_currency,'SYP'),'sale_currency',coalesce(pi.sale_price_currency,'SYP')) ORDER BY item.ordinality)
FROM jsonb_array_elements(COALESCE(d.data->'items','[]'::jsonb)) WITH ORDINALITY item(value,ordinality)
LEFT JOIN pharmacy_supplier_stage.purchase_items pi ON pi.id=(item.value->>'id')::uuid AND pi.purchase_id=p_purchase_id
),'[]'::jsonb),true) END
FROM (SELECT pharmacy_supplier_stage.admin_get_purchase_detail(p_purchase_id) data) d
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_inventory_count_items(p_count_id uuid)
 RETURNS TABLE(id uuid, batch_id uuid, product_id uuid, product_name text, barcode text, expiry_date date, expected_quantity numeric, actual_quantity numeric, difference numeric, supplier_name text, invoice_number text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
 SELECT i.id,i.batch_id,i.product_id,pr.name,pr.barcode,
   CASE WHEN i.product_id IS NOT NULL THEN NULL ELSE b.expiry_date END,
   i.expected_quantity,i.actual_quantity,i.difference,
   CASE WHEN i.product_id IS NOT NULL THEN
     (SELECT string_agg(DISTINCT s2.name,'، ' ORDER BY s2.name)
        FROM pharmacy_supplier_stage.batches b2 LEFT JOIN pharmacy_supplier_stage.suppliers s2 ON s2.id=b2.supplier_id
       WHERE b2.product_id=i.product_id AND NULLIF(trim(COALESCE(s2.name,'')),'') IS NOT NULL)
   ELSE s.name END,
   CASE WHEN i.product_id IS NOT NULL THEN
     (SELECT string_agg(DISTINCT p2.invoice_number,'، ' ORDER BY p2.invoice_number)
        FROM pharmacy_supplier_stage.batches b2 LEFT JOIN pharmacy_supplier_stage.purchases p2 ON p2.id=b2.purchase_id
       WHERE b2.product_id=i.product_id AND NULLIF(trim(COALESCE(p2.invoice_number,'')),'') IS NOT NULL)
   ELSE p.invoice_number END
 FROM pharmacy_supplier_stage.inventory_count_items i
 LEFT JOIN pharmacy_supplier_stage.batches b ON b.id=i.batch_id
 JOIN pharmacy_supplier_stage.products pr ON pr.id=COALESCE(i.product_id,b.product_id)
 LEFT JOIN pharmacy_supplier_stage.suppliers s ON s.id=b.supplier_id
 LEFT JOIN pharmacy_supplier_stage.purchases p ON p.id=b.purchase_id
 WHERE pharmacy_supplier_stage.is_admin() AND i.count_id=p_count_id
 ORDER BY pr.name,b.expiry_date;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_inventory_count_result(p_count_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  v_count pharmacy_supplier_stage.inventory_counts%ROWTYPE;
  v_rows jsonb;
  v_mode text;
  v_total integer;
  v_matched integer;
  v_short integer;
  v_over integer;
  v_net numeric;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;

  SELECT * INTO v_count
  FROM pharmacy_supplier_stage.inventory_counts
  WHERE id=p_count_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'جرد المخزون غير موجود';
  END IF;

  IF v_count.status <> 'completed' THEN
    RAISE EXCEPTION 'نتيجة الجرد متاحة بعد اعتماد الجرد';
  END IF;

  v_mode := CASE
    WHEN EXISTS (
      SELECT 1 FROM pharmacy_supplier_stage.inventory_count_items i
      WHERE i.count_id=p_count_id AND i.product_id IS NOT NULL
    ) THEN 'single_product'
    ELSE 'full'
  END;

  WITH counted AS (
    SELECT
      COALESCE(i.product_id,b.product_id) AS product_id,
      pr.name AS product_name,
      pr.barcode,
      SUM(i.expected_quantity) AS before_quantity,
      SUM(COALESCE(i.actual_quantity,0)) AS actual_quantity,
      COUNT(*)::integer AS batch_count
    FROM pharmacy_supplier_stage.inventory_count_items i
    LEFT JOIN pharmacy_supplier_stage.batches b ON b.id=i.batch_id
    JOIN pharmacy_supplier_stage.products pr ON pr.id=COALESCE(i.product_id,b.product_id)
    WHERE i.count_id=p_count_id
    GROUP BY COALESCE(i.product_id,b.product_id),pr.name,pr.barcode
  ),
  sold AS (
    SELECT
      COALESCE(sm.product_id,b.product_id) AS product_id,
      COALESCE(SUM(-sm.quantity),0) AS sold_quantity
    FROM pharmacy_supplier_stage.stock_movements sm
    LEFT JOIN pharmacy_supplier_stage.batches b ON b.id=sm.batch_id
    WHERE sm.movement_type='sale'
      AND sm.quantity<0
      AND sm.created_at >= v_count.started_at
      AND sm.created_at <= COALESCE(v_count.completed_at,now())
    GROUP BY COALESCE(sm.product_id,b.product_id)
  ),
  normalized AS (
    SELECT
      c.product_id,
      c.product_name,
      c.barcode,
      c.before_quantity,
      COALESCE(s.sold_quantity,0) AS sold_quantity,
      GREATEST(c.before_quantity-COALESCE(s.sold_quantity,0),0) AS expected_after_sales,
      c.actual_quantity,
      c.batch_count
    FROM counted c
    LEFT JOIN sold s ON s.product_id=c.product_id
  ),
  final_rows AS (
    SELECT *,
      actual_quantity-expected_after_sales AS difference,
      CASE
        WHEN actual_quantity-expected_after_sales=0 THEN 'matched'
        WHEN actual_quantity-expected_after_sales<0 THEN 'shortage'
        ELSE 'surplus'
      END AS result
    FROM normalized
  )
  SELECT
    COALESCE(jsonb_agg(
      jsonb_build_object(
        'product_id',f.product_id,
        'product_name',f.product_name,
        'barcode',f.barcode,
        'before_quantity',f.before_quantity,
        'sold_quantity',f.sold_quantity,
        'expected_after_sales',f.expected_after_sales,
        'after_quantity',f.actual_quantity,
        'difference',f.difference,
        'result',f.result,
        'batch_count',f.batch_count
      ) ORDER BY f.product_name
    ),'[]'::jsonb),
    COUNT(*)::integer,
    COUNT(*) FILTER (WHERE f.result='matched')::integer,
    COUNT(*) FILTER (WHERE f.result='shortage')::integer,
    COUNT(*) FILTER (WHERE f.result='surplus')::integer,
    COALESCE(SUM(f.difference),0)
  INTO v_rows,v_total,v_matched,v_short,v_over,v_net
  FROM final_rows f;

  RETURN jsonb_build_object(
    'count_id',p_count_id,
    'mode',v_mode,
    'status',v_count.status,
    'started_at',v_count.started_at,
    'completed_at',v_count.completed_at,
    'notes',v_count.notes,
    'summary',jsonb_build_object(
      'total',v_total,
      'matched',v_matched,
      'shortage',v_short,
      'surplus',v_over,
      'net_difference',v_net
    ),
    'rows',v_rows
  );
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_inventory_count_sales_summary(p_count_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_start timestamptz; v_end timestamptz; v jsonb;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  SELECT started_at,COALESCE(completed_at,now()) INTO v_start,v_end FROM pharmacy_supplier_stage.inventory_counts WHERE id=p_count_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'جرد المخزون غير موجود'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'product_id',x.product_id,
    'product_name',x.product_name,
    'sold_quantity',x.sold_quantity,
    'sales_value',x.sales_value,
    'invoice_count',x.invoice_count
  ) ORDER BY x.product_name),'[]'::jsonb)
  INTO v
  FROM (
    SELECT si.product_id,p.name AS product_name,
      COALESCE(SUM(si.quantity),0) AS sold_quantity,
      COALESCE(SUM(si.quantity*si.unit_price),0) AS sales_value,
      COUNT(DISTINCT si.sale_id)::integer AS invoice_count
    FROM pharmacy_supplier_stage.sale_items si
    JOIN pharmacy_supplier_stage.products p ON p.id=si.product_id
    WHERE si.created_at>=v_start AND si.created_at<=v_end
    GROUP BY si.product_id,p.name
  ) x;
  RETURN v;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_latest_inventory_count_result()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  v_count_id uuid;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;

  SELECT id
    INTO v_count_id
  FROM pharmacy_supplier_stage.inventory_counts
  WHERE status='completed'
  ORDER BY completed_at DESC NULLS LAST, started_at DESC
  LIMIT 1;

  IF v_count_id IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN pharmacy_supplier_stage.admin_inventory_count_result(v_count_id);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_list_debtors()
 RETURNS TABLE(id uuid, name text, phone text, address text, notes text, created_at timestamp with time zone, total_debt numeric, total_paid numeric, balance numeric, last_activity timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
 SELECT d.id,d.name,d.phone,d.address,d.notes,d.created_at,
   COALESCE(SUM(t.debit),0),COALESCE(SUM(t.credit),0),COALESCE(SUM(t.debit-t.credit),0),MAX(t.created_at)
 FROM pharmacy_supplier_stage.debtors d LEFT JOIN pharmacy_supplier_stage.debtor_transactions t ON t.debtor_id=d.id
 WHERE pharmacy_supplier_stage.is_admin() GROUP BY d.id ORDER BY COALESCE(SUM(t.debit-t.credit),0) DESC,d.name;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_list_purchases()
 RETURNS TABLE(id uuid, supplier_id uuid, supplier_name text, invoice_number text, invoice_date date, total numeric, subtotal numeric, discount_type text, discount_value numeric, discount_amount numeric, status text, notes text, created_at timestamp with time zone, item_count bigint, bonus_quantity numeric, paid_amount numeric, due_amount numeric, payment_status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  SELECT p.id,p.supplier_id,s.name,p.invoice_number,p.invoice_date,p.total,
         COALESCE(p.subtotal,p.total),COALESCE(p.discount_type,'none'),COALESCE(p.discount_value,0),COALESCE(p.discount_amount,0),
         p.status,p.notes,p.created_at,COUNT(pi.id)::bigint,COALESCE(SUM(pi.bonus_quantity),0),
         p.paid_amount,p.due_amount,p.payment_status
  FROM pharmacy_supplier_stage.purchases p
  LEFT JOIN pharmacy_supplier_stage.suppliers s ON s.id=p.supplier_id
  LEFT JOIN pharmacy_supplier_stage.purchase_items pi ON pi.purchase_id=p.id
  WHERE pharmacy_supplier_stage.is_admin()
  GROUP BY p.id,s.name
  ORDER BY COALESCE(p.invoice_date,p.created_at::date) DESC,p.created_at DESC;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_list_purchases_currency_v1()
 RETURNS TABLE(id uuid, supplier_id uuid, supplier_name text, invoice_number text, invoice_date date, total numeric, subtotal numeric, discount_type text, discount_value numeric, discount_amount numeric, status text, notes text, created_at timestamp with time zone, item_count bigint, bonus_quantity numeric, paid_amount numeric, due_amount numeric, payment_status text, currency text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
 select l.id,l.supplier_id,l.supplier_name,l.invoice_number,l.invoice_date,l.total,l.subtotal,l.discount_type,l.discount_value,l.discount_amount,l.status,l.notes,l.created_at,l.item_count,l.bonus_quantity,l.paid_amount,l.due_amount,l.payment_status,coalesce(p.currency,'SYP')::text
 from pharmacy_supplier_stage.admin_list_purchases() l
 join pharmacy_supplier_stage.purchases p on p.id=l.id
 where pharmacy_supplier_stage.is_admin()
 order by coalesce(l.invoice_date,l.created_at::date) desc,l.created_at desc
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_list_sale_items(p_start timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(id uuid, sale_id uuid, product_id uuid, product_name text, quantity numeric, unit_price numeric, unit_cost numeric, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 RETURN QUERY
 SELECT si.id,si.sale_id,si.product_id,p.name,
        GREATEST(si.quantity-COALESCE(rr.returned_qty,0),0) AS quantity,
        si.unit_price,si.unit_cost,si.created_at
 FROM pharmacy_supplier_stage.sale_items si
 LEFT JOIN pharmacy_supplier_stage.products p ON p.id=si.product_id
 LEFT JOIN (
   SELECT r0.sale_item_id,SUM(r0.quantity) AS returned_qty
   FROM pharmacy_supplier_stage.returns r0 WHERE r0.return_type='customer'
   GROUP BY sale_item_id
 ) rr ON rr.sale_item_id=si.id
 WHERE (p_start IS NULL OR si.created_at>=p_start)
   AND GREATEST(si.quantity-COALESCE(rr.returned_qty,0),0)>0
 ORDER BY si.created_at DESC LIMIT 5000;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_list_sales(p_start timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(id uuid, customer_id uuid, subtotal numeric, discount numeric, total numeric, created_at timestamp with time zone, created_by uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  RETURN QUERY
  SELECT s.id,s.customer_id,s.subtotal,s.discount,s.total,s.created_at,s.created_by
  FROM pharmacy_supplier_stage.sales s
  WHERE p_start IS NULL OR s.created_at >= p_start
  ORDER BY s.created_at DESC
  LIMIT 1000;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_list_suppliers()
 RETURNS TABLE(id uuid, name text, phone text, address text, notes text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;
  RETURN QUERY
  SELECT s.id, s.name, s.phone, s.address, s.notes, s.created_at
  FROM pharmacy_supplier_stage.suppliers s
  ORDER BY s.name ASC, s.created_at DESC;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_pos_stock_unavailable_reason(p_product_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
declare v_name text; v_valid numeric; v_expired numeric; v_all numeric; v_last date;
begin
 if not pharmacy_supplier_stage.is_admin() then raise exception 'غير مصرح'; end if;
 select name into v_name from pharmacy_supplier_stage.products where id=p_product_id;
 if not found then return 'المنتج غير موجود في دليل الصيدلية.'; end if;
 select coalesce(sum(case when quantity>0 and (expiry_date is null or expiry_date>=current_date) then quantity else 0 end),0),
 coalesce(sum(case when quantity>0 and expiry_date<current_date then quantity else 0 end),0),
 coalesce(sum(case when quantity>0 then quantity else 0 end),0),
 max(case when quantity>0 and expiry_date<current_date then expiry_date end)
 into v_valid,v_expired,v_all,v_last from pharmacy_supplier_stage.batches where product_id=p_product_id;
 if v_valid>0 then return format('المنتج %s لديه رصيد صالح (%s)، حدّث البحث وحاول مجدداً.',v_name,v_valid); end if;
 if v_expired>0 then return format('المنتج %s موجود في المخزون بكمية %s، لكن جميع القطع المتوفرة منتهية الصلاحية (آخر صلاحية: %s). لا يمكن بيعها. تحقق من تاريخ الصلاحية الفعلي للدفعة.',v_name,v_expired,v_last); end if;
 return format('المنتج %s موجود في دليل المنتجات لكن لا توجد له دفعات بكمية صالحة للبيع.',v_name);
end $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_product_batch_trace(p_product_id uuid)
 RETURNS TABLE(id uuid, expiry_date date, quantity numeric, purchase_price numeric, received_date date, supplier_name text, invoice_number text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  SELECT b.id, b.expiry_date, b.quantity, b.purchase_price, b.received_date,
         s.name AS supplier_name, p.invoice_number
  FROM pharmacy_supplier_stage.batches b
  LEFT JOIN pharmacy_supplier_stage.suppliers s ON s.id=b.supplier_id
  LEFT JOIN pharmacy_supplier_stage.purchases p ON p.id=b.purchase_id
  WHERE pharmacy_supplier_stage.is_admin() AND b.product_id=p_product_id
  ORDER BY b.expiry_date ASC NULLS LAST, b.received_date ASC NULLS LAST;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_product_catalog(p_query text DEFAULT NULL::text, p_manufacturer text DEFAULT NULL::text, p_dosage_form text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_customer_visible boolean DEFAULT NULL::boolean, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0, p_sort text DEFAULT 'name'::text, p_desc boolean DEFAULT false)
 RETURNS TABLE(id uuid, name text, barcode text, active_ingredient text, strength text, dosage_form text, manufacturer text, category text, unit text, reorder_level numeric, purchase_price numeric, sale_price numeric, parts_per_unit numeric, customer_visible boolean, active boolean, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  WITH filtered AS (
    SELECT p.*
    FROM pharmacy_supplier_stage.products p
    WHERE pharmacy_supplier_stage.is_admin()
      AND COALESCE(p.active,true)=true
      AND (p_customer_visible IS NULL OR p.customer_visible=p_customer_visible)
      AND (
        NULLIF(trim(COALESCE(p_query,'')),'') IS NULL
        OR EXISTS (SELECT 1 FROM pharmacy_supplier_stage.product_barcodes pb WHERE pb.product_id=p.id AND pb.barcode=trim(p_query)) OR p.name ILIKE '%' || trim(p_query) || '%'
        OR COALESCE(p.barcode,'') ILIKE '%' || trim(p_query) || '%'
        OR COALESCE(p.active_ingredient,'') ILIKE '%' || trim(p_query) || '%'
        OR COALESCE(p.strength,'') ILIKE '%' || trim(p_query) || '%'
        OR COALESCE(p.manufacturer,'') ILIKE '%' || trim(p_query) || '%'
        OR COALESCE(p.dosage_form,'') ILIKE '%' || trim(p_query) || '%'
      )
      AND (NULLIF(trim(COALESCE(p_manufacturer,'')),'') IS NULL OR COALESCE(p.manufacturer,'')=trim(p_manufacturer))
      AND (NULLIF(trim(COALESCE(p_dosage_form,'')),'') IS NULL OR COALESCE(p.dosage_form,'')=trim(p_dosage_form))
      AND (NULLIF(trim(COALESCE(p_category,'')),'') IS NULL OR COALESCE(p.category,'')=trim(p_category))
  )
  SELECT
    f.id,f.name,f.barcode,f.active_ingredient,f.strength,f.dosage_form,f.manufacturer,
    f.category,f.unit,f.reorder_level,f.purchase_price,f.sale_price,f.parts_per_unit,
    f.customer_visible,f.active,COUNT(*) OVER() AS total_count
  FROM filtered f
  ORDER BY
    CASE WHEN p_sort='name' AND NOT p_desc THEN lower(COALESCE(f.name,'')) END ASC,
    CASE WHEN p_sort='name' AND p_desc THEN lower(COALESCE(f.name,'')) END DESC,
    CASE WHEN p_sort='manufacturer' AND NOT p_desc THEN lower(COALESCE(f.manufacturer,'')) END ASC,
    CASE WHEN p_sort='manufacturer' AND p_desc THEN lower(COALESCE(f.manufacturer,'')) END DESC,
    CASE WHEN p_sort='dosage_form' AND NOT p_desc THEN lower(COALESCE(f.dosage_form,'')) END ASC,
    CASE WHEN p_sort='dosage_form' AND p_desc THEN lower(COALESCE(f.dosage_form,'')) END DESC,
    CASE WHEN p_sort='active_ingredient' AND NOT p_desc THEN lower(COALESCE(f.active_ingredient,'')) END ASC,
    CASE WHEN p_sort='active_ingredient' AND p_desc THEN lower(COALESCE(f.active_ingredient,'')) END DESC,
    CASE WHEN p_sort='category' AND NOT p_desc THEN lower(COALESCE(f.category,'')) END ASC,
    CASE WHEN p_sort='category' AND p_desc THEN lower(COALESCE(f.category,'')) END DESC,
    CASE WHEN p_sort='sale_price' AND NOT p_desc THEN f.sale_price END ASC,
    CASE WHEN p_sort='sale_price' AND p_desc THEN f.sale_price END DESC,
    CASE WHEN p_sort='purchase_price' AND NOT p_desc THEN f.purchase_price END ASC,
    CASE WHEN p_sort='purchase_price' AND p_desc THEN f.purchase_price END DESC,
    f.id
  LIMIT GREATEST(1,LEAST(COALESCE(p_limit,100),200))
  OFFSET GREATEST(COALESCE(p_offset,0),0);
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_product_catalog_currency(p_query text DEFAULT NULL::text, p_manufacturer text DEFAULT NULL::text, p_dosage_form text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_customer_visible boolean DEFAULT NULL::boolean, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0, p_sort text DEFAULT 'name'::text, p_desc boolean DEFAULT false)
 RETURNS TABLE(id uuid, name text, barcode text, active_ingredient text, strength text, dosage_form text, manufacturer text, category text, unit text, reorder_level numeric, purchase_price numeric, sale_price numeric, parts_per_unit numeric, customer_visible boolean, active boolean, total_count bigint, sale_currency text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
SELECT c.id,c.name,c.barcode,c.active_ingredient,c.strength,c.dosage_form,c.manufacturer,c.category,c.unit,c.reorder_level,c.purchase_price,c.sale_price,c.parts_per_unit,c.customer_visible,c.active,c.total_count,p.sale_currency
FROM pharmacy_supplier_stage.admin_product_catalog(p_query,p_manufacturer,p_dosage_form,p_category,p_customer_visible,p_limit,p_offset,p_sort,p_desc) c JOIN pharmacy_supplier_stage.products p ON p.id=c.id WHERE pharmacy_supplier_stage.is_admin()
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_product_catalog_currency_v2(p_query text DEFAULT NULL::text, p_manufacturer text DEFAULT NULL::text, p_dosage_form text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_customer_visible boolean DEFAULT NULL::boolean, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0, p_sort text DEFAULT 'name'::text, p_desc boolean DEFAULT false)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage'
AS $function$
 SELECT to_jsonb(c) || jsonb_build_object('sale_currency',COALESCE(p.sale_currency,'SYP'))
 FROM pharmacy_supplier_stage.admin_product_catalog(p_query,p_manufacturer,p_dosage_form,p_category,p_customer_visible,p_limit,p_offset,p_sort,p_desc) c
 JOIN pharmacy_supplier_stage.products p ON p.id=c.id WHERE pharmacy_supplier_stage.is_admin()
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_product_search_key_for_barcode(p_barcode text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
declare v_key text;
begin
 if not pharmacy_supplier_stage.is_admin() then raise exception 'غير مصرح'; end if;
 select coalesce(nullif(p.barcode,''),p.name) into v_key from pharmacy_supplier_stage.product_barcodes pb join pharmacy_supplier_stage.products p on p.id=pb.product_id where pb.barcode=btrim(coalesce(p_barcode,'')) limit 1;
 return v_key;
end $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_products_count()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  SELECT COUNT(*)::bigint
  FROM pharmacy_supplier_stage.products p
  WHERE pharmacy_supplier_stage.is_admin()
    AND COALESCE(p.active,true)=true;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_record_cashbox_count(p_actual_amount numeric, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  v_expected numeric;
  v_difference numeric;
  v_id uuid;
  v_at timestamptz;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_actual_amount IS NULL OR p_actual_amount < 0 THEN
    RAISE EXCEPTION 'قيمة النقد الفعلي يجب أن تكون صفراً أو أكثر';
  END IF;

  -- Snapshot the ledger at count time; do not create an adjustment entry.
  SELECT COALESCE(SUM(amount), 0) INTO v_expected FROM pharmacy_supplier_stage.cashbox_entries;
  v_difference := p_actual_amount - v_expected;

  INSERT INTO pharmacy_supplier_stage.cashbox_counts(expected_balance, actual_amount, difference, note, counted_by)
  VALUES (v_expected, p_actual_amount, v_difference, NULLIF(trim(COALESCE(p_note, '')), ''), auth.uid())
  RETURNING id, counted_at INTO v_id, v_at;

  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id, action, entity_type, entity_id, details)
  VALUES (auth.uid(), 'cashbox_count', 'cashbox', v_id,
    jsonb_build_object('expected_balance', v_expected, 'actual_amount', p_actual_amount,
      'difference', v_difference, 'note', p_note, 'counted_at', v_at));

  RETURN jsonb_build_object('id', v_id, 'expected_balance', v_expected,
    'actual_amount', p_actual_amount, 'difference', v_difference, 'counted_at', v_at);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_record_debtor_payment(p_debtor_id uuid, p_amount numeric, p_notes text DEFAULT NULL::text, p_payment_method text DEFAULT 'cash'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  v_balance numeric;
  v_tx uuid;
  v_name text;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'مبلغ الدفعة يجب أن يكون أكبر من صفر';
  END IF;
  IF p_payment_method NOT IN ('cash','other') THEN
    RAISE EXCEPTION 'طريقة الدفع غير صالحة';
  END IF;

  -- The existing receivables ledger is SYP-denominated. Prevent mixed currencies
  -- from silently entering a single debtor balance until full USD debtor migration.
  IF EXISTS (
    SELECT 1 FROM pharmacy_supplier_stage.debtor_transactions t
    WHERE t.debtor_id=p_debtor_id AND t.currency <> 'SYP'
  ) THEN
    RAISE EXCEPTION 'لا يمكن قبض دين متعدد العملات عبر دالة تحصيل الليرة';
  END IF;

  SELECT d.name,
         COALESCE((SELECT SUM(t.debit-t.credit)
                   FROM pharmacy_supplier_stage.debtor_transactions t
                   WHERE t.debtor_id=d.id),0)
    INTO v_name,v_balance
  FROM pharmacy_supplier_stage.debtors d
  WHERE d.id=p_debtor_id
  FOR UPDATE OF d;
  IF NOT FOUND THEN RAISE EXCEPTION 'المتدين غير موجود'; END IF;
  IF p_amount > v_balance THEN
    RAISE EXCEPTION 'الدفعة أكبر من الدين الحالي';
  END IF;

  INSERT INTO pharmacy_supplier_stage.debtor_transactions
    (debtor_id,transaction_type,amount,debit,credit,payment_method,notes,
     created_by,currency,fx_rate,amount_syp)
  VALUES
    (p_debtor_id,'payment',p_amount,0,p_amount,p_payment_method,p_notes,
     auth.uid(),'SYP',1,p_amount)
  RETURNING id INTO v_tx;

  IF p_payment_method='cash' THEN
    INSERT INTO pharmacy_supplier_stage.cashbox_entries
      (entry_type,amount,description,debtor_transaction_id,created_by,
       currency,fx_rate,amount_syp)
    VALUES
      ('debtor_payment',p_amount,'تحصيل دفعة من المتدين: '||v_name,v_tx,
       auth.uid(),'SYP',1,p_amount);
  END IF;

  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'debtor_payment','debtor',p_debtor_id,
         jsonb_build_object('name',v_name,'amount',p_amount,'currency','SYP',
                            'payment_method',p_payment_method,'notes',p_notes,
                            'previous_balance',v_balance,'new_balance',v_balance-p_amount));

  RETURN jsonb_build_object('transaction_id',v_tx,
                            'previous_balance',v_balance,
                            'new_balance',v_balance-p_amount,
                            'currency','SYP');
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_record_supplier_payment(p_supplier_id uuid, p_amount numeric, p_purchase_id uuid DEFAULT NULL::uuid, p_payment_method text DEFAULT 'cash'::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  v_payment_id uuid := gen_random_uuid();
  v_cash_id uuid;
  v_remaining numeric := p_amount;
  v_invoice_due numeric;
  v_alloc numeric;
  v_previous_debt numeric;
  v_new_debt numeric;
  v_supplier_name text;
  r record;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'مبلغ دفعة المورد يجب أن يكون موجباً'; END IF;
  IF p_payment_method NOT IN ('cash','other') THEN RAISE EXCEPTION 'طريقة الدفع غير صالحة'; END IF;
  SELECT name INTO v_supplier_name FROM pharmacy_supplier_stage.suppliers WHERE id=p_supplier_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
  SELECT COALESCE(SUM(GREATEST(due_amount,0)),0)
    INTO v_previous_debt FROM pharmacy_supplier_stage.purchases
    WHERE supplier_id=p_supplier_id AND currency='SYP';
  IF p_amount>v_previous_debt+0.0000001 THEN
    RAISE EXCEPTION 'الدفعة بالليرة تتجاوز رصيد المورد المستحق بالليرة';
  END IF;
  IF p_purchase_id IS NOT NULL THEN
    SELECT GREATEST(due_amount,0) INTO v_invoice_due
      FROM pharmacy_supplier_stage.purchases WHERE id=p_purchase_id AND supplier_id=p_supplier_id
      AND currency='SYP' FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'الفاتورة غير موجودة لهذا المورد أو عملتها ليست الليرة السورية';
    END IF;
    IF v_invoice_due<=0 THEN RAISE EXCEPTION 'هذه الفاتورة مسددة بالكامل'; END IF;
    IF p_amount>v_invoice_due+0.0000001 THEN
      RAISE EXCEPTION 'الدفعة أكبر من المتبقي بالليرة: %',v_invoice_due;
    END IF;
  END IF;
  INSERT INTO pharmacy_supplier_stage.supplier_payments
   (id,supplier_id,amount,payment_method,notes,created_by,currency,fx_rate,amount_syp)
   VALUES (v_payment_id,p_supplier_id,p_amount,p_payment_method,
     NULLIF(trim(COALESCE(p_notes,'')),''),auth.uid(),'SYP',1,p_amount);
  IF p_purchase_id IS NOT NULL THEN
    INSERT INTO pharmacy_supplier_stage.supplier_payment_allocations
      (payment_id,purchase_id,amount,currency,fx_rate,amount_syp)
    VALUES (v_payment_id,p_purchase_id,p_amount,'SYP',1,p_amount);
    v_remaining:=0;
  ELSE
    FOR r IN SELECT id,GREATEST(due_amount,0) AS due
     FROM pharmacy_supplier_stage.purchases
     WHERE supplier_id=p_supplier_id AND currency='SYP'
       AND GREATEST(due_amount,0)>0
     ORDER BY COALESCE(invoice_date,created_at::date),created_at,id FOR UPDATE
    LOOP
      EXIT WHEN v_remaining<=0;
      v_alloc:=LEAST(v_remaining,r.due);
      INSERT INTO pharmacy_supplier_stage.supplier_payment_allocations
        (payment_id,purchase_id,amount,currency,fx_rate,amount_syp)
      VALUES (v_payment_id,r.id,v_alloc,'SYP',1,v_alloc);
      v_remaining:=v_remaining-v_alloc;
    END LOOP;
    IF v_remaining>0.0000001 THEN
      RAISE EXCEPTION 'الدفعة تتجاوز الرصيد المتاح بالليرة';
    END IF;
  END IF;
  FOR r IN SELECT DISTINCT purchase_id FROM pharmacy_supplier_stage.supplier_payment_allocations
           WHERE payment_id=v_payment_id LOOP
    PERFORM pharmacy_supplier_stage.admin_refresh_purchase_balance(r.purchase_id);
  END LOOP;
  IF p_payment_method='cash' THEN
    INSERT INTO pharmacy_supplier_stage.cashbox_entries
      (entry_type,amount,description,purchase_id,supplier_payment_id,created_by,
       currency,fx_rate,amount_syp)
    VALUES ('purchase_payment',-p_amount,
      'دفع للمورد بالليرة: '||v_supplier_name||
       CASE WHEN p_purchase_id IS NULL THEN ' — توزيع على الفواتير المفتوحة'
         ELSE ' — فاتورة '||COALESCE((SELECT invoice_number FROM pharmacy_supplier_stage.purchases
           WHERE id=p_purchase_id),'—') END,
      p_purchase_id,v_payment_id,auth.uid(),'SYP',1,-p_amount)
    RETURNING id INTO v_cash_id;
    UPDATE pharmacy_supplier_stage.supplier_payments SET cashbox_entry_id=v_cash_id WHERE id=v_payment_id;
  END IF;
  SELECT COALESCE(SUM(GREATEST(due_amount,0)),0)
    INTO v_new_debt FROM pharmacy_supplier_stage.purchases
    WHERE supplier_id=p_supplier_id AND currency='SYP';
  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'supplier_payment','supplier',p_supplier_id,
    jsonb_build_object('supplier_name',v_supplier_name,'amount',p_amount,
      'currency','SYP','payment_method',p_payment_method,'purchase_id',p_purchase_id,
      'previous_debt',v_previous_debt,'new_debt',v_new_debt,
      'cashbox_entry_id',v_cash_id,'notes',p_notes));
  RETURN jsonb_build_object('payment_id',v_payment_id,'amount',p_amount,
    'currency','SYP','previous_debt',v_previous_debt,'new_debt',v_new_debt,
    'cashbox_entry_id',v_cash_id);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_record_supplier_payment_usd_v1(p_supplier_id uuid, p_amount numeric, p_purchase_id uuid DEFAULT NULL::uuid, p_payment_method text DEFAULT 'cash'::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_rate numeric; v_name text; v_id uuid:=gen_random_uuid(); v_cash_id uuid;
        v_left numeric:=p_amount; v_part numeric; v_debt numeric;
        v_before numeric; v_after numeric; r record;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'مبلغ الدفعة بالدولار يجب أن يكون موجباً'; END IF;
 IF p_payment_method NOT IN ('cash','other') THEN RAISE EXCEPTION 'طريقة الدفع غير صالحة'; END IF;
 SELECT name INTO v_name FROM pharmacy_supplier_stage.suppliers WHERE id=p_supplier_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
 SELECT usd_to_syp INTO v_rate FROM pharmacy_supplier_stage.pharmacy_currency_settings WHERE id=1 FOR SHARE;
 IF v_rate IS NULL OR v_rate<=1 THEN RAISE EXCEPTION 'حدد سعر صرف معتمد قبل دفع الدولار'; END IF;
 SELECT COALESCE(SUM(GREATEST(due_amount,0)),0) INTO v_before
   FROM pharmacy_supplier_stage.purchases WHERE supplier_id=p_supplier_id AND currency='USD';
 IF p_amount>v_before+0.0000001 THEN RAISE EXCEPTION 'الدفعة تتجاوز رصيد الدولار المستحق على المورد'; END IF;
 IF p_purchase_id IS NOT NULL THEN
   SELECT COALESCE(due_amount,0) INTO v_debt FROM pharmacy_supplier_stage.purchases
    WHERE id=p_purchase_id AND supplier_id=p_supplier_id AND currency='USD' FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'فاتورة الدولار المحددة غير موجودة عند هذا المورد'; END IF;
   IF p_amount>v_debt+0.0000001 THEN RAISE EXCEPTION 'الدفعة أكبر من المتبقي بالدولار'; END IF;
 END IF;
 INSERT INTO pharmacy_supplier_stage.supplier_payments(id,supplier_id,amount,payment_method,notes,created_by,currency,fx_rate,amount_syp)
 VALUES(v_id,p_supplier_id,p_amount,p_payment_method,NULLIF(trim(COALESCE(p_notes,'')),''),auth.uid(),'USD',v_rate,ROUND(p_amount*v_rate,2));
 IF p_purchase_id IS NOT NULL THEN
   INSERT INTO pharmacy_supplier_stage.supplier_payment_allocations(payment_id,purchase_id,amount,currency,fx_rate,amount_syp)
   VALUES(v_id,p_purchase_id,p_amount,'USD',v_rate,ROUND(p_amount*v_rate,2));
 ELSE
   FOR r IN SELECT id,GREATEST(due_amount,0) AS due FROM pharmacy_supplier_stage.purchases
    WHERE supplier_id=p_supplier_id AND currency='USD' AND GREATEST(due_amount,0)>0
    ORDER BY COALESCE(invoice_date,created_at::date),created_at,id FOR UPDATE
   LOOP
    EXIT WHEN v_left<=0;
    v_part:=LEAST(v_left,r.due);
    INSERT INTO pharmacy_supplier_stage.supplier_payment_allocations(payment_id,purchase_id,amount,currency,fx_rate,amount_syp)
    VALUES(v_id,r.id,v_part,'USD',v_rate,ROUND(v_part*v_rate,2));
    v_left:=v_left-v_part;
   END LOOP;
   IF v_left>0.0000001 THEN RAISE EXCEPTION 'لا توجد فواتير دولار تكفي لتوزيع الدفعة'; END IF;
 END IF;
 FOR r IN SELECT DISTINCT purchase_id FROM pharmacy_supplier_stage.supplier_payment_allocations WHERE payment_id=v_id LOOP
   PERFORM pharmacy_supplier_stage.admin_refresh_purchase_balance(r.purchase_id);
 END LOOP;
 IF p_payment_method='cash' THEN
  INSERT INTO pharmacy_supplier_stage.cashbox_entries(entry_type,amount,description,purchase_id,supplier_payment_id,created_by,currency,fx_rate,amount_syp)
  VALUES('purchase_payment',-p_amount,'دفع للمورد بالدولار: '||v_name,p_purchase_id,v_id,auth.uid(),'USD',v_rate,-ROUND(p_amount*v_rate,2))
  RETURNING id INTO v_cash_id;
  UPDATE pharmacy_supplier_stage.supplier_payments SET cashbox_entry_id=v_cash_id WHERE id=v_id; END IF;
 SELECT COALESCE(SUM(GREATEST(due_amount,0)),0) INTO v_after
 FROM pharmacy_supplier_stage.purchases WHERE supplier_id=p_supplier_id AND currency='USD';
 INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'supplier_payment_usd','supplier',p_supplier_id,
 jsonb_build_object('payment_id',v_id,'amount_usd',p_amount,'amount_syp',ROUND(p_amount*v_rate,2),
 'fx_rate',v_rate,'before_usd',v_before,'after_usd',v_after,'purchase_id',p_purchase_id));
 RETURN jsonb_build_object('payment_id',v_id,'currency','USD','amount',p_amount,'fx_rate',v_rate,
 'amount_syp',ROUND(p_amount*v_rate,2),'previous_debt_usd',v_before,'new_debt_usd',v_after,'cashbox_entry_id',v_cash_id);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_refresh_purchase_balance(p_purchase_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_total numeric;v_credit numeric;v_paid numeric;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT total,credit_amount INTO v_total,v_credit FROM pharmacy_supplier_stage.purchases WHERE id=p_purchase_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'فاتورة الشراء غير موجودة'; END IF;
 SELECT COALESCE(SUM(amount),0) INTO v_paid FROM pharmacy_supplier_stage.supplier_payment_allocations WHERE purchase_id=p_purchase_id;
 IF v_paid>v_total+0.000001 THEN RAISE EXCEPTION 'دفعات الفاتورة تتجاوز قيمتها'; END IF;
 UPDATE pharmacy_supplier_stage.purchases SET
  paid_amount=v_paid,
  due_amount=GREATEST(v_total-v_paid-v_credit,0),
  payment_status=CASE WHEN v_paid+v_credit>=v_total-0.000001 THEN 'paid'
    WHEN v_paid>0 OR v_credit>0 THEN 'partial' ELSE 'unpaid' END
 WHERE id=p_purchase_id;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_reorder_recommendations()
 RETURNS TABLE(product_id uuid, product_name text, barcode text, current_stock numeric, reorder_level numeric, suggested_quantity numeric, estimated_cost numeric, suggested_supplier text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
 SELECT pr.id,pr.name,pr.barcode,COALESCE(SUM(b.quantity),0),COALESCE(pr.reorder_level,0),
        GREATEST(COALESCE(pr.reorder_level,0)*2-COALESCE(SUM(b.quantity),0),1),
        GREATEST(COALESCE(pr.reorder_level,0)*2-COALESCE(SUM(b.quantity),0),1)*COALESCE(pr.purchase_price,0),
        (SELECT s.name FROM pharmacy_supplier_stage.batches b2 LEFT JOIN pharmacy_supplier_stage.suppliers s ON s.id=b2.supplier_id WHERE b2.product_id=pr.id AND s.id IS NOT NULL ORDER BY b2.received_date DESC NULLS LAST,b2.created_at DESC LIMIT 1)
 FROM pharmacy_supplier_stage.products pr LEFT JOIN pharmacy_supplier_stage.batches b ON b.product_id=pr.id AND b.quantity>0
 WHERE pharmacy_supplier_stage.is_admin() GROUP BY pr.id,pr.name,pr.barcode,pr.reorder_level,pr.purchase_price
 HAVING COALESCE(SUM(b.quantity),0)<=COALESCE(pr.reorder_level,0)
 ORDER BY COALESCE(SUM(b.quantity),0) ASC,pr.name;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_repair_supplier_invoice_balances()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  r record;
  v_count integer:=0;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  FOR r IN
    SELECT p.id,COALESCE(SUM(spa.amount),0) AS allocated
    FROM pharmacy_supplier_stage.purchases p
    LEFT JOIN pharmacy_supplier_stage.supplier_payment_allocations spa ON spa.purchase_id=p.id
    GROUP BY p.id
  LOOP
    IF EXISTS(SELECT 1 FROM pharmacy_supplier_stage.supplier_payment_allocations WHERE purchase_id=r.id) THEN
      UPDATE pharmacy_supplier_stage.purchases
      SET paid_amount=LEAST(GREATEST(r.allocated,0),GREATEST(COALESCE(total,0),0)),
          due_amount=GREATEST(COALESCE(total,0)-GREATEST(r.allocated,0),0),
          payment_status=CASE
            WHEN r.allocated>=COALESCE(total,0) AND COALESCE(total,0)>0 THEN 'paid'
            WHEN r.allocated>0 THEN 'partial'
            ELSE 'unpaid'
          END
      WHERE id=r.id;
      v_count:=v_count+1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('repaired_invoices',v_count);
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_resolve_product_barcode(p_barcode text)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
declare v_id uuid; v_code text:=btrim(coalesce(p_barcode,''));
begin
 if not pharmacy_supplier_stage.is_admin() then raise exception 'غير مصرح'; end if;
 select id into v_id from pharmacy_supplier_stage.products where barcode=v_code limit 1;
 if v_id is null then select product_id into v_id from pharmacy_supplier_stage.product_barcodes where barcode=v_code; end if;
 return v_id;
end $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_restore_pharmacy_product(p_product_id uuid)
 RETURNS products
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$ declare v pharmacy_supplier_stage.products; begin if not pharmacy_supplier_stage.is_admin() then raise exception 'غير مصرح'; end if; update pharmacy_supplier_stage.products set active=true,updated_at=now() where id=p_product_id and active=false returning * into v; if not found then raise exception 'المنتج غير موجود ضمن الأرشيف'; end if; insert into pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details) values(auth.uid(),'restore_pharmacy_product','product',p_product_id,jsonb_build_object('restored',true)); return v; end; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_return_list()
 RETURNS TABLE(id uuid, return_type text, product_name text, quantity numeric, amount numeric, reason text, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
 SELECT r.id,r.return_type,p.name,r.quantity,r.amount,r.reason,r.created_at
 FROM pharmacy_supplier_stage.returns r LEFT JOIN pharmacy_supplier_stage.products p ON p.id=r.product_id
 WHERE pharmacy_supplier_stage.is_admin() ORDER BY r.created_at DESC LIMIT 500;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_save_pharmacy_product(p_product_id uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS products
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  v pharmacy_supplier_stage.products;
  v_name text; v_barcode text; v_ai text; v_strength text; v_dosage text; v_manufacturer text; v_category text; v_unit text;
  v_reorder numeric; v_purchase numeric; v_sale numeric; v_parts numeric; v_visible boolean; v_currency text;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'غير مصرح'; END IF;
  v_name := NULLIF(trim(COALESCE(p_payload->>'name','')), '');
  IF v_name IS NULL THEN RAISE EXCEPTION 'اسم المنتج مطلوب'; END IF;
  v_barcode := NULLIF(trim(COALESCE(p_payload->>'barcode','')), '');
  v_ai := NULLIF(trim(COALESCE(p_payload->>'active_ingredient','')), '');
  v_strength := NULLIF(trim(COALESCE(p_payload->>'strength','')), '');
  v_dosage := NULLIF(trim(COALESCE(p_payload->>'dosage_form','')), '');
  v_manufacturer := NULLIF(trim(COALESCE(p_payload->>'manufacturer','')), '');
  v_category := NULLIF(trim(COALESCE(p_payload->>'category','')), '');
  v_unit := COALESCE(NULLIF(trim(COALESCE(p_payload->>'unit','')), ''), 'piece');
  v_reorder := GREATEST(0, COALESCE(NULLIF(p_payload->>'reorder_level','')::numeric,1));
  v_purchase := GREATEST(0, COALESCE(NULLIF(p_payload->>'purchase_price','')::numeric,0));
  v_sale := GREATEST(0, COALESCE(NULLIF(p_payload->>'sale_price','')::numeric,0));
  v_parts := GREATEST(1, COALESCE(NULLIF(p_payload->>'parts_per_unit','')::numeric,1));
  v_visible := COALESCE((p_payload->>'customer_visible')::boolean,true);
  v_currency := upper(COALESCE(NULLIF(trim(p_payload->>'sale_currency'),''),'SYP'));
  IF v_currency NOT IN ('SYP','USD') THEN RAISE EXCEPTION 'عملة سعر المبيع غير صحيحة'; END IF;

  IF p_product_id IS NULL THEN
    INSERT INTO pharmacy_supplier_stage.products(name,barcode,active_ingredient,strength,dosage_form,manufacturer,category,unit,reorder_level,purchase_price,sale_price,parts_per_unit,customer_visible,active,sale_currency)
    VALUES(v_name,v_barcode,v_ai,v_strength,v_dosage,v_manufacturer,v_category,v_unit,v_reorder,v_purchase,v_sale,v_parts,v_visible,true,v_currency)
    RETURNING * INTO v;
  ELSE
    UPDATE pharmacy_supplier_stage.products SET name=v_name,barcode=v_barcode,active_ingredient=v_ai,strength=v_strength,dosage_form=v_dosage,manufacturer=v_manufacturer,category=v_category,unit=v_unit,reorder_level=v_reorder,purchase_price=v_purchase,sale_price=v_sale,parts_per_unit=v_parts,customer_visible=v_visible,sale_currency=v_currency
    WHERE id=p_product_id RETURNING * INTO v;
    IF NOT FOUND THEN RAISE EXCEPTION 'المنتج غير موجود'; END IF;
  END IF;
  RETURN v;
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_save_product_with_barcodes(p_product_id uuid, p_payload jsonb, p_barcodes text[])
 RETURNS products
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
declare v pharmacy_supplier_stage.products; v_code text; v_primary text:=nullif(btrim(coalesce(p_payload->>'barcode','')),'');
begin
 if not pharmacy_supplier_stage.is_admin() then raise exception 'غير مصرح'; end if;
 if v_primary is not null and exists(select 1 from pharmacy_supplier_stage.product_barcodes where barcode=v_primary and (p_product_id is null or product_id<>p_product_id)) then raise exception 'الباركود الأساسي مستخدم كإضافي'; end if;
 if v_primary is not null and v_primary=any(coalesce(p_barcodes,array[]::text[])) then raise exception 'الباركود الأساسي مكرر'; end if;
 v:=pharmacy_supplier_stage.admin_save_pharmacy_product(p_product_id,p_payload);
 perform pharmacy_supplier_stage.admin_set_product_barcodes(v.id,p_barcodes);
 return v;
end $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_search_debtors(p_query text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, name text, phone text, balance numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
 SELECT d.id,d.name,d.phone,COALESCE(SUM(t.debit-t.credit),0)
 FROM pharmacy_supplier_stage.debtors d LEFT JOIN pharmacy_supplier_stage.debtor_transactions t ON t.debtor_id=d.id
 WHERE pharmacy_supplier_stage.is_admin() AND (NULLIF(trim(COALESCE(p_query,'')),'') IS NULL OR (d.name||' '||COALESCE(d.phone,'')) ILIKE '%'||trim(p_query)||'%')
 GROUP BY d.id ORDER BY d.name LIMIT 30;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_search_inventory_products(p_query text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, name text, barcode text, active_ingredient text, stock numeric, total_received numeric, total_sold numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  SELECT
    p.id,
    p.name,
    p.barcode,
    p.active_ingredient,
    COALESCE((SELECT SUM(b.quantity) FROM pharmacy_supplier_stage.batches b WHERE b.product_id=p.id),0),
    COALESCE((SELECT SUM(sm.quantity) FROM pharmacy_supplier_stage.stock_movements sm WHERE sm.product_id=p.id AND sm.movement_type='purchase' AND sm.quantity>0),0),
    COALESCE((SELECT SUM(-sm.quantity) FROM pharmacy_supplier_stage.stock_movements sm WHERE sm.product_id=p.id AND sm.movement_type='sale' AND sm.quantity<0),0)
  FROM pharmacy_supplier_stage.products p
  WHERE pharmacy_supplier_stage.is_admin()
    AND (
      NULLIF(trim(COALESCE(p_query,'')),'') IS NULL
      OR EXISTS (SELECT 1 FROM pharmacy_supplier_stage.product_barcodes pb WHERE pb.product_id=p.id AND pb.barcode=trim(p_query)) OR p.name ILIKE '%'||trim(p_query)||'%'
      OR COALESCE(p.active_ingredient,'') ILIKE '%'||trim(p_query)||'%'
      OR COALESCE(p.barcode,'')=trim(p_query)
    )
  ORDER BY
    CASE
      WHEN COALESCE(p.barcode,'')=trim(COALESCE(p_query,'')) THEN 0
      WHEN lower(p.name)=lower(trim(COALESCE(p_query,''))) THEN 1
      WHEN lower(p.name) LIKE lower(trim(COALESCE(p_query,'')))||'%' THEN 2
      ELSE 3
    END,
    p.name
  LIMIT 30;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_search_pos_products(p_query text, p_limit integer DEFAULT 30)
 RETURNS TABLE(id uuid, name text, barcode text, active_ingredient text, strength text, dosage_form text, unit text, sale_price numeric, purchase_price numeric, parts_per_unit numeric, stock numeric, expiry_date date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  WITH q AS (SELECT trim(COALESCE(p_query,'')) AS t)
  SELECT p.id,p.name,p.barcode,p.active_ingredient,p.strength,p.dosage_form,p.unit,
         p.sale_price,p.purchase_price,p.parts_per_unit,
         COALESCE(SUM(CASE WHEN b.quantity>0 AND (b.expiry_date IS NULL OR b.expiry_date>=current_date) THEN b.quantity ELSE 0 END),0) AS stock,
         MIN(CASE WHEN b.quantity>0 AND (b.expiry_date IS NULL OR b.expiry_date>=current_date) THEN b.expiry_date END) AS expiry_date
  FROM pharmacy_supplier_stage.products p CROSS JOIN q
  LEFT JOIN pharmacy_supplier_stage.batches b ON b.product_id=p.id
  WHERE pharmacy_supplier_stage.is_admin() AND COALESCE(p.active,true)=true
    AND q.t<>''
    AND (
      p.barcode=q.t OR p.barcode ILIKE q.t||'%' OR
      p.name ILIKE '%'||q.t||'%' OR
      COALESCE(p.active_ingredient,'') ILIKE '%'||q.t||'%'
    )
  GROUP BY p.id,q.t
  ORDER BY
    CASE WHEN p.barcode=q.t THEN 0
         WHEN lower(p.name)=lower(q.t) THEN 1
         WHEN lower(COALESCE(p.active_ingredient,''))=lower(q.t) THEN 2
         WHEN lower(p.name) LIKE lower(q.t)||'%' THEN 3
         WHEN lower(COALESCE(p.active_ingredient,'')) LIKE lower(q.t)||'%' THEN 4
         ELSE 5 END,
    MIN(CASE WHEN b.quantity>0 AND (b.expiry_date IS NULL OR b.expiry_date>=current_date) THEN b.expiry_date END) NULLS LAST,
    p.name
  LIMIT GREATEST(1,LEAST(COALESCE(p_limit,30),100));
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_search_pos_products_currency(p_query text, p_limit integer DEFAULT 30)
 RETURNS TABLE(id uuid, name text, barcode text, active_ingredient text, strength text, dosage_form text, unit text, sale_price numeric, purchase_price numeric, parts_per_unit numeric, stock numeric, expiry_date date, sale_currency text, current_fx_rate numeric, sale_price_syp numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  SELECT p.id,p.name,p.barcode,p.active_ingredient,p.strength,p.dosage_form,p.unit,p.sale_price,p.purchase_price,p.parts_per_unit,
    COALESCE(SUM(CASE WHEN b.quantity>0 AND (b.expiry_date IS NULL OR b.expiry_date>=CURRENT_DATE) THEN b.quantity ELSE 0 END),0),
    MIN(CASE WHEN b.quantity>0 AND (b.expiry_date IS NULL OR b.expiry_date>=CURRENT_DATE) THEN b.expiry_date END),
    p.sale_currency,fx.usd_to_syp,
    CASE WHEN p.sale_currency='USD' THEN p.sale_price*fx.usd_to_syp ELSE p.sale_price END
  FROM pharmacy_supplier_stage.products p CROSS JOIN pharmacy_supplier_stage.pharmacy_currency_settings fx
  LEFT JOIN pharmacy_supplier_stage.batches b ON b.product_id=p.id
  WHERE pharmacy_supplier_stage.is_admin() AND (COALESCE(p.barcode,'') ILIKE p_query||'%' OR EXISTS (SELECT 1 FROM pharmacy_supplier_stage.product_barcodes pb WHERE pb.product_id=p.id AND pb.barcode=trim(p_query)) OR COALESCE(p.name,'') ILIKE '%'||p_query||'%' OR COALESCE(p.active_ingredient,'') ILIKE '%'||p_query||'%')
  GROUP BY p.id,fx.usd_to_syp
  ORDER BY CASE WHEN p.barcode=p_query THEN 0 WHEN lower(COALESCE(p.name,''))=lower(p_query) THEN 1 WHEN lower(COALESCE(p.name,'')) LIKE lower(p_query)||'%' THEN 2 WHEN COALESCE(p.active_ingredient,'') ILIKE '%'||p_query||'%' THEN 3 ELSE 4 END,
    MIN(CASE WHEN b.quantity>0 AND (b.expiry_date IS NULL OR b.expiry_date>=CURRENT_DATE) THEN b.expiry_date END) NULLS LAST,p.name
  LIMIT GREATEST(1,LEAST(COALESCE(p_limit,30),100));
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_search_purchase_products(p_query text DEFAULT NULL::text, p_limit integer DEFAULT 40)
 RETURNS TABLE(id uuid, name text, barcode text, active_ingredient text, strength text, dosage_form text, manufacturer text, category text, unit text, purchase_price numeric, sale_price numeric, parts_per_unit numeric, reorder_level numeric, active boolean, customer_visible boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  SELECT
    p.id,p.name,p.barcode,p.active_ingredient,p.strength,p.dosage_form,
    p.manufacturer,p.category,p.unit,p.purchase_price,p.sale_price,
    p.parts_per_unit,p.reorder_level,p.active,p.customer_visible
  FROM pharmacy_supplier_stage.products p
  WHERE pharmacy_supplier_stage.is_admin()
    AND COALESCE(p.active,true)=true
    AND (
      NULLIF(trim(COALESCE(p_query,'')),'') IS NULL
      OR p.barcode = trim(p_query)
      OR EXISTS (SELECT 1 FROM pharmacy_supplier_stage.product_barcodes pb WHERE pb.product_id=p.id AND pb.barcode=trim(p_query)) OR p.name ILIKE '%' || trim(p_query) || '%'
      OR COALESCE(p.active_ingredient,'') ILIKE '%' || trim(p_query) || '%'
      OR COALESCE(p.strength,'') ILIKE '%' || trim(p_query) || '%'
      OR COALESCE(p.manufacturer,'') ILIKE '%' || trim(p_query) || '%'
    )
  ORDER BY
    CASE WHEN p.barcode = trim(COALESCE(p_query,'')) THEN 0 ELSE 1 END,
    CASE WHEN lower(p.name)=lower(trim(COALESCE(p_query,''))) THEN 0 ELSE 1 END,
    p.name,p.id
  LIMIT GREATEST(1,LEAST(COALESCE(p_limit,40),100));
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_search_purchase_products_currency(p_query text DEFAULT NULL::text, p_limit integer DEFAULT 40)
 RETURNS TABLE(id uuid, name text, barcode text, active_ingredient text, strength text, dosage_form text, manufacturer text, category text, unit text, purchase_price numeric, sale_price numeric, parts_per_unit numeric, reorder_level numeric, active boolean, customer_visible boolean, sale_currency text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
SELECT c.id,c.name,c.barcode,c.active_ingredient,c.strength,c.dosage_form,c.manufacturer,c.category,c.unit,c.purchase_price,c.sale_price,c.parts_per_unit,c.reorder_level,c.active,c.customer_visible,p.sale_currency FROM pharmacy_supplier_stage.admin_search_purchase_products(p_query,p_limit) c JOIN pharmacy_supplier_stage.products p ON p.id=c.id WHERE pharmacy_supplier_stage.is_admin()
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_search_purchase_products_currency_v2(p_query text DEFAULT NULL::text, p_limit integer DEFAULT 40)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage'
AS $function$
 SELECT to_jsonb(s) || jsonb_build_object('sale_currency',COALESCE(p.sale_currency,'SYP'))
 FROM pharmacy_supplier_stage.admin_search_purchase_products(p_query,p_limit) s
 JOIN pharmacy_supplier_stage.products p ON p.id=s.id WHERE pharmacy_supplier_stage.is_admin()
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_set_inventory_count_actual(p_item_id uuid, p_actual numeric, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_actual<0 THEN RAISE EXCEPTION 'Actual quantity cannot be negative'; END IF;
 UPDATE pharmacy_supplier_stage.inventory_count_items SET actual_quantity=p_actual,notes=NULLIF(trim(COALESCE(p_notes,'')),'') WHERE id=p_item_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Count item not found'; END IF;
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_set_product_barcodes(p_product_id uuid, p_barcodes text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
declare v_code text; v_primary text;
begin
 if not pharmacy_supplier_stage.is_admin() then raise exception 'غير مصرح'; end if;
 select barcode into v_primary from pharmacy_supplier_stage.products where id=p_product_id for update;
 if not found then raise exception 'المنتج غير موجود'; end if;
 if cardinality(coalesce(p_barcodes,array[]::text[]))>30 then raise exception 'الحد الأقصى 30 باركود'; end if;
 if exists(select 1 from unnest(coalesce(p_barcodes,array[]::text[])) c where c is null or c<>btrim(c) or c='') then raise exception 'باركود غير صالح'; end if;
 if exists(select 1 from unnest(coalesce(p_barcodes,array[]::text[])) c group by c having count(*)>1) then raise exception 'باركود مكرر'; end if;
 for v_code in select c from unnest(coalesce(p_barcodes,array[]::text[])) c loop
  if v_code=coalesce(v_primary,'') or exists(select 1 from pharmacy_supplier_stage.products where barcode=v_code) then raise exception 'الباركود موجود مسبقاً: %',v_code; end if;
  if exists(select 1 from pharmacy_supplier_stage.product_barcodes where barcode=v_code and product_id<>p_product_id) then raise exception 'الباركود مرتبط بمنتج آخر: %',v_code; end if;
 end loop;
 delete from pharmacy_supplier_stage.product_barcodes where product_id=p_product_id and not(barcode=any(coalesce(p_barcodes,array[]::text[])));
 insert into pharmacy_supplier_stage.product_barcodes(product_id,barcode)
 select p_product_id,c from unnest(coalesce(p_barcodes,array[]::text[])) c
 on conflict(barcode) do nothing;
end $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_set_product_visibility(p_product_id uuid, p_visible boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;
  UPDATE pharmacy_supplier_stage.products
  SET customer_visible = COALESCE(p_visible, false), updated_at = now()
  WHERE id = p_product_id;
  RETURN FOUND;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_set_usd_to_syp_rate(p_rate numeric, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_rate IS NULL OR p_rate <= 0 THEN RAISE EXCEPTION 'سعر الصرف يجب أن يكون أكبر من صفر'; END IF;
  UPDATE pharmacy_supplier_stage.pharmacy_currency_settings
  SET usd_to_syp=p_rate, updated_at=now(), updated_by=auth.uid()
  WHERE id=1;
  INSERT INTO pharmacy_supplier_stage.pharmacy_currency_history(usd_to_syp,changed_by,note)
  VALUES(p_rate,auth.uid(),NULLIF(trim(COALESCE(p_note,'')),''));
  RETURN jsonb_build_object('usd_to_syp',p_rate,'updated_at',now());
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_smart_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v jsonb;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object(
  'today_sales',COALESCE((SELECT SUM(total) FROM pharmacy_supplier_stage.sales WHERE created_at>=current_date),0),
  'today_profit',COALESCE((SELECT SUM((unit_price-unit_cost)*quantity) FROM pharmacy_supplier_stage.sale_items WHERE created_at>=current_date),0),
  'low_stock',COALESCE((SELECT COUNT(*) FROM (SELECT pr.id,COALESCE(SUM(b.quantity),0) q,COALESCE(pr.reorder_level,0) r FROM pharmacy_supplier_stage.products pr LEFT JOIN pharmacy_supplier_stage.batches b ON b.product_id=pr.id GROUP BY pr.id,pr.reorder_level HAVING COALESCE(SUM(b.quantity),0)<=COALESCE(pr.reorder_level,0)) x),0),
  'expired',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.batches WHERE expiry_date<current_date AND quantity>0),0),
  'expiring_30',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.batches WHERE expiry_date>=current_date AND expiry_date<=current_date+30 AND quantity>0),0),
  'dead_stock',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.products pr WHERE NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.sale_items si WHERE si.product_id=pr.id AND si.created_at>=now()-interval '90 days') AND EXISTS(SELECT 1 FROM pharmacy_supplier_stage.batches b WHERE b.product_id=pr.id AND b.quantity>0)),0),
  'today_orders',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.orders WHERE created_at>=current_date),0),
  'new_prescriptions',COALESCE((SELECT COUNT(*) FROM pharmacy_supplier_stage.prescriptions WHERE status IN ('new','pending','review') ),0)
 ) INTO v;
 RETURN v;
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_start_inventory_count(p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_id uuid;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 INSERT INTO pharmacy_supplier_stage.inventory_counts(created_by,notes) VALUES(auth.uid(),NULLIF(trim(COALESCE(p_notes,'')),'')) RETURNING id INTO v_id;
 INSERT INTO pharmacy_supplier_stage.inventory_count_items(count_id,batch_id,expected_quantity)
 SELECT v_id,b.id,b.quantity FROM pharmacy_supplier_stage.batches b WHERE b.quantity>0;
 RETURN v_id;
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_start_product_inventory_count(p_product_id uuid, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_id uuid; v_stock numeric;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_product_id IS NULL OR NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.products WHERE id=p_product_id) THEN RAISE EXCEPTION 'المنتج غير موجود'; END IF;
 SELECT COALESCE(SUM(quantity),0) INTO v_stock FROM pharmacy_supplier_stage.batches WHERE product_id=p_product_id;
 INSERT INTO pharmacy_supplier_stage.inventory_counts(created_by,notes) VALUES(auth.uid(),COALESCE(NULLIF(trim(COALESCE(p_notes,'')),''),'جرد منتج واحد')) RETURNING id INTO v_id;
 INSERT INTO pharmacy_supplier_stage.inventory_count_items(count_id,batch_id,product_id,expected_quantity)
 VALUES(v_id,NULL,p_product_id,v_stock);
 RETURN v_id;
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_supplier_debt_ledger(p_supplier_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v jsonb;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.suppliers WHERE id=p_supplier_id) THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
  SELECT jsonb_build_object(
    'supplier',to_jsonb(s),
    'summary',jsonb_build_object(
      'invoice_total',COALESCE((SELECT SUM(total) FROM pharmacy_supplier_stage.purchases WHERE supplier_id=s.id),0),
      'paid_total',COALESCE((SELECT SUM(COALESCE(p.paid_amount,0)) FROM pharmacy_supplier_stage.purchases p WHERE p.supplier_id=s.id),0),
      'balance',COALESCE((SELECT SUM(GREATEST(total-COALESCE(paid_amount,0),0)) FROM pharmacy_supplier_stage.purchases WHERE supplier_id=s.id),0)
    ),
    'invoices',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',p.id,'invoice_number',p.invoice_number,'invoice_date',p.invoice_date,'created_at',p.created_at,
      'total',p.total,'paid_amount',p.paid_amount,'due_amount',p.due_amount,'payment_status',p.payment_status,
      'status',p.status,'notes',p.notes,
      'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_name',pr.name,'barcode',pr.barcode,'quantity',pi.quantity,'purchase_price',pi.purchase_price,'sale_price',pi.sale_price,'expiry_date',pi.expiry_date,'batch_id',pi.batch_id) ORDER BY pi.id) FROM pharmacy_supplier_stage.purchase_items pi JOIN pharmacy_supplier_stage.products pr ON pr.id=pi.product_id WHERE pi.purchase_id=p.id),'[]'::jsonb)
    ) ORDER BY COALESCE(p.invoice_date,p.created_at::date) DESC,p.created_at DESC) FROM pharmacy_supplier_stage.purchases p WHERE p.supplier_id=s.id),'[]'::jsonb),
    'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',sp.id,'amount',sp.amount,'payment_method',sp.payment_method,'notes',sp.notes,'created_at',sp.created_at,
      'cashbox_entry_id',sp.cashbox_entry_id,
      'allocations',COALESCE((SELECT jsonb_agg(jsonb_build_object('purchase_id',spa.purchase_id,'invoice_number',p2.invoice_number,'amount',spa.amount) ORDER BY p2.invoice_date,p2.created_at) FROM pharmacy_supplier_stage.supplier_payment_allocations spa JOIN pharmacy_supplier_stage.purchases p2 ON p2.id=spa.purchase_id WHERE spa.payment_id=sp.id),'[]'::jsonb)
    ) ORDER BY sp.created_at DESC) FROM pharmacy_supplier_stage.supplier_payments sp WHERE sp.supplier_id=s.id),'[]'::jsonb)
  ) INTO v
  FROM pharmacy_supplier_stage.suppliers s WHERE s.id=p_supplier_id;
  RETURN v;
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_supplier_debt_list()
 RETURNS TABLE(id uuid, name text, phone text, address text, invoice_total numeric, paid_total numeric, balance numeric, invoice_count bigint, payment_count bigint, last_payment timestamp with time zone, last_invoice timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  SELECT s.id,s.name,s.phone,s.address,
    COALESCE((SELECT SUM(COALESCE(p.total,0)) FROM pharmacy_supplier_stage.purchases p WHERE p.supplier_id=s.id),0),
    -- paid_amount is the authoritative invoice balance, so legacy invoices remain visible
    -- even when they pre-date supplier_payment_allocations.
    COALESCE((SELECT SUM(COALESCE(p.paid_amount,0)) FROM pharmacy_supplier_stage.purchases p WHERE p.supplier_id=s.id),0),
    COALESCE((SELECT SUM(GREATEST(COALESCE(p.total,0)-COALESCE(p.paid_amount,0),0)) FROM pharmacy_supplier_stage.purchases p WHERE p.supplier_id=s.id),0),
    (SELECT COUNT(*) FROM pharmacy_supplier_stage.purchases p WHERE p.supplier_id=s.id),
    (SELECT COUNT(*) FROM pharmacy_supplier_stage.supplier_payments sp WHERE sp.supplier_id=s.id),
    (SELECT MAX(sp.created_at) FROM pharmacy_supplier_stage.supplier_payments sp WHERE sp.supplier_id=s.id),
    (SELECT MAX(p.created_at) FROM pharmacy_supplier_stage.purchases p WHERE p.supplier_id=s.id)
  FROM pharmacy_supplier_stage.suppliers s
  WHERE pharmacy_supplier_stage.is_admin()
  ORDER BY (SELECT COALESCE(SUM(GREATEST(COALESCE(p2.total,0)-COALESCE(p2.paid_amount,0),0)),0) FROM pharmacy_supplier_stage.purchases p2 WHERE p2.supplier_id=s.id) DESC,s.name;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_supplier_purchase_history(p_supplier_id uuid)
 RETURNS TABLE(id uuid, invoice_number text, invoice_date date, total numeric, status text, paid_amount numeric, due_amount numeric, payment_status text, created_at timestamp with time zone, item_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
 SELECT p.id,p.invoice_number,p.invoice_date,p.total,p.status,p.paid_amount,p.due_amount,p.payment_status,p.created_at,COUNT(pi.id)::bigint
 FROM pharmacy_supplier_stage.purchases p LEFT JOIN pharmacy_supplier_stage.purchase_items pi ON pi.purchase_id=p.id
 WHERE pharmacy_supplier_stage.is_admin() AND p.supplier_id=p_supplier_id
 GROUP BY p.id ORDER BY COALESCE(p.invoice_date,p.created_at::date) DESC,p.created_at DESC;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_supplier_return(p_batch_id uuid, p_quantity numeric, p_reason text DEFAULT 'مرتجع إلى المورد'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_purchase uuid;v_result jsonb;
BEGIN
 SELECT purchase_id INTO v_purchase FROM pharmacy_supplier_stage.batches WHERE id=p_batch_id;
 IF v_purchase IS NULL THEN RAISE EXCEPTION 'لا يمكن تنفيذ مرتجع بدون فاتورة شراء مرتبطة'; END IF;
 v_result:=pharmacy_supplier_stage.admin_currency_supplier_return_v2(v_purchase,'selected',
  jsonb_build_array(jsonb_build_object('batch_id',p_batch_id,'quantity',p_quantity)),p_reason);
 RETURN jsonb_build_object('batch_id',p_batch_id,'quantity',p_quantity,'amount',v_result->'credit_amount',
   'currency',v_result->'currency');
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_supplier_return_bundle(p_purchase_id uuid, p_mode text, p_items jsonb DEFAULT '[]'::jsonb, p_reason text DEFAULT 'مرتجع إلى المورد'::text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
 SELECT pharmacy_supplier_stage.admin_currency_supplier_return_v2(p_purchase_id,p_mode,p_items,p_reason);
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_supplier_return_options()
 RETURNS TABLE(purchase_id uuid, invoice_number text, supplier_name text, purchase_date date, purchase_item_id uuid, batch_id uuid, product_id uuid, product_name text, purchased_quantity numeric, available_quantity numeric, purchase_price numeric, expiry_date date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  SELECT p.id,p.invoice_number,s.name,p.invoice_date,pi.id,b.id,pr.id,pr.name,
         pi.quantity,COALESCE(b.quantity,0),pi.purchase_price,b.expiry_date
  FROM pharmacy_supplier_stage.purchase_items pi
  JOIN pharmacy_supplier_stage.purchases p ON p.id=pi.purchase_id
  JOIN pharmacy_supplier_stage.products pr ON pr.id=pi.product_id
  LEFT JOIN pharmacy_supplier_stage.suppliers s ON s.id=p.supplier_id
  LEFT JOIN pharmacy_supplier_stage.batches b ON b.id=pi.batch_id
  WHERE pharmacy_supplier_stage.is_admin()
    AND b.id IS NOT NULL
    AND COALESCE(b.quantity,0)>0
  ORDER BY p.created_at DESC NULLS LAST,pr.name;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_system_healthcheck()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
  SELECT jsonb_build_object(
    'admin',pharmacy_supplier_stage.is_admin(),
    'tables',jsonb_build_object(
      'products',to_regclass('pharmacy_supplier_stage.products') IS NOT NULL,
      'batches',to_regclass('pharmacy_supplier_stage.batches') IS NOT NULL,
      'sales',to_regclass('pharmacy_supplier_stage.sales') IS NOT NULL,
      'sale_items',to_regclass('pharmacy_supplier_stage.sale_items') IS NOT NULL,
      'purchases',to_regclass('pharmacy_supplier_stage.purchases') IS NOT NULL,
      'purchase_items',to_regclass('pharmacy_supplier_stage.purchase_items') IS NOT NULL,
      'stock_movements',to_regclass('pharmacy_supplier_stage.stock_movements') IS NOT NULL,
      'cashbox_entries',to_regclass('pharmacy_supplier_stage.cashbox_entries') IS NOT NULL,
      'returns',to_regclass('pharmacy_supplier_stage.returns') IS NOT NULL,
      'audit_logs',to_regclass('pharmacy_supplier_stage.audit_logs') IS NOT NULL
    ),
    'columns',jsonb_build_object(
      'products_active',EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='pharmacy_supplier_stage' AND table_name='products' AND column_name='active'),
      'products_sale_price',EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='pharmacy_supplier_stage' AND table_name='products' AND column_name='sale_price'),
      'purchases_paid_amount',EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='pharmacy_supplier_stage' AND table_name='purchases' AND column_name='paid_amount'),
      'purchases_due_amount',EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='pharmacy_supplier_stage' AND table_name='purchases' AND column_name='due_amount')
    ),
    'functions',jsonb_build_object(
      'admin_get_products',to_regprocedure('pharmacy_supplier_stage.admin_get_products()') IS NOT NULL,
      'admin_search_pos_products',to_regprocedure('pharmacy_supplier_stage.admin_search_pos_products(text,integer)') IS NOT NULL,
      'complete_sale_accounting',to_regprocedure('pharmacy_supplier_stage.complete_sale_accounting(jsonb,numeric,text,uuid,text)') IS NOT NULL,
      'admin_customer_return',to_regprocedure('pharmacy_supplier_stage.admin_customer_return(uuid,numeric,text)') IS NOT NULL,
      'admin_supplier_return_bundle',to_regprocedure('pharmacy_supplier_stage.admin_supplier_return_bundle(uuid,text,jsonb,text)') IS NOT NULL,
      'admin_accounting_report',to_regprocedure('pharmacy_supplier_stage.admin_accounting_report(timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone)') IS NOT NULL,
      'admin_cashbox_summary',to_regprocedure('pharmacy_supplier_stage.admin_cashbox_summary(timestamp with time zone,timestamp with time zone)') IS NOT NULL
    )
  );
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_update_batch_details(p_batch_id uuid, p_quantity numeric, p_expiry_date date, p_purchase_price numeric DEFAULT NULL::numeric, p_sale_price numeric DEFAULT NULL::numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  b pharmacy_supplier_stage.batches%rowtype;
  v_old numeric;
  v_new numeric;
  v_product_name text;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_quantity IS NULL OR p_quantity < 0 THEN RAISE EXCEPTION 'الكمية يجب أن تكون صفراً أو أكبر'; END IF;
  IF p_expiry_date IS NULL THEN RAISE EXCEPTION 'تاريخ الصلاحية مطلوب'; END IF;
  IF p_purchase_price IS NOT NULL AND p_purchase_price < 0 THEN RAISE EXCEPTION 'سعر النت لا يمكن أن يكون سالباً'; END IF;
  IF p_sale_price IS NOT NULL AND p_sale_price < 0 THEN RAISE EXCEPTION 'سعر المبيع لا يمكن أن يكون سالباً'; END IF;

  SELECT * INTO b FROM pharmacy_supplier_stage.batches WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الدفعة غير موجودة'; END IF;
  v_old:=COALESCE(b.quantity,0); v_new:=p_quantity;
  SELECT name INTO v_product_name FROM pharmacy_supplier_stage.products WHERE id=b.product_id;

  UPDATE pharmacy_supplier_stage.batches
  SET quantity=v_new,
      expiry_date=p_expiry_date,
      purchase_price=COALESCE(p_purchase_price,purchase_price)
  WHERE id=p_batch_id;

  IF v_new<>v_old THEN
    INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
    VALUES(b.product_id,b.id,'adjustment',v_new-v_old,'تعديل كمية من بطاقة المادة',auth.uid());
  END IF;

  IF p_purchase_price IS NOT NULL OR p_sale_price IS NOT NULL THEN
    UPDATE pharmacy_supplier_stage.products
    SET purchase_price=COALESCE(p_purchase_price,purchase_price),
        sale_price=COALESCE(p_sale_price,sale_price),
        updated_at=now()
    WHERE id=b.product_id;
  END IF;

  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'adjust_stock','batch',b.id,jsonb_build_object(
    'product_id',b.product_id,
    'product_name',COALESCE(v_product_name,'—'),
    'old_quantity',v_old,
    'new_quantity',v_new,
    'delta',v_new-v_old,
    'old_expiry_date',b.expiry_date,
    'new_expiry_date',p_expiry_date,
    'old_purchase_price',b.purchase_price,
    'new_purchase_price',COALESCE(p_purchase_price,b.purchase_price),
    'new_sale_price',p_sale_price,
    'note','تعديل من بطاقة المادة'
  ));
  RETURN v_new;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_update_order_status(p_order_id uuid, p_status text)
 RETURNS TABLE(id uuid, status text, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  v_status text := lower(trim(coalesce(p_status,'')));
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;
  IF v_status NOT IN ('new','confirmed','preparing','ready','completed','cancelled') THEN
    RAISE EXCEPTION 'Invalid order status';
  END IF;

  UPDATE pharmacy_supplier_stage.orders o
  SET status = v_status,
      updated_at = now()
  WHERE o.id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  RETURN QUERY
  SELECT o.id, o.status, o.updated_at
  FROM pharmacy_supplier_stage.orders o
  WHERE o.id = p_order_id;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_update_product_prices(p_product_id uuid, p_purchase_price numeric, p_sale_price numeric)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;
  UPDATE pharmacy_supplier_stage.products
  SET purchase_price = GREATEST(COALESCE(p_purchase_price,0),0),
      sale_price = GREATEST(COALESCE(p_sale_price,0),0),
      updated_at = now()
  WHERE id = p_product_id;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  RETURN true;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_update_purchase_item_sale_currency_v1(p_purchase_item_id uuid, p_sale_currency text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_item pharmacy_supplier_stage.purchase_items%ROWTYPE; v_old text; v_product_old text;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_sale_currency IS NULL OR p_sale_currency NOT IN ('USD','SYP') THEN RAISE EXCEPTION 'Invalid sale currency'; END IF;
 SELECT * INTO v_item FROM pharmacy_supplier_stage.purchase_items WHERE id=p_purchase_item_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Purchase item not found'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.purchases WHERE id=v_item.purchase_id) THEN RAISE EXCEPTION 'Purchase not found'; END IF;
 SELECT sale_currency INTO v_product_old FROM pharmacy_supplier_stage.products WHERE id=v_item.product_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Product not found'; END IF;
 v_old:=v_item.sale_price_currency;
 IF v_old IS DISTINCT FROM p_sale_currency OR v_product_old IS DISTINCT FROM p_sale_currency THEN
  UPDATE pharmacy_supplier_stage.purchase_items SET sale_price_currency=p_sale_currency WHERE id=p_purchase_item_id;
  UPDATE pharmacy_supplier_stage.products SET sale_currency=p_sale_currency WHERE id=v_item.product_id;
  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'admin_update_purchase_sale_currency','purchase',v_item.purchase_id,
    jsonb_build_object('purchase_item_id',v_item.id,'product_id',v_item.product_id,
      'previous_invoice_currency',v_old,'previous_product_currency',v_product_old,
      'new_sale_currency',p_sale_currency,'sale_price_unchanged',v_item.sale_price));
 END IF;
 RETURN jsonb_build_object('updated',true,'purchase_item_id',v_item.id,'product_id',v_item.product_id,'sale_currency',p_sale_currency);
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_update_supplier(p_id uuid, p_name text, p_phone text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS suppliers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v pharmacy_supplier_stage.suppliers;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF nullif(trim(coalesce(p_name,'')), '') IS NULL THEN RAISE EXCEPTION 'Supplier name is required'; END IF;
  UPDATE pharmacy_supplier_stage.suppliers SET name=trim(p_name), phone=nullif(trim(coalesce(p_phone,'')),''), address=nullif(trim(coalesce(p_address,'')),''), notes=nullif(trim(coalesce(p_notes,'')),'') WHERE id=p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Supplier not found'; END IF;
  SELECT * INTO v FROM pharmacy_supplier_stage.suppliers WHERE id=p_id;
  RETURN v;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.audit_batch_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_product_name text;
BEGIN
  SELECT p.name INTO v_product_name FROM pharmacy_supplier_stage.products p WHERE p.id=NEW.product_id;
  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'admin_create_batch','batch',NEW.id,
    jsonb_build_object('product_id',NEW.product_id,'product_name',COALESCE(v_product_name,'—'),
      'batch_number',COALESCE(NEW.batch_number,'—'),'expiry_date',NEW.expiry_date,
      'quantity',NEW.quantity,'purchase_price',NEW.purchase_price,'received_date',NEW.received_date));
  RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.audit_product_changes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
BEGIN
 IF pharmacy_supplier_stage.is_admin() AND (NEW.sale_price IS DISTINCT FROM OLD.sale_price OR NEW.purchase_price IS DISTINCT FROM OLD.purchase_price) THEN
  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details) VALUES(auth.uid(),'admin_update_product_price','product',NEW.id,jsonb_build_object('product_name',NEW.name,'old_purchase_price',OLD.purchase_price,'new_purchase_price',NEW.purchase_price,'old_sale_price',OLD.sale_price,'new_sale_price',NEW.sale_price));
 END IF;
 RETURN NEW;
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.complete_sale_accounting(p_items jsonb, p_discount numeric DEFAULT 0, p_payment_method text DEFAULT 'cash'::text, p_debtor_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
 v_sale_id uuid:=gen_random_uuid(); it jsonb; b record; need numeric; take numeric; sub numeric:=0; v_total numeric:=0; v_paid numeric:=0; v_due numeric:=0;
 v_debtor_name text; v_product_id uuid; v_unit_price numeric; v_base_price numeric; v_overrides jsonb:='[]'::jsonb;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF jsonb_typeof(COALESCE(p_items,'[]'::jsonb))<>'array' OR jsonb_array_length(COALESCE(p_items,'[]'::jsonb))=0 THEN RAISE EXCEPTION 'Sale must contain items'; END IF;
 IF COALESCE(p_discount,0)<0 THEN RAISE EXCEPTION 'Invalid discount'; END IF;
 IF p_payment_method NOT IN ('cash','credit') THEN RAISE EXCEPTION 'Invalid payment method'; END IF;
 IF p_payment_method='credit' AND p_debtor_id IS NULL THEN RAISE EXCEPTION 'اختر ملف المتدين أولاً'; END IF;
 IF p_debtor_id IS NOT NULL THEN SELECT name INTO v_debtor_name FROM pharmacy_supplier_stage.debtors WHERE id=p_debtor_id; IF NOT FOUND THEN RAISE EXCEPTION 'ملف المتدين غير موجود'; END IF; END IF;
 INSERT INTO pharmacy_supplier_stage.sales(id,customer_id,debtor_id,subtotal,discount,total,created_by,payment_method,paid_amount,due_amount,payment_notes)
 VALUES(v_sale_id,NULL,p_debtor_id,0,GREATEST(COALESCE(p_discount,0),0),0,auth.uid(),p_payment_method,0,0,p_notes);
 FOR it IN SELECT value FROM jsonb_array_elements(p_items) LOOP
   v_product_id:=NULLIF(it->>'product_id','')::uuid; need:=COALESCE((it->>'quantity')::numeric,0); v_unit_price:=COALESCE((it->>'unit_price')::numeric,0);
   IF v_product_id IS NULL OR NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.products WHERE id=v_product_id) THEN RAISE EXCEPTION 'Invalid sale product'; END IF;
   IF need<=0 THEN RAISE EXCEPTION 'Invalid quantity'; END IF;
   IF v_unit_price<0 THEN RAISE EXCEPTION 'سعر البيع لا يمكن أن يكون سالباً'; END IF;
   SELECT COALESCE(p.sale_price,0) INTO v_base_price FROM pharmacy_supplier_stage.products p WHERE p.id=v_product_id;
   IF ABS(v_unit_price-v_base_price)>0.000001 THEN
     v_overrides:=v_overrides||jsonb_build_object('product_id',v_product_id,'base_unit_price',v_base_price,'final_unit_price',v_unit_price,'difference',v_unit_price-v_base_price);
   END IF;
   FOR b IN SELECT bt.id,bt.quantity,bt.purchase_price,bt.expiry_date FROM pharmacy_supplier_stage.batches bt WHERE bt.product_id=v_product_id AND bt.quantity>0 AND (bt.expiry_date IS NULL OR bt.expiry_date>=current_date) ORDER BY bt.expiry_date NULLS LAST,bt.received_date NULLS FIRST,bt.batch_number NULLS LAST,bt.id FOR UPDATE OF bt LOOP
     EXIT WHEN need<=0; take:=LEAST(need,b.quantity); UPDATE pharmacy_supplier_stage.batches bt SET quantity=bt.quantity-take WHERE bt.id=b.id;
     INSERT INTO pharmacy_supplier_stage.sale_items(sale_id,product_id,batch_id,quantity,unit_price,unit_cost,base_unit_price) VALUES(v_sale_id,v_product_id,b.id,take,v_unit_price,b.purchase_price,v_base_price);
     INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,created_by) VALUES(v_product_id,b.id,'sale',-take,v_sale_id,auth.uid());
     sub:=sub+take*v_unit_price; need:=need-take;
   END LOOP;
   IF need>0 THEN RAISE EXCEPTION 'Insufficient non-expired stock for product %',v_product_id; END IF;
 END LOOP;
 v_total:=GREATEST(sub-GREATEST(COALESCE(p_discount,0),0),0);
 IF p_payment_method='cash' THEN v_paid:=v_total; v_due:=0; ELSE v_paid:=0; v_due:=v_total; END IF;
 UPDATE pharmacy_supplier_stage.sales s SET subtotal=sub,total=v_total,paid_amount=v_paid,due_amount=v_due WHERE s.id=v_sale_id;
 IF p_payment_method='credit' THEN
   INSERT INTO pharmacy_supplier_stage.debtor_transactions(debtor_id,transaction_type,sale_id,amount,debit,credit,payment_method,notes,created_by) VALUES(p_debtor_id,'sale',v_sale_id,v_total,v_total,0,'credit',p_notes,auth.uid());
 ELSE
   INSERT INTO pharmacy_supplier_stage.cashbox_entries(entry_type,amount,description,sale_id,created_by) VALUES('sale_cash',v_total,'بيع نقدي',v_sale_id,auth.uid());
 END IF;
 INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'complete_sale','sale',v_sale_id,jsonb_build_object('subtotal',sub,'discount',p_discount,'total',v_total,'payment_method',p_payment_method,'debtor_id',p_debtor_id,'debtor_name',v_debtor_name,'paid_amount',v_paid,'due_amount',v_due,'price_overrides',v_overrides,'notes',p_notes));
 RETURN jsonb_build_object('sale_id',v_sale_id,'total',v_total,'payment_method',p_payment_method,'debtor_id',p_debtor_id,'paid_amount',v_paid,'due_amount',v_due,'price_overrides',v_overrides);
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.complete_sale_accounting_currency(p_currency text DEFAULT 'SYP'::text, p_debtor_id uuid DEFAULT NULL::uuid, p_discount numeric DEFAULT 0, p_fx_rate numeric DEFAULT NULL::numeric, p_items jsonb DEFAULT '[]'::jsonb, p_notes text DEFAULT NULL::text, p_payment_method text DEFAULT 'cash'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  v_sale_id uuid:=gen_random_uuid(); it jsonb; b record; need numeric; take numeric; sub numeric:=0; v_total numeric:=0; v_paid numeric:=0; v_due numeric:=0;
  v_debtor_name text; v_product_id uuid; v_unit_price numeric; v_base_price numeric; v_product_currency text; v_item_fx numeric; v_stock numeric;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF upper(COALESCE(p_currency,'SYP')) NOT IN ('SYP','USD') THEN RAISE EXCEPTION 'عملة الفاتورة غير صحيحة'; END IF;
  IF jsonb_typeof(COALESCE(p_items,'[]'::jsonb))<>'array' OR jsonb_array_length(COALESCE(p_items,'[]'::jsonb))=0 THEN RAISE EXCEPTION 'Sale must contain items'; END IF;
  IF COALESCE(p_discount,0)<0 THEN RAISE EXCEPTION 'Invalid discount'; END IF;
  IF p_payment_method NOT IN ('cash','credit') THEN RAISE EXCEPTION 'Invalid payment method'; END IF;
  IF p_payment_method='credit' AND p_debtor_id IS NULL THEN RAISE EXCEPTION 'اختر ملف المتدين أولاً'; END IF;
  IF p_debtor_id IS NOT NULL THEN SELECT name INTO v_debtor_name FROM pharmacy_supplier_stage.debtors WHERE id=p_debtor_id; IF NOT FOUND THEN RAISE EXCEPTION 'ملف المتدين غير موجود'; END IF; END IF;
  SELECT usd_to_syp INTO v_item_fx FROM pharmacy_supplier_stage.pharmacy_currency_settings WHERE id=1;
  v_item_fx:=COALESCE(NULLIF(p_fx_rate,0),v_item_fx,1);
  INSERT INTO pharmacy_supplier_stage.sales(id,customer_id,debtor_id,subtotal,discount,total,created_by,payment_method,paid_amount,due_amount,payment_notes,currency,fx_rate,total_syp)
  VALUES(v_sale_id,NULL,p_debtor_id,0,GREATEST(COALESCE(p_discount,0),0),0,auth.uid(),p_payment_method,0,0,p_notes,upper(COALESCE(p_currency,'SYP')),v_item_fx,0);

  FOR it IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id:=NULLIF(it->>'product_id','')::uuid;
    need:=COALESCE((it->>'quantity')::numeric,0);
    SELECT p.sale_price,p.sale_currency INTO v_base_price,v_product_currency FROM pharmacy_supplier_stage.products p WHERE p.id=v_product_id AND COALESCE(p.active,true)=true;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invalid sale product'; END IF;
    IF need<=0 THEN RAISE EXCEPTION 'Invalid quantity'; END IF;
    v_product_currency:=upper(COALESCE(v_product_currency,'SYP'));
    IF v_product_currency='USD' THEN v_unit_price:=v_base_price*v_item_fx; ELSE v_unit_price:=v_base_price; END IF;
    IF it ? 'unit_price' AND (it->>'unit_price') IS NOT NULL THEN
      IF (it->>'unit_price')::numeric<0 THEN RAISE EXCEPTION 'سعر البيع لا يمكن أن يكون سالباً'; END IF;
      v_unit_price:=(it->>'unit_price')::numeric;
    END IF;
    FOR b IN SELECT bt.id,bt.quantity,bt.purchase_price,bt.expiry_date FROM pharmacy_supplier_stage.batches bt WHERE bt.product_id=v_product_id AND bt.quantity>0 AND (bt.expiry_date IS NULL OR bt.expiry_date>=CURRENT_DATE) ORDER BY bt.expiry_date NULLS LAST,bt.received_date NULLS FIRST,bt.batch_number NULLS LAST,bt.id FOR UPDATE OF bt LOOP
      EXIT WHEN need<=0; take:=LEAST(need,b.quantity); UPDATE pharmacy_supplier_stage.batches bt SET quantity=bt.quantity-take WHERE bt.id=b.id;
      INSERT INTO pharmacy_supplier_stage.sale_items(sale_id,product_id,batch_id,quantity,unit_price,unit_cost,base_unit_price,price_currency,price_fx_rate)
      VALUES(v_sale_id,v_product_id,b.id,take,v_unit_price,b.purchase_price,v_base_price,v_product_currency,v_item_fx);
      INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,created_by) VALUES(v_product_id,b.id,'sale',-take,v_sale_id,auth.uid());
      sub:=sub+take*v_unit_price; need:=need-take;
    END LOOP;
    IF need>0 THEN RAISE EXCEPTION 'Insufficient non-expired stock for product %',v_product_id; END IF;
  END LOOP;
  v_total:=GREATEST(sub-GREATEST(COALESCE(p_discount,0),0),0);
  IF p_payment_method='cash' THEN v_paid:=v_total; v_due:=0; ELSE v_paid:=0; v_due:=v_total; END IF;
  UPDATE pharmacy_supplier_stage.sales SET subtotal=sub,total=v_total,paid_amount=v_paid,due_amount=v_due,total_syp=v_total WHERE id=v_sale_id;
  IF p_payment_method='credit' THEN
    INSERT INTO pharmacy_supplier_stage.debtor_transactions(debtor_id,transaction_type,sale_id,amount,debit,credit,payment_method,notes,created_by,currency,fx_rate,amount_syp)
    VALUES(p_debtor_id,'sale',v_sale_id,v_total,v_total,0,'credit',p_notes,auth.uid(),'SYP',v_item_fx,v_total);
  ELSE
    INSERT INTO pharmacy_supplier_stage.cashbox_entries(entry_type,amount,description,sale_id,created_by,currency,fx_rate,amount_syp)
    VALUES('sale_cash',v_total,'بيع نقدي',v_sale_id,auth.uid(),'SYP',v_item_fx,v_total);
  END IF;
  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'complete_sale','sale',v_sale_id,jsonb_build_object('currency',upper(COALESCE(p_currency,'SYP')),'fx_rate',v_item_fx,'subtotal',sub,'discount',p_discount,'total',v_total,'payment_method',p_payment_method,'debtor_id',p_debtor_id,'debtor_name',v_debtor_name,'notes',p_notes));
  RETURN jsonb_build_object('sale_id',v_sale_id,'total',v_total,'currency','SYP','fx_rate',v_item_fx,'payment_method',p_payment_method,'debtor_id',p_debtor_id,'paid_amount',v_paid,'due_amount',v_due);
EXCEPTION WHEN OTHERS THEN
  RAISE;
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.complete_sale_atomic(p_items jsonb, p_discount numeric DEFAULT 0, p_customer_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE
  v_sale_id uuid := gen_random_uuid(); it jsonb; v_batch record; need numeric; take numeric;
  sub numeric := 0; v_total numeric; v_product_id uuid; v_unit_price numeric; v_sale_details jsonb;
BEGIN
  IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array' OR jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 THEN RAISE EXCEPTION 'Sale must contain items'; END IF;
  IF coalesce(p_discount,0)<0 THEN RAISE EXCEPTION 'Invalid discount'; END IF;
  INSERT INTO pharmacy_supplier_stage.sales(id,customer_id,subtotal,discount,total,created_by)
  VALUES(v_sale_id,p_customer_id,0,greatest(coalesce(p_discount,0),0),0,auth.uid());
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_product_id:=nullif(it->>'product_id','')::uuid; need:=coalesce((it->>'quantity')::numeric,0); v_unit_price:=coalesce((it->>'unit_price')::numeric,0);
    IF v_product_id IS NULL OR need<=0 OR v_unit_price<0 THEN RAISE EXCEPTION 'Invalid sale item'; END IF;
    FOR v_batch IN SELECT bt.id,bt.quantity,bt.purchase_price,bt.expiry_date FROM pharmacy_supplier_stage.batches AS bt WHERE bt.product_id=v_product_id AND bt.quantity>0 AND (bt.expiry_date IS NULL OR bt.expiry_date>=current_date) ORDER BY bt.expiry_date NULLS LAST,bt.received_date NULLS FIRST,bt.id FOR UPDATE OF bt LOOP
      EXIT WHEN need<=0; take:=least(need,v_batch.quantity);
      UPDATE pharmacy_supplier_stage.batches SET quantity=quantity-take WHERE id=v_batch.id;
      INSERT INTO pharmacy_supplier_stage.sale_items(sale_id,product_id,batch_id,quantity,unit_price,unit_cost) VALUES(v_sale_id,v_product_id,v_batch.id,take,v_unit_price,v_batch.purchase_price);
      INSERT INTO pharmacy_supplier_stage.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,created_by) VALUES(v_product_id,v_batch.id,'sale',-take,v_sale_id,auth.uid());
      sub:=sub+take*v_unit_price; need:=need-take;
    END LOOP;
    IF need>0 THEN RAISE EXCEPTION 'Insufficient non-expired stock for product %',v_product_id; END IF;
  END LOOP;
  v_total:=greatest(sub-greatest(coalesce(p_discount,0),0),0);
  UPDATE pharmacy_supplier_stage.sales SET subtotal=sub,total=v_total WHERE id=v_sale_id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('product_name',COALESCE(p.name,'—'),'batch_number',COALESCE(b.batch_number,'—'),'quantity',si.quantity) ORDER BY p.name,b.batch_number),'[]'::jsonb)
  INTO v_sale_details
  FROM pharmacy_supplier_stage.sale_items si LEFT JOIN pharmacy_supplier_stage.products p ON p.id=si.product_id LEFT JOIN pharmacy_supplier_stage.batches b ON b.id=si.batch_id
  WHERE si.sale_id=v_sale_id;
  INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'complete_sale','sale',v_sale_id,jsonb_build_object('subtotal',sub,'discount',p_discount,'total',v_total,'items',v_sale_details));
  RETURN v_sale_id;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.create_public_order(p_name text, p_phone text, p_address text, p_notes text, p_items jsonb)
 RETURNS TABLE(public_code text, order_id uuid, total numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage'
AS $function$
DECLARE
  v_customer_id uuid;
  v_order_id uuid;
  v_code text;
  v_total numeric := 0;
  v_item jsonb;
  v_product_id uuid;
  v_quantity numeric;
  v_price numeric;
BEGIN
  IF COALESCE(trim(p_name), '') = '' THEN
    RAISE EXCEPTION 'Customer name is required';
  END IF;

  IF COALESCE(trim(p_phone), '') = '' THEN
    RAISE EXCEPTION 'Customer phone is required';
  END IF;

  IF p_items IS NULL
     OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Order must contain at least one item';
  END IF;

  INSERT INTO pharmacy_supplier_stage.customers(name, phone, address)
  VALUES (
    trim(p_name),
    trim(p_phone),
    NULLIF(trim(p_address), '')
  )
  RETURNING id INTO v_customer_id;

  INSERT INTO pharmacy_supplier_stage.orders(
    customer_id,
    status,
    notes,
    total
  )
  VALUES (
    v_customer_id,
    'new',
    NULLIF(trim(p_notes), ''),
    0
  )
  RETURNING id INTO v_order_id;

  SELECT o.public_code
  INTO v_code
  FROM pharmacy_supplier_stage.orders AS o
  WHERE o.id = v_order_id;

  FOR v_item IN
    SELECT value
    FROM jsonb_array_elements(p_items)
  LOOP

    v_product_id := (v_item->>'product_id')::uuid;
    v_quantity := (v_item->>'quantity')::numeric;

    IF v_quantity IS NULL OR v_quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity';
    END IF;

    SELECT p.sale_price
    INTO v_price
    FROM pharmacy_supplier_stage.products AS p
    WHERE p.id = v_product_id
      AND p.customer_visible = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product not available';
    END IF;

    v_price := COALESCE(v_price, 0);

    INSERT INTO pharmacy_supplier_stage.order_items(
      order_id,
      product_id,
      quantity,
      unit_price
    )
    VALUES (
      v_order_id,
      v_product_id,
      v_quantity,
      v_price
    );

    v_total := v_total + (v_quantity * v_price);
  END LOOP;

  UPDATE pharmacy_supplier_stage.orders AS o
  SET total = v_total
  WHERE o.id = v_order_id;

  RETURN QUERY
  SELECT
    v_code,
    v_order_id,
    v_total;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.fefo_batches(p_product_id uuid, p_required_qty numeric)
 RETURNS TABLE(batch_id uuid, take_qty numeric, expiry_date date)
 LANGUAGE plpgsql
AS $function$
declare
  remaining numeric := p_required_qty;
  r record;
begin
  if p_required_qty <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  for r in
    select id, quantity, expiry_date
    from pharmacy_supplier_stage.batches
    where product_id = p_product_id
      and quantity > 0
      and (expiry_date is null or expiry_date >= current_date)
    order by expiry_date nulls last, id
    for update
  loop
    exit when remaining <= 0;
    take_qty := least(remaining, r.quantity);
    batch_id := r.id;
    expiry_date := r.expiry_date;
    remaining := remaining - take_qty;
    return next;
  end loop;

  if remaining > 0 then
    raise exception 'Insufficient non-expired stock';
  end if;
end;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.get_admin_orders()
 RETURNS TABLE(id uuid, public_code text, status text, total numeric, created_at timestamp with time zone, customer_name text, customer_phone text, customer_address text, items jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN
   RAISE EXCEPTION 'Admin authorization required';
 END IF;
 RETURN QUERY
 SELECT o.id,o.public_code,o.status,o.total,o.created_at, c.name,c.phone,c.address,
 COALESCE((SELECT jsonb_agg(jsonb_build_object('product_name',p.name,'quantity',oi.quantity,'unit_price',oi.unit_price) ORDER BY oi.created_at) FROM order_items oi LEFT JOIN products p ON p.id=oi.product_id WHERE oi.order_id=o.id),'[]'::jsonb)
 FROM orders o LEFT JOIN customers c ON c.id=o.customer_id ORDER BY o.created_at DESC LIMIT 150;
END; $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.prevent_primary_barcode_alias_collision()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pharmacy_supplier_stage'
AS $function$
begin
 if nullif(btrim(coalesce(new.barcode,'')),'') is not null and exists(
  select 1 from pharmacy_supplier_stage.product_barcodes pb where pb.barcode=btrim(new.barcode)
 ) then raise exception 'الباركود الأساسي مسجل كإضافي لمنتج آخر'; end if;
 return new;
end $function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.process_sale(p_items jsonb, p_discount numeric DEFAULT 0, p_customer_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(sale_id uuid, subtotal numeric, discount numeric, total numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage'
AS $function$
DECLARE
    v_sale_id uuid;
    v_user_id uuid;
    v_subtotal numeric := 0;
    v_discount numeric := COALESCE(p_discount, 0);
    v_total numeric;
    v_item jsonb;
    v_product_id uuid;
    v_quantity numeric;
    v_unit_price numeric;
    v_remaining numeric;
    v_take numeric;
    v_batch_id uuid;
    v_expiry_date date;
    v_unit_cost numeric;
BEGIN
    ----------------------------------------------------------------
    -- 1. التأكد من وجود مستخدم مسجل الدخول
    ----------------------------------------------------------------
    v_user_id := auth.uid();

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    ----------------------------------------------------------------
    -- 2. التحقق من بيانات الإدخال
    ----------------------------------------------------------------
    IF p_items IS NULL
       OR jsonb_typeof(p_items) <> 'array'
       OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Sale must contain at least one item';
    END IF;

    IF v_discount < 0 THEN
        RAISE EXCEPTION 'Discount cannot be negative';
    END IF;

    ----------------------------------------------------------------
    -- 3. إنشاء سجل البيع مؤقتًا
    ----------------------------------------------------------------
    INSERT INTO pharmacy_supplier_stage.sales (
        customer_id,
        subtotal,
        discount,
        total,
        created_by
    )
    VALUES (
        p_customer_id,
        0,
        0,
        0,
        v_user_id
    )
    RETURNING id INTO v_sale_id;

    ----------------------------------------------------------------
    -- 4. معالجة كل صنف
    --
    -- Expected JSON:
    -- [
    --   {
    --     "product_id": "UUID",
    --     "quantity": 2,
    --     "unit_price": 1500
    --   }
    -- ]
    ----------------------------------------------------------------
    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(p_items)
    LOOP

        ------------------------------------------------------------
        -- استخراج البيانات
        ------------------------------------------------------------
        BEGIN
            v_product_id := (v_item->>'product_id')::uuid;
        EXCEPTION
            WHEN others THEN
                RAISE EXCEPTION 'Invalid product_id';
        END;

        BEGIN
            v_quantity := (v_item->>'quantity')::numeric;
        EXCEPTION
            WHEN others THEN
                RAISE EXCEPTION 'Invalid quantity for product %',
                    v_product_id;
        END;

        BEGIN
            v_unit_price := (v_item->>'unit_price')::numeric;
        EXCEPTION
            WHEN others THEN
                RAISE EXCEPTION 'Invalid unit_price for product %',
                    v_product_id;
        END;

        ------------------------------------------------------------
        -- التحقق من القيم
        ------------------------------------------------------------
        IF v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION
                'Quantity must be greater than zero for product %',
                v_product_id;
        END IF;

        IF v_unit_price IS NULL OR v_unit_price < 0 THEN
            RAISE EXCEPTION
                'Unit price cannot be negative for product %',
                v_product_id;
        END IF;

        ------------------------------------------------------------
        -- التأكد من وجود المنتج
        ------------------------------------------------------------
        IF NOT EXISTS (
            SELECT 1
            FROM pharmacy_supplier_stage.products
            WHERE id = v_product_id
        ) THEN
            RAISE EXCEPTION
                'Product % does not exist',
                v_product_id;
        END IF;

        ------------------------------------------------------------
        -- حساب الإجمالي الفرعي
        ------------------------------------------------------------
        v_subtotal :=
            v_subtotal + (v_quantity * v_unit_price);

        ------------------------------------------------------------
        -- FEFO:
        -- أقدم تاريخ انتهاء أولًا
        --
        -- FOR UPDATE يحجز الدفعات أثناء العملية
        ------------------------------------------------------------
        v_remaining := v_quantity;

        FOR v_batch_id, v_take, v_expiry_date IN
            SELECT
                f.batch_id,
                f.take_qty,
                f.expiry_date
            FROM pharmacy_supplier_stage.fefo_batches(
                v_product_id,
                v_remaining
            ) f
        LOOP

            EXIT WHEN v_remaining <= 0;

            --------------------------------------------------------
            -- الحصول على تكلفة الشراء للدفعة
            --------------------------------------------------------
            SELECT purchase_price
            INTO v_unit_cost
            FROM pharmacy_supplier_stage.batches
            WHERE id = v_batch_id
            FOR UPDATE;

            IF NOT FOUND THEN
                RAISE EXCEPTION
                    'Batch % no longer exists',
                    v_batch_id;
            END IF;

            --------------------------------------------------------
            -- تسجيل sale_items
            --------------------------------------------------------
            INSERT INTO pharmacy_supplier_stage.sale_items (
                sale_id,
                product_id,
                batch_id,
                quantity,
                unit_price,
                unit_cost
            )
            VALUES (
                v_sale_id,
                v_product_id,
                v_batch_id,
                v_take,
                v_unit_price,
                v_unit_cost
            );

            --------------------------------------------------------
            -- خصم الكمية فعليًا من الدفعة
            --------------------------------------------------------
            UPDATE pharmacy_supplier_stage.batches
            SET quantity = quantity - v_take
            WHERE id = v_batch_id
              AND quantity >= v_take;

            IF NOT FOUND THEN
                RAISE EXCEPTION
                    'Insufficient stock in batch %',
                    v_batch_id;
            END IF;

            --------------------------------------------------------
            -- تسجيل حركة المخزون
            --
            -- البيع = خروج من المخزون
            -- لذلك الكمية سالبة
            --------------------------------------------------------
            INSERT INTO pharmacy_supplier_stage.stock_movements (
                product_id,
                batch_id,
                movement_type,
                quantity,
                reference_id,
                note,
                created_by
            )
            VALUES (
                v_product_id,
                v_batch_id,
                'sale',
                -v_take,
                v_sale_id,
                'Sale transaction',
                v_user_id
            );

            v_remaining := v_remaining - v_take;

        END LOOP;

        ------------------------------------------------------------
        -- للتأكد من أن الكمية المطلوبة تم تأمينها
        ------------------------------------------------------------
        IF v_remaining > 0 THEN
            RAISE EXCEPTION
                'Insufficient non-expired stock for product %',
                v_product_id;
        END IF;

    END LOOP;

    ----------------------------------------------------------------
    -- 5. التحقق من الخصم
    ----------------------------------------------------------------
    IF v_discount > v_subtotal THEN
        RAISE EXCEPTION
            'Discount cannot exceed subtotal';
    END IF;

    ----------------------------------------------------------------
    -- 6. حساب الإجمالي
    ----------------------------------------------------------------
    v_total := v_subtotal - v_discount;

    ----------------------------------------------------------------
    -- 7. تحديث sales
    ----------------------------------------------------------------
    UPDATE pharmacy_supplier_stage.sales
    SET
        subtotal = v_subtotal,
        discount = v_discount,
        total = v_total
    WHERE id = v_sale_id;

    ----------------------------------------------------------------
    -- 8. إرجاع نتيجة البيع
    ----------------------------------------------------------------
    RETURN QUERY
    SELECT
        v_sale_id,
        v_subtotal,
        v_discount,
        v_total;

END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.production_healthcheck()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage'
AS $function$
declare
  neg integer;
  exp integer;
begin
  if not pharmacy_supplier_stage.is_admin() then raise exception 'Admin authorization required'; end if;
  select count(*) into neg from pharmacy_supplier_stage.batches where quantity < 0;
  select count(*) into exp from pharmacy_supplier_stage.batches where quantity > 0 and expiry_date < current_date;
  return jsonb_build_object('ok',neg=0 and exp=0,'negative_stock_batches',neg,'expired_batches_with_stock',exp);
end;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.submit_medicine_request(p_name text, p_strength text, p_phone text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage'
AS $function$
declare v_id uuid;
begin
  if coalesce(trim(p_name),'')='' or coalesce(trim(p_phone),'')='' then raise exception 'Name and phone are required'; end if;
  insert into pharmacy_supplier_stage.medicine_requests(name,strength,phone,status)
  values(trim(p_name),nullif(trim(coalesce(p_strength,'')),''),trim(p_phone),'new')
  returning id into v_id;
  return v_id;
end;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.submit_public_prescription(p_name text, p_phone text, p_notes text, p_file_path text, p_file_name text, p_mime_type text, p_file_size bigint)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage'
AS $function$
declare v_id uuid;
begin
  if coalesce(trim(p_name),'')='' or coalesce(trim(p_phone),'')='' then raise exception 'Name and phone are required'; end if;
  if p_file_path not like 'intake/%' then raise exception 'Invalid prescription path'; end if;
  if p_file_size is null or p_file_size > 10485760 then raise exception 'File is too large'; end if;
  insert into pharmacy_supplier_stage.prescriptions(customer_name,customer_phone,notes,file_path,file_name,mime_type,file_size,status)
  values(trim(p_name),trim(p_phone),nullif(trim(coalesce(p_notes,'')),''),p_file_path,p_file_name,p_mime_type,p_file_size,'new')
  returning id into v_id;
  return v_id;
end;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.sync_purchase_payment_state()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
 IF TG_OP='INSERT' OR NEW.total IS DISTINCT FROM OLD.total
     OR NEW.credit_amount IS DISTINCT FROM OLD.credit_amount THEN
  NEW.paid_amount:=LEAST(GREATEST(COALESCE(NEW.paid_amount,0),0),COALESCE(NEW.total,0));
  NEW.due_amount:=GREATEST(COALESCE(NEW.total,0)-NEW.paid_amount-COALESCE(NEW.credit_amount,0),0);
  NEW.payment_status:=CASE WHEN NEW.paid_amount+COALESCE(NEW.credit_amount,0)>=NEW.total-0.000001
    THEN 'paid' WHEN NEW.paid_amount>0 OR COALESCE(NEW.credit_amount,0)>0 THEN 'partial' ELSE 'unpaid' END;
 END IF;
 RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.track_public_order(p_code text, p_phone text)
 RETURNS TABLE(public_code text, status text, created_at timestamp with time zone, updated_at timestamp with time zone, total numeric, customer_name text, customer_phone text, customer_address text, notes text, items jsonb)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage'
AS $function$
  SELECT
    o.public_code,
    o.status,
    o.created_at,
    o.updated_at,
    o.total,
    c.name,
    c.phone,
    c.address,
    o.notes,
    COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'product_name', p.name,
          'quantity', oi.quantity,
          'unit_price', oi.unit_price
        ) ORDER BY oi.created_at
      )
      FROM pharmacy_supplier_stage.order_items oi
      LEFT JOIN pharmacy_supplier_stage.products p ON p.id = oi.product_id
      WHERE oi.order_id = o.id
    ), '[]'::jsonb)
  FROM pharmacy_supplier_stage.orders o
  JOIN pharmacy_supplier_stage.customers c ON c.id = o.customer_id
  WHERE upper(o.public_code)=upper(trim(p_code))
    AND c.phone=trim(p_phone)
  ORDER BY o.created_at DESC
  LIMIT 1;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.validate_sale_quantity(requested_qty integer, available_qty integer)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select requested_qty > 0 and available_qty >= requested_qty;
$function$;
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.validate_supplier_payment_allocation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v_supplier uuid; v_purchase_supplier uuid; v_invoice_currency text;
        v_payment_currency text; v_invoice_total numeric; v_payment_total numeric;
        v_already_invoice numeric; v_already_payment numeric; v_payment_fx numeric;
BEGIN
  SELECT supplier_id, currency, amount, fx_rate INTO v_supplier,v_payment_currency,v_payment_total,v_payment_fx
    FROM pharmacy_supplier_stage.supplier_payments WHERE id=NEW.payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'دفعة المورد غير موجودة'; END IF;
  SELECT supplier_id,currency,GREATEST(total-COALESCE(credit_amount,0),0) INTO v_purchase_supplier,v_invoice_currency,v_invoice_total
    FROM pharmacy_supplier_stage.purchases WHERE id=NEW.purchase_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'فاتورة الشراء غير موجودة'; END IF;
  IF v_supplier IS DISTINCT FROM v_purchase_supplier THEN
    RAISE EXCEPTION 'لا يمكن تخصيص دفعة لمورد مختلف'; END IF;
  IF v_payment_currency IS DISTINCT FROM v_invoice_currency THEN
    RAISE EXCEPTION 'لا يمكن تخصيص دفعة بعملة مختلفة عن عملة الفاتورة'; END IF;
  IF NEW.currency IS DISTINCT FROM v_invoice_currency THEN
    RAISE EXCEPTION 'عملة التوزيع لا تطابق عملة الفاتورة'; END IF;
  IF NEW.amount IS NULL OR NEW.amount<=0 THEN RAISE EXCEPTION 'مبلغ التوزيع غير صالح'; END IF;
  IF NEW.fx_rate IS DISTINCT FROM v_payment_fx THEN
    RAISE EXCEPTION 'سعر صرف التخصيص لا يطابق سعر صرف الدفعة'; END IF;
  IF v_payment_currency='USD' AND
     (NEW.amount_syp IS NULL OR NEW.amount_syp IS DISTINCT FROM ROUND(NEW.amount*v_payment_fx,2)) THEN
    RAISE EXCEPTION 'قيمة تحويل تخصيص الدولار إلى الليرة غير صحيحة'; END IF;
  IF v_payment_currency='SYP' AND NEW.amount_syp IS NOT NULL AND
     NEW.amount_syp IS DISTINCT FROM NEW.amount THEN
    RAISE EXCEPTION 'تخصيص الليرة يحتوي مقابلاً غير مطابق بالليرة'; END IF;

  SELECT COALESCE(SUM(amount),0) INTO v_already_invoice
    FROM pharmacy_supplier_stage.supplier_payment_allocations
    WHERE purchase_id=NEW.purchase_id AND id IS DISTINCT FROM NEW.id;
  SELECT COALESCE(SUM(amount),0) INTO v_already_payment
    FROM pharmacy_supplier_stage.supplier_payment_allocations
    WHERE payment_id=NEW.payment_id AND id IS DISTINCT FROM NEW.id;
  IF v_already_invoice+NEW.amount>v_invoice_total+0.0000001 THEN
    RAISE EXCEPTION 'التوزيع يتجاوز قيمة الفاتورة'; END IF;
  IF v_already_payment+NEW.amount>v_payment_total+0.0000001 THEN
    RAISE EXCEPTION 'التوزيع يتجاوز قيمة الدفعة'; END IF;
  RETURN NEW;
END;
$function$;
CREATE FUNCTION pharmacy_supplier_stage.is_admin() RETURNS boolean LANGUAGE sql STABLE SET search_path='' AS $$ SELECT auth.uid()='15cdd7b6-cbfa-4607-9364-2787447f7680'::uuid AND current_setting('pharmacy_supplier_stage.verified_actor',true)='15cdd7b6-cbfa-4607-9364-2787447f7680' $$;
CREATE TRIGGER products_set_updated_at BEFORE UPDATE ON pharmacy_supplier_stage.products FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER orders_set_updated_at BEFORE UPDATE ON pharmacy_supplier_stage.orders FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_audit_batch_insert AFTER INSERT ON pharmacy_supplier_stage.batches FOR EACH ROW EXECUTE FUNCTION audit_batch_insert();
CREATE TRIGGER trg_audit_product_changes AFTER UPDATE OF purchase_price, sale_price ON pharmacy_supplier_stage.products FOR EACH ROW EXECUTE FUNCTION audit_product_changes();
CREATE TRIGGER trg_ab_allocation_metadata_guard_v1 BEFORE UPDATE OF currency, fx_rate, amount_syp ON pharmacy_supplier_stage.supplier_payment_allocations FOR EACH ROW EXECUTE FUNCTION validate_supplier_payment_allocation();
CREATE TRIGGER trg_ab_sync_purchase_credit_amount_v1 BEFORE UPDATE OF credit_amount ON pharmacy_supplier_stage.purchases FOR EACH ROW EXECUTE FUNCTION sync_purchase_payment_state();
CREATE TRIGGER trg_ab_validate_supplier_return_v1 BEFORE INSERT ON pharmacy_supplier_stage.returns FOR EACH ROW EXECUTE FUNCTION ab_validate_supplier_return_v1();
CREATE TRIGGER trg_ab_apply_supplier_return_credit_v1 AFTER INSERT ON pharmacy_supplier_stage.returns FOR EACH ROW EXECUTE FUNCTION ab_apply_supplier_return_credit_v1();
CREATE TRIGGER trg_ab_immutable_supplier_return_v1 BEFORE DELETE OR UPDATE ON pharmacy_supplier_stage.returns FOR EACH ROW EXECUTE FUNCTION ab_immutable_supplier_return_v1();
CREATE TRIGGER products_prevent_barcode_alias_collision BEFORE INSERT OR UPDATE OF barcode ON pharmacy_supplier_stage.products FOR EACH ROW EXECUTE FUNCTION prevent_primary_barcode_alias_collision();
CREATE TRIGGER trg_sync_purchase_payment_state BEFORE INSERT OR UPDATE OF total ON pharmacy_supplier_stage.purchases FOR EACH ROW EXECUTE FUNCTION sync_purchase_payment_state();
CREATE TRIGGER trg_validate_supplier_payment_allocation BEFORE INSERT OR UPDATE OF payment_id, purchase_id, amount ON pharmacy_supplier_stage.supplier_payment_allocations FOR EACH ROW EXECUTE FUNCTION validate_supplier_payment_allocation();
REVOKE ALL ON ALL TABLES IN SCHEMA pharmacy_supplier_stage FROM PUBLIC,anon,authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pharmacy_supplier_stage FROM PUBLIC,anon,authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA pharmacy_supplier_stage FROM PUBLIC,anon,authenticated;

