-- Purchasing declarations only: no physical Stock effects or historical backfill.
CREATE TABLE {{schema}}.purchasing_delivery_revisions (
 company_id uuid NOT NULL, location_id uuid NOT NULL, order_id uuid NOT NULL,
 delivery_id uuid NOT NULL, revision bigint NOT NULL CHECK(revision BETWEEN 1 AND 9007199254740991),
 ledger_version bigint NOT NULL CHECK(ledger_version BETWEEN 1 AND 9007199254740991),
 kind text NOT NULL CHECK(kind IN ('delivery_declare','delivery_correct','delivery_void')),
 local_reference text NOT NULL CHECK(length(local_reference) BETWEEN 1 AND 64 AND local_reference=btrim(local_reference) AND local_reference !~ '[[:cntrl:]]'),
 reference_key text GENERATED ALWAYS AS (translate(local_reference,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')) STORED NOT NULL,
 reason text CHECK(reason IS NULL OR (length(reason) BETWEEN 1 AND 500 AND reason=btrim(reason) AND reason !~ '[[:cntrl:]]')),
 actor_id uuid NOT NULL, recorded_at timestamptz NOT NULL DEFAULT clock_timestamp() CHECK(isfinite(recorded_at)), operation_id uuid NOT NULL,
 PRIMARY KEY(company_id,order_id,delivery_id,revision),
 UNIQUE(company_id,order_id,ledger_version),
 UNIQUE(company_id,operation_id),
 UNIQUE(company_id,order_id,location_id,delivery_id,revision),
 UNIQUE(company_id,order_id,location_id,delivery_id,revision,ledger_version,actor_id,kind,operation_id),
 FOREIGN KEY(company_id,order_id,location_id) REFERENCES {{schema}}.purchasing_orders(company_id,id,location_id),
 FOREIGN KEY(actor_id,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
 CHECK(((kind='delivery_declare' AND revision=1) OR (kind IN ('delivery_correct','delivery_void') AND revision>1 AND reason IS NOT NULL)) IS TRUE)
);
CREATE UNIQUE INDEX purchasing_delivery_reference_unique ON {{schema}}.purchasing_delivery_revisions(company_id,order_id,reference_key) WHERE revision=1;
CREATE INDEX purchasing_delivery_lookup ON {{schema}}.purchasing_delivery_revisions(company_id,order_id,delivery_id,revision DESC);

CREATE TABLE {{schema}}.purchasing_delivery_revision_lines (
 company_id uuid NOT NULL, location_id uuid NOT NULL, order_id uuid NOT NULL,
 delivery_id uuid NOT NULL, revision bigint NOT NULL, order_line_id uuid NOT NULL,
 quantity_scaled bigint NOT NULL CHECK(quantity_scaled BETWEEN 1 AND 999999999999999),
 PRIMARY KEY(company_id,order_id,delivery_id,revision,order_line_id),
 FOREIGN KEY(company_id,order_id,location_id,delivery_id,revision) REFERENCES {{schema}}.purchasing_delivery_revisions(company_id,order_id,location_id,delivery_id,revision),
 FOREIGN KEY(company_id,order_id,location_id) REFERENCES {{schema}}.purchasing_orders(company_id,id,location_id),
 FOREIGN KEY(company_id,order_id,order_line_id) REFERENCES {{schema}}.purchasing_order_lines(company_id,order_id,id)
);

CREATE TABLE {{schema}}.purchasing_delivery_commands (
 company_id uuid NOT NULL, operation_id uuid NOT NULL, location_id uuid NOT NULL, order_id uuid NOT NULL, delivery_id uuid NOT NULL,
 actor_id uuid NOT NULL, kind text NOT NULL CHECK(kind IN ('delivery_declare','delivery_correct','delivery_void')),
 expected_order_version bigint NOT NULL CHECK(expected_order_version BETWEEN 1 AND 9007199254740991),
 expected_ledger_version bigint NOT NULL CHECK(expected_ledger_version BETWEEN 0 AND 9007199254740990),
 expected_revision bigint CHECK(expected_revision BETWEEN 1 AND 9007199254740990),
 revision bigint NOT NULL, ledger_version bigint NOT NULL,
 response_status integer NOT NULL CHECK(response_status IN (200,201)),
 payload jsonb NOT NULL CHECK((jsonb_typeof(payload)='object' AND octet_length(payload::text)<=32768) IS TRUE),
 result jsonb NOT NULL CHECK((jsonb_typeof(result)='object' AND octet_length(result::text)<=65536) IS TRUE),
 accepted_at timestamptz NOT NULL DEFAULT clock_timestamp() CHECK(isfinite(accepted_at)),
 PRIMARY KEY(company_id,operation_id),
 UNIQUE(company_id,order_id,location_id,delivery_id,revision,ledger_version,actor_id,kind,operation_id),
 FOREIGN KEY(company_id,order_id,location_id,delivery_id,revision,ledger_version,actor_id,kind,operation_id)
 REFERENCES {{schema}}.purchasing_delivery_revisions(company_id,order_id,location_id,delivery_id,revision,ledger_version,actor_id,kind,operation_id) DEFERRABLE INITIALLY DEFERRED,
 CHECK((ledger_version=expected_ledger_version+1 AND ((kind='delivery_declare' AND expected_revision IS NULL AND revision=1 AND response_status=201) OR (kind IN ('delivery_correct','delivery_void') AND expected_revision IS NOT NULL AND revision=expected_revision+1 AND response_status=200))) IS TRUE)
);
ALTER TABLE {{schema}}.purchasing_delivery_revisions ADD CONSTRAINT purchasing_delivery_receipt
 FOREIGN KEY(company_id,order_id,location_id,delivery_id,revision,ledger_version,actor_id,kind,operation_id)
 REFERENCES {{schema}}.purchasing_delivery_commands(company_id,order_id,location_id,delivery_id,revision,ledger_version,actor_id,kind,operation_id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE {{schema}}.purchasing_delivery_terminal_snapshots (
 company_id uuid NOT NULL, location_id uuid NOT NULL, order_id uuid NOT NULL,
 operation_id uuid NOT NULL, order_version bigint NOT NULL CHECK(order_version BETWEEN 1 AND 9007199254740991),
 actor_id uuid NOT NULL, kind text NOT NULL CHECK(kind IN ('order_close','order_cancel')),
 terminal_at timestamptz NOT NULL CHECK(isfinite(terminal_at)),
 ledger_version bigint NOT NULL CHECK(ledger_version BETWEEN 0 AND 9007199254740991),
 summary jsonb NOT NULL CHECK((jsonb_typeof(summary)='object' AND octet_length(summary::text)<=32768) IS TRUE),
 PRIMARY KEY(company_id,order_id),
 FOREIGN KEY(company_id,order_id,location_id) REFERENCES {{schema}}.purchasing_orders(company_id,id,location_id),
 FOREIGN KEY(actor_id,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
 FOREIGN KEY(company_id,operation_id,order_id,location_id,actor_id,kind,order_version)
 REFERENCES {{schema}}.purchasing_commands(company_id,operation_id,order_id,location_id,actor_id,kind,applied_version) DEFERRABLE INITIALLY DEFERRED
);

CREATE FUNCTION {{schema}}.purchasing_delivery_quantity(q numeric) RETURNS text LANGUAGE sql IMMUTABLE STRICT AS $$
 SELECT trunc(q/1000)::text||'.'||lpad(mod(q,1000)::text,3,'0')
$$;
CREATE FUNCTION {{schema}}.purchasing_delivery_summary(c uuid,o uuid,b bigint) RETURNS jsonb LANGUAGE sql STABLE AS $$
 WITH latest AS (
  SELECT DISTINCT ON (delivery_id) delivery_id,revision,kind FROM {{schema}}.purchasing_delivery_revisions
  WHERE company_id=c AND order_id=o AND ledger_version<=b ORDER BY delivery_id,revision DESC
 ), totals AS (
  SELECT l.order_line_id,sum(l.quantity_scaled::numeric) q FROM latest r JOIN {{schema}}.purchasing_delivery_revision_lines l
  ON l.company_id=c AND l.order_id=o AND l.delivery_id=r.delivery_id AND l.revision=r.revision
  WHERE r.kind<>'delivery_void' GROUP BY l.order_line_id
 ) SELECT jsonb_build_object('orderId',o,'ledgerVersion',b,
 'declarationCount',(SELECT count(*) FROM {{schema}}.purchasing_delivery_revisions WHERE company_id=c AND order_id=o AND revision=1 AND ledger_version<=b),
 'lines',COALESCE((SELECT jsonb_agg(jsonb_build_object('orderLineId',l.id,
 'orderedQuantity',{{schema}}.purchasing_delivery_quantity(l.quantity_scaled),
 'effectiveDelivered',{{schema}}.purchasing_delivery_quantity(COALESCE(t.q,0)),
 'recordedRemainder',{{schema}}.purchasing_delivery_quantity(greatest(l.quantity_scaled-COALESCE(t.q,0),0)),
 'overdelivery',{{schema}}.purchasing_delivery_quantity(greatest(COALESCE(t.q,0)-l.quantity_scaled,0))) ORDER BY l.position)
 FROM {{schema}}.purchasing_order_lines l LEFT JOIN totals t ON t.order_line_id=l.id WHERE l.company_id=c AND l.order_id=o AND EXISTS(SELECT 1 FROM {{schema}}.purchasing_orders po WHERE po.company_id=c AND po.id=o AND po.issued_at IS NOT NULL)),'[]'::jsonb))
$$;
CREATE FUNCTION {{schema}}.purchasing_delivery_revision_json(c uuid,o uuid,d uuid,v bigint) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('deliveryId',delivery_id,'orderId',order_id,'locationId',location_id,'revision',revision,'ledgerVersion',ledger_version,'kind',kind,
 'localReference',local_reference,'reason',reason,'actorId',actor_id,'recordedAt',{{schema}}.purchasing_time(recorded_at),'operationId',operation_id,
 'lines',COALESCE((SELECT jsonb_agg(jsonb_build_object('orderLineId',order_line_id,'quantity',{{schema}}.purchasing_delivery_quantity(quantity_scaled)) ORDER BY order_line_id)
 FROM {{schema}}.purchasing_delivery_revision_lines l WHERE l.company_id=c AND l.order_id=o AND l.delivery_id=d AND l.revision=v),'[]'::jsonb))
 FROM {{schema}}.purchasing_delivery_revisions WHERE company_id=c AND order_id=o AND delivery_id=d AND revision=v
$$;

-- Both insertion directions acquire the same existing Company writer lock.
CREATE FUNCTION {{schema}}.purchasing_operation_namespace() RETURNS trigger LANGUAGE plpgsql VOLATILE AS $$
BEGIN
 -- A waiting advisory lock must be followed by a fresh statement snapshot.
 -- Repeatable-read snapshots could otherwise miss the other table's commit.
 IF current_setting('transaction_isolation') IS DISTINCT FROM 'read committed' THEN
  RAISE EXCEPTION 'Purchasing receipt inserts require read committed isolation' USING ERRCODE='23514',CONSTRAINT='purchasing_operation_isolation';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtext('storeos_platform:'||TG_TABLE_SCHEMA||':'||NEW.company_id::text));
 IF (TG_TABLE_NAME='purchasing_commands' AND EXISTS(SELECT 1 FROM {{schema}}.purchasing_delivery_commands WHERE company_id=NEW.company_id AND operation_id=NEW.operation_id))
 OR (TG_TABLE_NAME='purchasing_delivery_commands' AND EXISTS(SELECT 1 FROM {{schema}}.purchasing_commands WHERE company_id=NEW.company_id AND operation_id=NEW.operation_id)) THEN
  RAISE EXCEPTION 'Purchasing operation identity already bound' USING ERRCODE='23505',CONSTRAINT='purchasing_operation_namespace';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER purchasing_operation_namespace BEFORE INSERT ON {{schema}}.purchasing_commands FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_operation_namespace();
CREATE TRIGGER purchasing_operation_namespace BEFORE INSERT ON {{schema}}.purchasing_delivery_commands FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_operation_namespace();

CREATE FUNCTION {{schema}}.purchasing_delivery_insert_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE o {{schema}}.purchasing_orders%ROWTYPE; r {{schema}}.purchasing_delivery_revisions%ROWTYPE; n bigint; v bigint;
BEGIN
 SELECT * INTO o FROM {{schema}}.purchasing_orders WHERE company_id=NEW.company_id AND id=NEW.order_id AND location_id=NEW.location_id FOR UPDATE;
 IF o.id IS NULL OR o.issued_at IS NULL THEN RAISE EXCEPTION 'Issued scoped Order required' USING ERRCODE='23514'; END IF;
 IF TG_TABLE_NAME='purchasing_delivery_revisions' THEN
  SELECT COALESCE(max(ledger_version),0) INTO n FROM {{schema}}.purchasing_delivery_revisions WHERE company_id=NEW.company_id AND order_id=NEW.order_id;
  SELECT * INTO r FROM {{schema}}.purchasing_delivery_revisions WHERE company_id=NEW.company_id AND order_id=NEW.order_id AND delivery_id=NEW.delivery_id ORDER BY revision DESC LIMIT 1;
  IF NEW.recorded_at<o.issued_at OR NEW.ledger_version IS DISTINCT FROM n+1 OR NEW.revision IS DISTINCT FROM COALESCE(r.revision,0)+1
   OR (NEW.revision=1 AND o.status IS DISTINCT FROM 'issued')
   OR (r.revision IS NOT NULL AND (NEW.local_reference IS DISTINCT FROM r.local_reference OR NEW.recorded_at<r.recorded_at)) THEN
   RAISE EXCEPTION 'Invalid delivery sequence or lifecycle' USING ERRCODE='23514';
  END IF;
 ELSIF TG_TABLE_NAME='purchasing_delivery_revision_lines' THEN
  SELECT * INTO r FROM {{schema}}.purchasing_delivery_revisions WHERE company_id=NEW.company_id AND order_id=NEW.order_id AND delivery_id=NEW.delivery_id AND revision=NEW.revision;
  IF r.location_id IS DISTINCT FROM NEW.location_id OR r.kind IS NOT DISTINCT FROM 'delivery_void' THEN RAISE EXCEPTION 'Invalid revision line scope' USING ERRCODE='23514'; END IF;
 ELSIF TG_TABLE_NAME='purchasing_delivery_commands' THEN
  IF NEW.expected_order_version IS DISTINCT FROM o.version THEN RAISE EXCEPTION 'Invalid Order version binding' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER purchasing_delivery_revision_guard BEFORE INSERT ON {{schema}}.purchasing_delivery_revisions FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_delivery_insert_guard();
CREATE TRIGGER purchasing_delivery_line_guard BEFORE INSERT ON {{schema}}.purchasing_delivery_revision_lines FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_delivery_insert_guard();
CREATE TRIGGER purchasing_delivery_command_guard BEFORE INSERT ON {{schema}}.purchasing_delivery_commands FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_delivery_insert_guard();

CREATE FUNCTION {{schema}}.purchasing_delivery_final() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c uuid; o uuid; d uuid; v bigint; r {{schema}}.purchasing_delivery_revisions%ROWTYPE;
 receipt {{schema}}.purchasing_delivery_commands%ROWTYPE; lines jsonb; intent jsonb; summary jsonb; before_summary jsonb;
BEGIN
 c=NEW.company_id;o=NEW.order_id;d=NEW.delivery_id;v=NEW.revision;
 SELECT * INTO r FROM {{schema}}.purchasing_delivery_revisions WHERE company_id=c AND order_id=o AND delivery_id=d AND revision=v;
 SELECT * INTO receipt FROM {{schema}}.purchasing_delivery_commands WHERE company_id=c AND operation_id=r.operation_id;
 lines={{schema}}.purchasing_delivery_revision_json(c,o,d,v)->'lines';
 IF r.operation_id IS NULL OR receipt.operation_id IS NULL OR receipt.accepted_at<r.recorded_at OR
  ((r.kind='delivery_void' AND jsonb_array_length(lines)=0) OR (r.kind<>'delivery_void' AND jsonb_array_length(lines) BETWEEN 1 AND 50)) IS NOT TRUE THEN
  RAISE EXCEPTION 'Incomplete delivery evidence' USING ERRCODE='23514';
 END IF;
 summary={{schema}}.purchasing_delivery_summary(c,o,r.ledger_version);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(summary->'lines') l WHERE (l->>'effectiveDelivered')::numeric>999999999999.999) THEN
  RAISE EXCEPTION 'Delivery quantity limit' USING ERRCODE='23514';
 END IF;
 intent=jsonb_build_object('operationId',r.operation_id,'expectedOrderVersion',receipt.expected_order_version,'expectedLedgerVersion',receipt.expected_ledger_version,'reason',r.reason);
 IF r.kind='delivery_declare' THEN intent=intent||jsonb_build_object('deliveryId',d,'localReference',r.local_reference);
 ELSE intent=intent||jsonb_build_object('expectedRevision',receipt.expected_revision); END IF;
 IF r.kind<>'delivery_void' THEN intent=intent||jsonb_build_object('lines',lines); END IF;
 IF receipt.payload IS DISTINCT FROM intent OR receipt.result IS DISTINCT FROM jsonb_build_object('delivery',{{schema}}.purchasing_delivery_revision_json(c,o,d,v),'summary',summary,'replayed',false) THEN
  RAISE EXCEPTION 'Invalid delivery receipt intent/result' USING ERRCODE='23514';
 END IF;
 before_summary={{schema}}.purchasing_delivery_summary(c,o,r.ledger_version-1);
 IF r.reason IS NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements(summary->'lines') a JOIN jsonb_array_elements(before_summary->'lines') b ON a->>'orderLineId'=b->>'orderLineId' WHERE (a->>'overdelivery')::numeric>(b->>'overdelivery')::numeric) THEN
  RAISE EXCEPTION 'Overdelivery reason required' USING ERRCODE='23514';
 END IF;
 IF r.revision>1 AND lines IS NOT DISTINCT FROM ({{schema}}.purchasing_delivery_revision_json(c,o,d,v-1)->'lines') THEN
  RAISE EXCEPTION 'Unchanged delivery contribution' USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER purchasing_delivery_revision_final AFTER INSERT ON {{schema}}.purchasing_delivery_revisions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_delivery_final();
CREATE CONSTRAINT TRIGGER purchasing_delivery_line_final AFTER INSERT ON {{schema}}.purchasing_delivery_revision_lines DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_delivery_final();
CREATE CONSTRAINT TRIGGER purchasing_delivery_command_final AFTER INSERT ON {{schema}}.purchasing_delivery_commands DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_delivery_final();

CREATE FUNCTION {{schema}}.purchasing_delivery_terminal_final() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE o {{schema}}.purchasing_orders%ROWTYPE; s {{schema}}.purchasing_delivery_terminal_snapshots%ROWTYPE; c uuid; i uuid; b bigint;
BEGIN
 IF TG_TABLE_NAME='purchasing_orders' THEN
  IF (OLD.status='issued' AND NEW.status IN ('closed','cancelled')) IS NOT TRUE THEN RETURN NULL; END IF;
  c=NEW.company_id;i=NEW.id;
 ELSE c=NEW.company_id;i=NEW.order_id; END IF;
 SELECT * INTO o FROM {{schema}}.purchasing_orders WHERE company_id=c AND id=i;
 SELECT * INTO s FROM {{schema}}.purchasing_delivery_terminal_snapshots WHERE company_id=c AND order_id=i;
 SELECT COALESCE(max(ledger_version),0) INTO b FROM {{schema}}.purchasing_delivery_revisions WHERE company_id=c AND order_id=i;
 IF s.operation_id IS NULL OR o.issued_at IS NULL OR o.status NOT IN ('closed','cancelled') OR
  s.location_id IS DISTINCT FROM o.location_id OR s.operation_id IS DISTINCT FROM o.terminal_operation_id OR
  s.order_version IS DISTINCT FROM o.version OR s.actor_id IS DISTINCT FROM o.terminal_by OR s.terminal_at IS DISTINCT FROM o.terminal_at OR
  s.kind IS DISTINCT FROM o.last_kind OR s.ledger_version IS DISTINCT FROM b OR
  s.summary IS DISTINCT FROM {{schema}}.purchasing_delivery_summary(c,i,s.ledger_version) THEN
  RAISE EXCEPTION 'Invalid terminal delivery boundary' USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER purchasing_delivery_terminal_required AFTER UPDATE ON {{schema}}.purchasing_orders DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_delivery_terminal_final();
CREATE CONSTRAINT TRIGGER purchasing_delivery_terminal_final AFTER INSERT ON {{schema}}.purchasing_delivery_terminal_snapshots DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_delivery_terminal_final();

CREATE TRIGGER purchasing_delivery_revision_immutable BEFORE UPDATE OR DELETE ON {{schema}}.purchasing_delivery_revisions FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_command_immutable();
CREATE TRIGGER purchasing_delivery_line_immutable BEFORE UPDATE OR DELETE ON {{schema}}.purchasing_delivery_revision_lines FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_command_immutable();
CREATE TRIGGER purchasing_delivery_command_immutable BEFORE UPDATE OR DELETE ON {{schema}}.purchasing_delivery_commands FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_command_immutable();
CREATE TRIGGER purchasing_delivery_terminal_immutable BEFORE UPDATE OR DELETE ON {{schema}}.purchasing_delivery_terminal_snapshots FOR EACH ROW EXECUTE FUNCTION {{schema}}.purchasing_command_immutable();
