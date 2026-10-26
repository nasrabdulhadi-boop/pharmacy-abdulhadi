-- EMPTY DISPOSABLE SUPABASE PROJECT ONLY. Never run on the pharmacy project.
-- Caller must set pharmacy.qa_fixture to isolated-synthetic-v1 and private test passwords.
BEGIN;
DO $guard$
BEGIN
 IF current_setting('pharmacy.qa_fixture',true) IS DISTINCT FROM 'isolated-synthetic-v1'
  OR to_regclass('public.products') IS NOT NULL
  OR EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE')
  OR EXISTS(SELECT 1 FROM auth.users) THEN
  RAISE EXCEPTION 'Synthetic fixture requires an explicitly selected empty disposable project';
 END IF;
 IF length(COALESCE(current_setting('pharmacy.qa_admin_password',true),''))<32
  OR length(COALESCE(current_setting('pharmacy.qa_user_password',true),''))<32 THEN
  RAISE EXCEPTION 'Private synthetic account passwords are required';
 END IF;
END;$guard$;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change)
SELECT '00000000-0000-0000-0000-000000000000'::uuid,v.id,'authenticated','authenticated',v.email,
 extensions.crypt(current_setting(v.password_setting),extensions.gen_salt('bf')),now(),
 jsonb_build_object('provider','email','providers',jsonb_build_array('email'),'role',v.app_role),
 '{"role":"admin","fixture":"isolated-only"}'::jsonb,now(),now(),'','','',''
FROM (VALUES
 ('00000000-0000-4000-8000-000000000101'::uuid,'clinical-qa-admin@example.invalid','admin','pharmacy.qa_admin_password'),
 ('00000000-0000-4000-8000-000000000102'::uuid,'clinical-qa-user@example.invalid','user','pharmacy.qa_user_password')
) AS v(id,email,app_role,password_setting);
INSERT INTO auth.identities(provider_id,user_id,identity_data,provider,created_at,updated_at)
SELECT id::text,id,jsonb_build_object('sub',id::text,'email',email,'email_verified',true),'email',now(),now()
FROM auth.users;

-- Same existing admin-check logic; all accounts above are synthetic.
CREATE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,auth AS $admin$
 SELECT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=auth.uid() AND
  (COALESCE(u.raw_app_meta_data->>'role','')='admin' OR u.email='drnaser@pharmahadi.com'));
$admin$;
CREATE TABLE public.products(id uuid PRIMARY KEY,barcode text,name text,active_ingredient text,dosage_form text,strength text,manufacturer text,category text,unit text,reorder_level numeric,customer_visible boolean,created_at timestamptz,updated_at timestamptz,sale_price numeric,parts_per_unit numeric,purchase_price numeric,active boolean,sale_currency text);
INSERT INTO public.products(id,name,active_ingredient,strength,dosage_form,customer_visible,active,purchase_price,sale_price,sale_currency,barcode) VALUES
 ('00000000-0000-4000-8000-000000000001','QA Visible USD','qa_ingredient_a','1 unit','synthetic',true,true,4.25,9,'USD','QA001'),
 ('00000000-0000-4000-8000-000000000002','QA Visible SYP','qa_ingredient_b','2 units','synthetic',true,true,12,20,'SYP','QA002'),
 ('00000000-0000-4000-8000-000000000003','QA Hidden','qa_ingredient_c','3 units','synthetic',false,true,8.5,15,'USD','QA003'),
 ('00000000-0000-4000-8000-000000000004','QA Archived','qa_ingredient_d','4 units','synthetic',true,false,3,7,'SYP','QA004');
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "public products read" ON public.products FOR SELECT TO anon,authenticated USING(customer_visible=true);
CREATE POLICY "Admins can insert products" ON public.products FOR INSERT TO authenticated WITH CHECK((auth.jwt()->'app_metadata'->>'role')='admin');
CREATE POLICY "Admins can update products" ON public.products FOR UPDATE TO authenticated USING((auth.jwt()->'app_metadata'->>'role')='admin') WITH CHECK((auth.jwt()->'app_metadata'->>'role')='admin');
CREATE POLICY "Admins can delete products" ON public.products FOR DELETE TO authenticated USING((auth.jwt()->'app_metadata'->>'role')='admin');
GRANT SELECT,INSERT,UPDATE,DELETE,REFERENCES,TRIGGER ON public.products TO anon,authenticated;
CREATE FUNCTION public.admin_get_products_page(p_limit integer DEFAULT 500,p_offset integer DEFAULT 0,p_customer_visible boolean DEFAULT NULL)
RETURNS SETOF public.products LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $page$
 SELECT p.* FROM public.products p WHERE public.is_admin() AND COALESCE(p.active,true)=true
 AND (p_customer_visible IS NULL OR p.customer_visible=p_customer_visible)
 ORDER BY p.name,p.id LIMIT LEAST(GREATEST(COALESCE(p_limit,500),1),500) OFFSET GREATEST(COALESCE(p_offset,0),0);
$page$;
REVOKE ALL ON FUNCTION public.admin_get_products_page(integer,integer,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_products_page(integer,integer,boolean) TO anon,authenticated;
NOTIFY pgrst,'reload schema';
DO $clear_private_settings$ BEGIN
 PERFORM set_config('pharmacy.qa_admin_password','',false);
 PERFORM set_config('pharmacy.qa_user_password','',false);
END;$clear_private_settings$;
COMMIT;
