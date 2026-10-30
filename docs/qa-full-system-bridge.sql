CREATE OR REPLACE FUNCTION public.supplier_preview_original_admin_bridge(
 p_actor uuid,p_kind text,p_name text,p_payload jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
 v_p pg_proc;v_call text;v_arg text;v_key text;v_type text;v_sql text;v_result jsonb;
 v_where text:='true';v_from text;v_expr text:='to_jsonb(t)';v_order text:='';
 v_action text:=coalesce(p_payload->>'action','select');v_col text;v_cols text;v_values text;
 v_filters jsonb:=coalesce(p_payload->'filters','[]'::jsonb);v_f jsonb;v_o jsonb;
 v_item jsonb;v_idx integer;v_claims text;v_op text;v_allowed boolean;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' OR p_actor IS DISTINCT FROM '15cdd7b6-cbfa-4607-9364-2787447f7680'::uuid THEN
  RAISE EXCEPTION 'Verified production administrator required' USING ERRCODE='42501'; END IF;
 IF p_name IS NULL OR p_name !~ '^[a-z_][a-z_0-9]*$' THEN RAISE EXCEPTION 'Invalid operation'; END IF;
 v_claims:=current_setting('request.jwt.claims',true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated')::text,true);
 PERFORM set_config('pharmacy_supplier_stage.verified_actor',p_actor::text,true);
 IF p_kind='rpc' THEN
  IF NOT (p_name LIKE 'admin\_%' ESCAPE '\' OR p_name IN ('get_admin_orders','adjust_stock','complete_sale_accounting_currency','production_healthcheck')) THEN
   RAISE EXCEPTION 'RPC not permitted'; END IF;
  SELECT p.* INTO STRICT v_p FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='pharmacy_supplier_stage' AND p.proname=p_name;
  v_call:=format('pharmacy_supplier_stage.%I(',p_name);
  FOR v_key IN SELECT jsonb_object_keys(coalesce(p_payload->'args','{}')) LOOP
   v_idx:=NULL;
   SELECT i INTO v_idx FROM generate_series(0,v_p.pronargs-1) i WHERE v_p.proargnames[i+1]=v_key;
   IF v_idx IS NULL THEN RAISE EXCEPTION 'Unknown argument: %',v_key; END IF;
   v_type:=format_type(v_p.proargtypes[v_idx],NULL);
   IF v_type IN ('jsonb','json') THEN v_arg:=format('($1->''args''->%L)::%s',v_key,v_type);
   ELSIF right(v_type,2)='[]' THEN v_arg:=format('(ARRAY(SELECT jsonb_array_elements_text($1->''args''->%L)))::%s',v_key,v_type);
   ELSE v_arg:=format('($1->''args''->>%L)::%s',v_key,v_type); END IF;
   v_call:=v_call||format('%I => %s,',v_key,v_arg);
  END LOOP;
  v_call:=rtrim(v_call,',')||')';
  IF v_p.proretset THEN v_sql:='SELECT coalesce(jsonb_agg(to_jsonb(r)),''[]''::jsonb) FROM '||v_call||' r';
  ELSE v_sql:='SELECT to_jsonb('||v_call||')'; END IF;
  EXECUTE v_sql INTO v_result USING p_payload;
 ELSIF p_kind='table' THEN
  IF p_name NOT IN ('products','batches','orders','prescriptions','offers','medicine_requests','audit_logs','sale_items','pos_shortcut_preferences') THEN RAISE EXCEPTION 'Table not permitted'; END IF;
  v_from:=format('pharmacy_supplier_stage.%I t',p_name);
  IF p_name='batches' THEN v_from:=v_from||' LEFT JOIN pharmacy_supplier_stage.products j ON j.id=t.product_id';v_expr:=v_expr||' || jsonb_build_object(''products'',to_jsonb(j))'; END IF;
  IF p_name='sale_items' THEN v_from:=v_from||' JOIN pharmacy_supplier_stage.sales j ON j.id=t.sale_id';v_expr:=v_expr||' || jsonb_build_object(''sales'',to_jsonb(j))'; END IF;
  FOR v_f IN SELECT value FROM jsonb_array_elements(v_filters) LOOP
   v_key:=v_f->>'column';
   IF p_name='sale_items' AND v_key='sales.created_at' THEN v_col:='j.created_at';v_type:='timestamptz';
   ELSE
    SELECT format_type(a.atttypid,NULL) INTO v_type FROM pg_attribute a
     WHERE a.attrelid=format('pharmacy_supplier_stage.%I',p_name)::regclass AND a.attname=v_key AND a.attnum>0 AND NOT a.attisdropped;
    IF v_type IS NULL THEN RAISE EXCEPTION 'Unknown filter column'; END IF;v_col:=format('t.%I',v_key);
   END IF;
   v_op:=v_f->>'op';
   IF v_op IN ('eq','neq','gt','gte','lt','lte') THEN
    v_where:=v_where||format(' AND %s %s %L::%s',v_col,CASE v_op WHEN 'eq' THEN '=' WHEN 'neq' THEN '<>' WHEN 'gt' THEN '>' WHEN 'gte' THEN '>=' WHEN 'lt' THEN '<' ELSE '<=' END,v_f->>'value',v_type);
   ELSIF v_op='in' THEN
    v_where:=v_where||format(' AND %s IN (SELECT jsonb_array_elements_text(%L::jsonb)::%s)',v_col,(v_f->'value')::text,v_type);
   ELSIF v_op='is' AND (v_f->'value'='null'::jsonb) THEN v_where:=v_where||' AND '||v_col||' IS NULL';
   ELSE RAISE EXCEPTION 'Unsupported filter'; END IF;
  END LOOP;
  IF p_name='pos_shortcut_preferences' THEN v_where:=v_where||format(' AND t.user_id=%L::uuid',p_actor); END IF;
  IF v_action='select' THEN
   FOR v_o IN SELECT value FROM jsonb_array_elements(coalesce(p_payload->'orders','[]')) LOOP
    v_key:=v_o->>'column';IF NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=format('pharmacy_supplier_stage.%I',p_name)::regclass AND a.attname=v_key AND a.attnum>0) THEN RAISE EXCEPTION 'Unknown order column'; END IF;
    v_order:=v_order||format('t.%I %s,',v_key,CASE WHEN coalesce((v_o->>'ascending')::boolean,true) THEN 'ASC' ELSE 'DESC' END);
   END LOOP;
   IF v_order<>'' THEN v_order:=' ORDER BY '||rtrim(v_order,','); END IF;
   v_sql:=format('SELECT coalesce(jsonb_agg(x.row),''[]''::jsonb) FROM (SELECT %s row FROM %s WHERE %s%s LIMIT %s OFFSET %s)x',v_expr,v_from,v_where,v_order,least(greatest(coalesce((p_payload->>'limit')::integer,5000),0),5000),greatest(coalesce((p_payload->>'offset')::integer,0),0));
   EXECUTE v_sql INTO v_result;
  ELSE
   v_allowed:=(p_name='products' AND v_action IN ('insert','update')) OR (p_name='batches' AND v_action IN ('insert','update')) OR (p_name IN ('prescriptions','medicine_requests') AND v_action IN ('insert','update')) OR (p_name='offers' AND v_action IN ('insert','update','delete')) OR (p_name='pos_shortcut_preferences' AND v_action='upsert');
   IF NOT v_allowed THEN RAISE EXCEPTION 'Table mutation not permitted'; END IF;
   IF v_action IN ('update','delete') AND jsonb_array_length(v_filters)=0 THEN RAISE EXCEPTION 'Mutation requires row filter'; END IF;
   v_item:=p_payload->'data';v_cols:='';v_values:='';v_arg:='';
   IF v_action<>'delete' THEN
    IF jsonb_typeof(v_item)<>'object' THEN RAISE EXCEPTION 'Mutation must contain one object'; END IF;
    IF p_name='pos_shortcut_preferences' AND v_item->>'user_id' IS DISTINCT FROM p_actor::text THEN RAISE EXCEPTION 'Shortcut owner mismatch'; END IF;
    FOR v_key IN SELECT jsonb_object_keys(v_item) LOOP
     IF NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=format('pharmacy_supplier_stage.%I',p_name)::regclass AND a.attname=v_key AND a.attnum>0 AND NOT a.attisdropped) THEN RAISE EXCEPTION 'Unknown write column'; END IF;
     v_cols:=v_cols||format('%I,',v_key);v_values:=v_values||format('r.%I,',v_key);v_arg:=v_arg||format('%I=r.%I,',v_key,v_key);
    END LOOP;
    v_cols:=rtrim(v_cols,',');v_values:=rtrim(v_values,',');v_arg:=rtrim(v_arg,',');
   END IF;
   IF v_action IN ('insert','upsert') THEN
    v_sql:=format('INSERT INTO pharmacy_supplier_stage.%I (%s) SELECT %s FROM jsonb_populate_record(NULL::pharmacy_supplier_stage.%I,$1) r',p_name,v_cols,v_values,p_name);
    IF v_action='upsert' THEN v_sql:=v_sql||' ON CONFLICT (user_id) DO UPDATE SET items=excluded.items,updated_at=excluded.updated_at'; END IF;
   ELSIF v_action='update' THEN v_sql:=format('UPDATE pharmacy_supplier_stage.%I t SET %s FROM jsonb_populate_record(NULL::pharmacy_supplier_stage.%I,$1) r WHERE %s',p_name,v_arg,p_name,v_where);
   ELSE v_sql:=format('DELETE FROM pharmacy_supplier_stage.%I t WHERE %s',p_name,v_where); END IF;
   EXECUTE v_sql USING v_item;v_result:='null'::jsonb;
  END IF;
 ELSE RAISE EXCEPTION 'Unknown operation kind'; END IF;
 PERFORM set_config('request.jwt.claims',coalesce(v_claims,''),true);
 PERFORM set_config('pharmacy_supplier_stage.verified_actor','',true);
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.supplier_preview_original_admin_bridge(uuid,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.supplier_preview_original_admin_bridge(uuid,text,text,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';
