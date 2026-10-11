-- Purchasing intent only. Inventory identity remains owned by Inventory.
ALTER TABLE {{schema}}.accounts ADD CONSTRAINT purchasing_account_company_anchor UNIQUE(id,company_id);

CREATE TABLE {{schema}}.purchasing_suppliers (
  company_id uuid NOT NULL REFERENCES {{schema}}.companies(id),
  id uuid NOT NULL,
  name text NOT NULL CHECK(length(name) BETWEEN 1 AND 200 AND name=btrim(name) AND name !~ '[[:cntrl:]]'),
  ordering_reference text CHECK(ordering_reference IS NULL OR (length(ordering_reference) BETWEEN 1 AND 64 AND ordering_reference=btrim(ordering_reference) AND ordering_reference !~ '[[:cntrl:]]')),
  status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','retired')),
  version bigint NOT NULL DEFAULT 1 CHECK(version BETWEEN 1 AND 9007199254740991),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  changed_by uuid NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  retired_by uuid,
  retired_at timestamptz,
  last_operation_id uuid NOT NULL,
  last_kind text NOT NULL CHECK(last_kind IN ('supplier_create','supplier_edit','supplier_retire')),
  PRIMARY KEY(company_id,id),
  FOREIGN KEY(created_by,company_id) REFERENCES {{schema}}.accounts(id,company_id),
  FOREIGN KEY(changed_by,company_id) REFERENCES {{schema}}.accounts(id,company_id),
  FOREIGN KEY(retired_by,company_id) REFERENCES {{schema}}.accounts(id,company_id),
  CHECK(changed_at>=created_at),
  CHECK((status='active' AND retired_by IS NULL AND retired_at IS NULL) OR (status='retired' AND retired_by IS NOT NULL AND retired_at=changed_at AND retired_by=changed_by))
);
CREATE INDEX purchasing_supplier_page ON {{schema}}.purchasing_suppliers(company_id,status,id);

CREATE TABLE {{schema}}.purchasing_orders (
  company_id uuid NOT NULL,
  id uuid NOT NULL,
  location_id uuid NOT NULL,
  reference text NOT NULL CHECK(length(reference) BETWEEN 1 AND 64 AND reference=btrim(reference) AND reference !~ '[[:cntrl:]]'),
  reference_key text GENERATED ALWAYS AS (translate(reference,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')) STORED NOT NULL,
  supplier_id uuid NOT NULL,
  supplier_version bigint NOT NULL CHECK(supplier_version BETWEEN 1 AND 9007199254740991),
  supplier_name text NOT NULL CHECK(length(supplier_name) BETWEEN 1 AND 200 AND supplier_name=btrim(supplier_name) AND supplier_name !~ '[[:cntrl:]]'),
  supplier_reference text CHECK(supplier_reference IS NULL OR (length(supplier_reference) BETWEEN 1 AND 64 AND supplier_reference=btrim(supplier_reference) AND supplier_reference !~ '[[:cntrl:]]')),
  status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','issued','closed','cancelled')),
  version bigint NOT NULL DEFAULT 1 CHECK(version BETWEEN 1 AND 9007199254740991),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  changed_by uuid NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  issued_by uuid,
  issued_at timestamptz,
  issue_operation_id uuid,
  terminal_by uuid,
  terminal_at timestamptz,
  terminal_reason text CHECK(terminal_reason IS NULL OR (length(terminal_reason) BETWEEN 1 AND 500 AND terminal_reason=btrim(terminal_reason) AND terminal_reason !~ '[[:cntrl:]]')),
  terminal_operation_id uuid,
  last_operation_id uuid NOT NULL,
  last_kind text NOT NULL CHECK(last_kind IN ('order_create','order_save','order_issue','order_cancel','order_close')),
  PRIMARY KEY(company_id,id),
  UNIQUE(company_id,id,location_id),
  CONSTRAINT purchasing_order_reference_unique UNIQUE(company_id,location_id,reference_key),
  FOREIGN KEY(location_id,company_id) REFERENCES {{schema}}.locations(id,company_id),
  FOREIGN KEY(company_id,supplier_id) REFERENCES {{schema}}.purchasing_suppliers(company_id,id),
  FOREIGN KEY(created_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY(changed_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY(issued_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY(terminal_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  CHECK(changed_at>=created_at),
  CHECK((issued_by IS NULL AND issued_at IS NULL AND issue_operation_id IS NULL) OR (issued_by IS NOT NULL AND issued_at IS NOT NULL AND issue_operation_id IS NOT NULL AND issued_at>=created_at)),
  CHECK((status IN ('draft','issued') AND terminal_by IS NULL AND terminal_at IS NULL AND terminal_reason IS NULL AND terminal_operation_id IS NULL) OR (status IN ('closed','cancelled') AND terminal_by IS NOT NULL AND terminal_at=changed_at AND terminal_by=changed_by AND terminal_reason IS NOT NULL AND terminal_operation_id IS NOT NULL)),
  CHECK((status='draft' AND issued_at IS NULL) OR (status IN ('issued','closed') AND issued_at IS NOT NULL) OR status='cancelled'),
  CHECK(terminal_at IS NULL OR terminal_at>=COALESCE(issued_at,created_at))
  ,CHECK(last_kind<>'order_issue' OR (issue_operation_id=last_operation_id AND issued_by=changed_by AND issued_at=changed_at))
  ,CHECK(last_kind NOT IN ('order_cancel','order_close') OR terminal_operation_id=last_operation_id)
);
CREATE INDEX purchasing_order_page ON {{schema}}.purchasing_orders(company_id,location_id,status,id);
CREATE INDEX purchasing_order_supplier_page ON {{schema}}.purchasing_orders(company_id,location_id,supplier_id,id);

CREATE TABLE {{schema}}.purchasing_order_lines (
  company_id uuid NOT NULL,
  order_id uuid NOT NULL,
  location_id uuid NOT NULL,
  id uuid NOT NULL,
  position integer NOT NULL CHECK(position BETWEEN 1 AND 50),
  article_id uuid NOT NULL,
  article_version bigint NOT NULL CHECK(article_version BETWEEN 1 AND 9007199254740991),
  sku text NOT NULL CHECK(length(sku) BETWEEN 1 AND 64 AND sku=btrim(sku) AND sku !~ '[[:cntrl:]]'),
  name text NOT NULL CHECK(length(name) BETWEEN 1 AND 120 AND name=btrim(name) AND name !~ '[[:cntrl:]]'),
  unit text NOT NULL CHECK(length(unit) BETWEEN 1 AND 32 AND unit=btrim(unit) AND unit !~ '[[:cntrl:]]'),
  quantity_scaled bigint NOT NULL CHECK(quantity_scaled BETWEEN 1 AND 999999999999999),
  PRIMARY KEY(company_id,order_id,id),
  UNIQUE(company_id,order_id,article_id),
  UNIQUE(company_id,order_id,position),
  FOREIGN KEY(company_id,order_id,location_id) REFERENCES {{schema}}.purchasing_orders(company_id,id,location_id),
  FOREIGN KEY(article_id,company_id) REFERENCES {{schema}}.articles(id,company_id)
);

CREATE TABLE {{schema}}.purchasing_commands (
  company_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  supplier_id uuid,
  order_id uuid,
  location_id uuid,
  actor_id uuid NOT NULL,
  kind text NOT NULL CHECK(kind IN ('supplier_create','supplier_edit','supplier_retire','order_create','order_save','order_issue','order_cancel','order_close')),
  expected_version bigint CHECK(expected_version BETWEEN 1 AND 9007199254740991),
  applied_version bigint NOT NULL CHECK(applied_version BETWEEN 1 AND 9007199254740991),
  response_status integer NOT NULL CHECK(response_status IN (200,201)),
  payload jsonb NOT NULL CHECK(jsonb_typeof(payload)='object' AND octet_length(payload::text)<=262144),
  result jsonb NOT NULL CHECK(jsonb_typeof(result)='object' AND octet_length(result::text)<=524288),
  accepted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(company_id,operation_id),
  UNIQUE(company_id,supplier_id,applied_version),
  UNIQUE(company_id,order_id,applied_version),
  UNIQUE(company_id,operation_id,supplier_id,actor_id,kind,applied_version),
  UNIQUE(company_id,operation_id,order_id,location_id,actor_id,kind,applied_version),
  FOREIGN KEY(company_id,supplier_id) REFERENCES {{schema}}.purchasing_suppliers(company_id,id),
  FOREIGN KEY(company_id,order_id,location_id) REFERENCES {{schema}}.purchasing_orders(company_id,id,location_id),
  FOREIGN KEY(actor_id,company_id) REFERENCES {{schema}}.accounts(id,company_id),
  FOREIGN KEY(actor_id,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  CHECK((kind LIKE 'supplier_%' AND supplier_id IS NOT NULL AND order_id IS NULL AND location_id IS NULL) OR (kind LIKE 'order_%' AND order_id IS NOT NULL AND supplier_id IS NULL AND location_id IS NOT NULL)),
  CHECK((kind IN ('supplier_create','order_create') AND expected_version IS NULL AND applied_version=1 AND response_status=201) OR (kind NOT IN ('supplier_create','order_create') AND expected_version IS NOT NULL AND applied_version=expected_version+1 AND response_status=200)),
  CHECK(payload ? 'operationId' AND payload->>'operationId'=operation_id::text AND result ? 'replayed' AND result->>'replayed'='false'),
  CHECK((expected_version IS NULL AND NOT payload ? 'expectedVersion') OR (expected_version IS NOT NULL AND payload ? 'expectedVersion' AND (payload->>'expectedVersion')::bigint=expected_version))
);
ALTER TABLE {{schema}}.purchasing_suppliers ADD CONSTRAINT purchasing_supplier_receipt FOREIGN KEY(company_id,last_operation_id,id,changed_by,last_kind,version) REFERENCES {{schema}}.purchasing_commands(company_id,operation_id,supplier_id,actor_id,kind,applied_version) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE {{schema}}.purchasing_orders ADD CONSTRAINT purchasing_order_receipt FOREIGN KEY(company_id,last_operation_id,id,location_id,changed_by,last_kind,version) REFERENCES {{schema}}.purchasing_commands(company_id,operation_id,order_id,location_id,actor_id,kind,applied_version) DEFERRABLE INITIALLY DEFERRED;

CREATE FUNCTION {{schema}}.purchasing_time(t timestamptz) RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT to_char(t AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') $$;
CREATE FUNCTION {{schema}}.purchasing_supplier_json(c uuid,i uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('id',id,'companyId',company_id,'name',name,'orderingReference',ordering_reference,'status',status,'version',version,'createdBy',created_by,'createdAt',{{schema}}.purchasing_time(created_at),'changedBy',changed_by,'changedAt',{{schema}}.purchasing_time(changed_at),'retiredBy',retired_by,'retiredAt',{{schema}}.purchasing_time(retired_at)) FROM {{schema}}.purchasing_suppliers WHERE company_id=c AND id=i
$$;
CREATE FUNCTION {{schema}}.purchasing_order_json(c uuid,i uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('id',id,'companyId',company_id,'locationId',location_id,'reference',reference,'supplier',jsonb_build_object('id',supplier_id,'version',supplier_version,'name',supplier_name,'orderingReference',supplier_reference),'status',status,'version',version,'createdBy',created_by,'createdAt',{{schema}}.purchasing_time(created_at),'changedBy',changed_by,'changedAt',{{schema}}.purchasing_time(changed_at),'issuedBy',issued_by,'issuedAt',{{schema}}.purchasing_time(issued_at),'terminalBy',terminal_by,'terminalAt',{{schema}}.purchasing_time(terminal_at),'reason',terminal_reason,'lines',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',l.id,'position',position,'articleId',article_id,'articleVersion',article_version,'sku',sku,'name',l.name,'unit',unit,'quantity',(quantity_scaled/1000)::text||'.'||lpad((quantity_scaled%1000)::text,3,'0')) ORDER BY position) FROM {{schema}}.purchasing_order_lines l WHERE l.company_id=c AND l.order_id=i),'[]'::jsonb)) FROM {{schema}}.purchasing_orders WHERE company_id=c AND id=i
$$;

CREATE FUNCTION {{schema}}.purchasing_aggregate_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE allowed text[];
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Purchasing evidence retained' USING ERRCODE='23514'; END IF;
 IF TG_OP='INSERT' THEN
   IF NEW.version<>1 OR NEW.last_kind<>(CASE WHEN TG_TABLE_NAME='purchasing_suppliers' THEN 'supplier_create' ELSE 'order_create' END) OR NEW.status<>(CASE WHEN TG_TABLE_NAME='purchasing_suppliers' THEN 'active' ELSE 'draft' END) THEN RAISE EXCEPTION 'Invalid creation' USING ERRCODE='23514'; END IF;
   RETURN NEW;
 END IF;
 IF NEW.version<>OLD.version+1 OR NEW.last_operation_id=OLD.last_operation_id OR NEW.changed_at<OLD.changed_at THEN RAISE EXCEPTION 'Invalid version transition' USING ERRCODE='23514'; END IF;
 IF TG_TABLE_NAME='purchasing_suppliers' THEN
   IF OLD.status<>'active' OR NEW.last_kind NOT IN ('supplier_edit','supplier_retire') OR (NEW.last_kind='supplier_edit' AND NEW.status<>'active') OR (NEW.last_kind='supplier_retire' AND (NEW.status<>'retired' OR NEW.name<>OLD.name OR NEW.ordering_reference IS DISTINCT FROM OLD.ordering_reference)) THEN RAISE EXCEPTION 'Invalid Supplier lifecycle' USING ERRCODE='23514'; END IF;
   allowed=ARRAY['name','ordering_reference','status','version','changed_by','changed_at','retired_by','retired_at','last_kind','last_operation_id'];
 ELSE
   IF NOT ((OLD.status='draft' AND NEW.status='draft' AND NEW.last_kind='order_save') OR (OLD.status='draft' AND NEW.status='issued' AND NEW.last_kind='order_issue') OR (OLD.status IN ('draft','issued') AND NEW.status='cancelled' AND NEW.last_kind='order_cancel') OR (OLD.status='issued' AND NEW.status='closed' AND NEW.last_kind='order_close')) THEN RAISE EXCEPTION 'Invalid Order lifecycle' USING ERRCODE='23514'; END IF;
   allowed=ARRAY['reference_key','status','version','changed_by','changed_at','last_operation_id','last_kind'];
   IF NEW.last_kind='order_save' THEN allowed=allowed||ARRAY['reference','reference_key','supplier_id','supplier_version','supplier_name','supplier_reference'];
   ELSIF NEW.last_kind='order_issue' THEN allowed=allowed||ARRAY['issued_by','issued_at','issue_operation_id'];
   ELSE allowed=allowed||ARRAY['terminal_by','terminal_at','terminal_reason','terminal_operation_id']; END IF;
 END IF;
 IF (to_jsonb(NEW)-allowed) IS DISTINCT FROM (to_jsonb(OLD)-allowed) THEN RAISE EXCEPTION 'Immutable Purchasing content' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER purchasing_supplier_guard BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.purchasing_suppliers FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_aggregate_guard();
CREATE TRIGGER purchasing_order_guard BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.purchasing_orders FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_aggregate_guard();
CREATE FUNCTION {{schema}}.purchasing_line_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c uuid; i uuid; state text;
BEGIN
 IF TG_OP='UPDATE' THEN RAISE EXCEPTION 'Replace draft lines only' USING ERRCODE='23514'; END IF;
 IF TG_OP='DELETE' THEN c=OLD.company_id;i=OLD.order_id; ELSE c=NEW.company_id;i=NEW.order_id; END IF;
 SELECT status INTO state FROM {{schema}}.purchasing_orders WHERE company_id=c AND id=i FOR UPDATE;
 IF state IS DISTINCT FROM 'draft' THEN RAISE EXCEPTION 'Frozen Order lines' USING ERRCODE='23514'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE TRIGGER purchasing_line_guard BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.purchasing_order_lines FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_line_guard();
CREATE FUNCTION {{schema}}.purchasing_command_immutable() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Immutable Purchasing receipt' USING ERRCODE='23514'; END $$;
CREATE TRIGGER purchasing_command_immutable BEFORE UPDATE OR DELETE ON {{schema}}.purchasing_commands FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_command_immutable();

CREATE FUNCTION {{schema}}.purchasing_final_state() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c uuid; i uuid; supplier boolean; d jsonb; r {{schema}}.purchasing_commands%ROWTYPE; n bigint; v bigint; bytes bigint; l jsonb; op uuid; j jsonb;
BEGIN
 j=COALESCE(to_jsonb(NEW),to_jsonb(OLD));
 c=(j->>'company_id')::uuid;
 supplier=TG_TABLE_NAME='purchasing_suppliers' OR (TG_TABLE_NAME='purchasing_commands' AND j->>'supplier_id' IS NOT NULL);
 IF supplier THEN
  i=(CASE WHEN TG_TABLE_NAME='purchasing_commands' THEN j->>'supplier_id' ELSE j->>'id' END)::uuid;
  d={{schema}}.purchasing_supplier_json(c,i);
  SELECT last_operation_id INTO op FROM {{schema}}.purchasing_suppliers WHERE company_id=c AND id=i;
  SELECT count(*) INTO n FROM {{schema}}.purchasing_commands WHERE company_id=c AND supplier_id=i;
 ELSE
  IF TG_TABLE_NAME IN ('purchasing_order_lines','purchasing_commands') THEN i=(j->>'order_id')::uuid; ELSE i=(j->>'id')::uuid; END IF;
  d={{schema}}.purchasing_order_json(c,i);
  SELECT last_operation_id INTO op FROM {{schema}}.purchasing_orders WHERE company_id=c AND id=i;
  SELECT count(*) INTO n FROM {{schema}}.purchasing_commands WHERE company_id=c AND order_id=i;
  IF jsonb_array_length(d->'lines')>50 OR ((d->>'issuedAt') IS NOT NULL AND jsonb_array_length(d->'lines')=0) OR EXISTS(SELECT 1 FROM (SELECT position,row_number() OVER(ORDER BY position) actual FROM {{schema}}.purchasing_order_lines WHERE company_id=c AND order_id=i) p WHERE position<>actual) THEN RAISE EXCEPTION 'Invalid Order line collection' USING ERRCODE='23514',CONSTRAINT='purchasing_document_valid'; END IF;
  bytes=octet_length(i::text)+octet_length(c::text)+octet_length(d->>'locationId')+octet_length(d->>'reference')+octet_length(d->'supplier'->>'id')+octet_length(d->'supplier'->>'version')+octet_length(d->'supplier'->>'name')+octet_length(COALESCE(d->'supplier'->>'orderingReference',''));
  FOR l IN SELECT value FROM jsonb_array_elements(d->'lines') LOOP bytes=bytes+octet_length(l->>'id')+octet_length(l->>'position')+octet_length(l->>'articleId')+octet_length(l->>'articleVersion')+octet_length(l->>'sku')+octet_length(l->>'name')+octet_length(l->>'unit')+octet_length(l->>'quantity'); END LOOP;
  IF bytes>98304 THEN RAISE EXCEPTION 'Order document byte bound' USING ERRCODE='23514',CONSTRAINT='purchasing_document_valid'; END IF;
 END IF;
 SELECT * INTO r FROM {{schema}}.purchasing_commands WHERE company_id=c AND operation_id=op;
 v=(d->>'version')::bigint;
 IF d IS NULL OR r.operation_id IS NULL OR n<>v OR r.applied_version<>v OR r.result->(CASE WHEN supplier THEN 'supplier' ELSE 'order' END) IS DISTINCT FROM d THEN RAISE EXCEPTION 'Incomplete Purchasing receipt/evidence chain' USING ERRCODE='23514',CONSTRAINT='purchasing_receipt_valid'; END IF;
 IF TG_TABLE_NAME='purchasing_commands' THEN
  IF NEW.applied_version>v OR NEW.result->(CASE WHEN supplier THEN 'supplier' ELSE 'order' END)->>'id' IS DISTINCT FROM i::text OR NEW.result->(CASE WHEN supplier THEN 'supplier' ELSE 'order' END)->>'companyId' IS DISTINCT FROM c::text OR (NEW.result->(CASE WHEN supplier THEN 'supplier' ELSE 'order' END)->>'version')::bigint IS DISTINCT FROM NEW.applied_version OR (NOT supplier AND NEW.result->'order'->>'locationId' IS DISTINCT FROM NEW.location_id::text) THEN RAISE EXCEPTION 'Invalid receipt result scope' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER purchasing_supplier_final AFTER INSERT OR UPDATE ON {{schema}}.purchasing_suppliers DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_final_state();
CREATE CONSTRAINT TRIGGER purchasing_order_final AFTER INSERT OR UPDATE ON {{schema}}.purchasing_orders DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_final_state();
CREATE CONSTRAINT TRIGGER purchasing_line_final AFTER INSERT OR DELETE ON {{schema}}.purchasing_order_lines DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_final_state();
CREATE CONSTRAINT TRIGGER purchasing_command_final AFTER INSERT ON {{schema}}.purchasing_commands DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_final_state();
