-- Stock owns selected-article counts. Identification labels are count-time
-- evidence; quantities always use the StockLevel's frozen unit.
CREATE TABLE {{schema}}.stock_counts (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  created_by uuid NOT NULL,
  purpose text NOT NULL CHECK (length(purpose) BETWEEN 1 AND 500 AND purpose=btrim(purpose) AND purpose !~ '[[:cntrl:]]'),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','approved','cancelled')),
  version bigint NOT NULL DEFAULT 1 CHECK (version BETWEEN 1 AND 9007199254740991),
  opened_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  preceding_count_id uuid,
  approved_at timestamptz,
  approved_by uuid,
  cancelled_at timestamptz,
  cancelled_by uuid,
  cancellation_reason text CHECK (cancellation_reason IS NULL OR (length(cancellation_reason) BETWEEN 1 AND 500 AND cancellation_reason=btrim(cancellation_reason) AND cancellation_reason !~ '[[:cntrl:]]')),
  UNIQUE (id,company_id,location_id),
  UNIQUE (id,company_id,location_id,employee_id),
  FOREIGN KEY (location_id,company_id) REFERENCES {{schema}}.locations(id,company_id),
  FOREIGN KEY (employee_id,company_id,location_id) REFERENCES {{schema}}.employees(id,company_id,location_id),
  FOREIGN KEY (created_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY (approved_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY (cancelled_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY (preceding_count_id,company_id,location_id) REFERENCES {{schema}}.stock_counts(id,company_id,location_id),
  CHECK (preceding_count_id IS NULL OR preceding_count_id<>id),
  CHECK ((status='open' AND approved_at IS NULL AND approved_by IS NULL AND cancelled_at IS NULL AND cancelled_by IS NULL AND cancellation_reason IS NULL)
    OR (status='approved' AND approved_at IS NOT NULL AND approved_by IS NOT NULL AND cancelled_at IS NULL AND cancelled_by IS NULL AND cancellation_reason IS NULL)
    OR (status='cancelled' AND approved_at IS NULL AND approved_by IS NULL AND cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL AND cancellation_reason IS NOT NULL))
);
CREATE INDEX stock_counts_page ON {{schema}}.stock_counts(company_id,location_id,id);
CREATE INDEX stock_counts_self_page ON {{schema}}.stock_counts(company_id,location_id,employee_id,id);

CREATE TABLE {{schema}}.stock_count_lines (
  id uuid PRIMARY KEY,
  count_id uuid NOT NULL,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  stock_level_id uuid NOT NULL,
  article_id uuid NOT NULL,
  position integer NOT NULL CHECK (position BETWEEN 1 AND 100),
  stock_unit text NOT NULL CHECK (length(stock_unit) BETWEEN 1 AND 32 AND stock_unit=btrim(stock_unit) AND stock_unit !~ '[[:cntrl:]]'),
  sku text NOT NULL CHECK (length(sku) BETWEEN 1 AND 64 AND sku !~ '[[:cntrl:]]'),
  article_name text NOT NULL CHECK (length(article_name) BETWEEN 1 AND 120 AND article_name !~ '[[:cntrl:]]'),
  barcode text CHECK (barcode IS NULL OR (length(barcode) BETWEEN 1 AND 64 AND barcode !~ '[[:cntrl:]]')),
  current_round_id uuid,
  approved_observation_id uuid,
  discrepancy_scaled bigint CHECK (discrepancy_scaled BETWEEN -999999999999999 AND 999999999999999),
  checked_stock_version bigint,
  movement_id uuid,
  UNIQUE (count_id,stock_level_id),
  UNIQUE (count_id,position),
  UNIQUE (id,count_id,company_id,location_id,stock_level_id,article_id,stock_unit),
  UNIQUE (id,count_id,approved_observation_id,movement_id),
  FOREIGN KEY (count_id,company_id,location_id) REFERENCES {{schema}}.stock_counts(id,company_id,location_id),
  FOREIGN KEY (stock_level_id,company_id,location_id,article_id) REFERENCES {{schema}}.stock_levels(id,company_id,location_id,article_id),
  CHECK ((approved_observation_id IS NULL AND discrepancy_scaled IS NULL AND checked_stock_version IS NULL AND movement_id IS NULL)
    OR (approved_observation_id IS NOT NULL AND discrepancy_scaled IS NOT NULL AND checked_stock_version IS NOT NULL AND checked_stock_version BETWEEN 1 AND 9007199254740991 AND ((discrepancy_scaled=0 AND movement_id IS NULL) OR (discrepancy_scaled<>0 AND movement_id IS NOT NULL))))
);

CREATE TABLE {{schema}}.stock_count_rounds (
  id uuid PRIMARY KEY,
  line_id uuid NOT NULL,
  count_id uuid NOT NULL,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  stock_level_id uuid NOT NULL,
  article_id uuid NOT NULL,
  stock_unit text NOT NULL,
  number bigint NOT NULL CHECK (number BETWEEN 1 AND 9007199254740991),
  baseline_scaled bigint NOT NULL CHECK (baseline_scaled BETWEEN 0 AND 999999999999999),
  baseline_version bigint NOT NULL CHECK (baseline_version BETWEEN 1 AND 9007199254740991),
  captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  provenance text NOT NULL CHECK (provenance IN ('open','recount')),
  requested_by uuid NOT NULL,
  reason text CHECK (reason IS NULL OR (length(reason) BETWEEN 1 AND 500 AND reason=btrim(reason) AND reason !~ '[[:cntrl:]]')),
  operation_id uuid NOT NULL,
  UNIQUE (line_id,number),
  UNIQUE (id,line_id,count_id,company_id,location_id,stock_level_id,article_id,stock_unit),
  FOREIGN KEY (line_id,count_id,company_id,location_id,stock_level_id,article_id,stock_unit) REFERENCES {{schema}}.stock_count_lines(id,count_id,company_id,location_id,stock_level_id,article_id,stock_unit),
  FOREIGN KEY (requested_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  CHECK ((number=1 AND provenance='open' AND reason IS NULL) OR (number>1 AND provenance='recount' AND reason IS NOT NULL))
);
ALTER TABLE {{schema}}.stock_count_lines ADD CONSTRAINT stock_count_current_round_fk
  FOREIGN KEY (current_round_id,id,count_id,company_id,location_id,stock_level_id,article_id,stock_unit)
  REFERENCES {{schema}}.stock_count_rounds(id,line_id,count_id,company_id,location_id,stock_level_id,article_id,stock_unit);

CREATE TABLE {{schema}}.stock_count_observations (
  id uuid PRIMARY KEY,
  round_id uuid NOT NULL UNIQUE,
  line_id uuid NOT NULL,
  count_id uuid NOT NULL,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  stock_level_id uuid NOT NULL,
  article_id uuid NOT NULL,
  stock_unit text NOT NULL,
  employee_id uuid NOT NULL,
  recorded_by uuid NOT NULL,
  observed_scaled bigint NOT NULL CHECK (observed_scaled BETWEEN 0 AND 999999999999999),
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  note text CHECK (note IS NULL OR (length(note) BETWEEN 1 AND 500 AND note=btrim(note) AND note !~ '[[:cntrl:]]')),
  operation_id uuid NOT NULL UNIQUE,
  UNIQUE (id,line_id,count_id,stock_level_id,article_id,company_id,location_id),
  FOREIGN KEY (round_id,line_id,count_id,company_id,location_id,stock_level_id,article_id,stock_unit) REFERENCES {{schema}}.stock_count_rounds(id,line_id,count_id,company_id,location_id,stock_level_id,article_id,stock_unit),
  FOREIGN KEY (count_id,company_id,location_id,employee_id) REFERENCES {{schema}}.stock_counts(id,company_id,location_id,employee_id),
  FOREIGN KEY (recorded_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id)
);

CREATE TABLE {{schema}}.stock_count_commands (
  operation_id uuid PRIMARY KEY,
  count_id uuid NOT NULL,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  actor_id uuid NOT NULL,
  kind text NOT NULL CHECK (kind IN ('open','observation','recount','approve','cancel')),
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload)='object' AND octet_length(payload::text)<=16384),
  -- A bounded 100-line current result can include 500-character Unicode notes
  -- and recount reasons per line; allow their full UTF-8 representation.
  result jsonb NOT NULL CHECK (jsonb_typeof(result)='object' AND octet_length(result::text)<=1048576),
  accepted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (operation_id,count_id,company_id,location_id),
  FOREIGN KEY (count_id,company_id,location_id) REFERENCES {{schema}}.stock_counts(id,company_id,location_id),
  FOREIGN KEY (actor_id,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id)
);
ALTER TABLE {{schema}}.stock_count_rounds ADD CONSTRAINT stock_count_round_command_fk
  FOREIGN KEY (operation_id,count_id,company_id,location_id) REFERENCES {{schema}}.stock_count_commands(operation_id,count_id,company_id,location_id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE {{schema}}.stock_count_observations ADD CONSTRAINT stock_count_observation_command_fk
  FOREIGN KEY (operation_id,count_id,company_id,location_id) REFERENCES {{schema}}.stock_count_commands(operation_id,count_id,company_id,location_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE {{schema}}.stock_movements DROP CONSTRAINT stock_movements_kind_valid;
ALTER TABLE {{schema}}.stock_movements ADD CONSTRAINT stock_movements_kind_valid CHECK (kind IN ('opening','adjustment','count_correction'));
ALTER TABLE {{schema}}.stock_movements ADD COLUMN count_id uuid;
ALTER TABLE {{schema}}.stock_movements ADD COLUMN count_line_id uuid;
ALTER TABLE {{schema}}.stock_movements ADD COLUMN count_observation_id uuid;
ALTER TABLE {{schema}}.stock_movements ADD CONSTRAINT stock_movement_count_provenance_valid CHECK (
  (kind='count_correction' AND count_id IS NOT NULL AND count_line_id IS NOT NULL AND count_observation_id IS NOT NULL AND delta_scaled<>0)
  OR (kind<>'count_correction' AND count_id IS NULL AND count_line_id IS NULL AND count_observation_id IS NULL));
CREATE UNIQUE INDEX stock_movement_count_observation_unique ON {{schema}}.stock_movements(count_observation_id) WHERE count_observation_id IS NOT NULL;
ALTER TABLE {{schema}}.stock_movements ADD CONSTRAINT stock_movement_count_observation_fk
  FOREIGN KEY (count_observation_id,count_line_id,count_id,stock_level_id,article_id,company_id,location_id)
  REFERENCES {{schema}}.stock_count_observations(id,line_id,count_id,stock_level_id,article_id,company_id,location_id);
ALTER TABLE {{schema}}.stock_movements ADD CONSTRAINT stock_movement_approved_line_fk
  FOREIGN KEY (count_line_id,count_id,count_observation_id,id)
  REFERENCES {{schema}}.stock_count_lines(id,count_id,approved_observation_id,movement_id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE {{schema}}.stock_count_lines ADD CONSTRAINT stock_count_approved_observation_fk
  FOREIGN KEY (approved_observation_id,id,count_id,stock_level_id,article_id,company_id,location_id)
  REFERENCES {{schema}}.stock_count_observations(id,line_id,count_id,stock_level_id,article_id,company_id,location_id);
ALTER TABLE {{schema}}.stock_count_lines ADD CONSTRAINT stock_count_movement_fk FOREIGN KEY (movement_id) REFERENCES {{schema}}.stock_movements(id) DEFERRABLE INITIALLY DEFERRED;

CREATE FUNCTION {{schema}}.stock_count_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Immutable Stock count evidence' USING ERRCODE='23514'; END $$;
CREATE TRIGGER stock_count_round_immutable BEFORE UPDATE OR DELETE ON {{schema}}.stock_count_rounds FOR EACH ROW EXECUTE FUNCTION {{schema}}.stock_count_append_only();
CREATE TRIGGER stock_count_observation_immutable BEFORE UPDATE OR DELETE ON {{schema}}.stock_count_observations FOR EACH ROW EXECUTE FUNCTION {{schema}}.stock_count_append_only();
CREATE TRIGGER stock_count_command_immutable BEFORE UPDATE OR DELETE ON {{schema}}.stock_count_commands FOR EACH ROW EXECUTE FUNCTION {{schema}}.stock_count_append_only();
CREATE TRIGGER stock_count_movement_immutable BEFORE UPDATE OR DELETE ON {{schema}}.stock_movements FOR EACH ROW WHEN (OLD.kind='count_correction') EXECUTE FUNCTION {{schema}}.stock_count_append_only();

CREATE FUNCTION {{schema}}.stock_count_header_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Count cannot be deleted' USING ERRCODE='23514'; END IF;
  IF TG_OP='UPDATE' THEN
    IF OLD.status<>'open' OR NEW.version<>OLD.version+1 OR
      (to_jsonb(NEW)-ARRAY['status','version','approved_at','approved_by','cancelled_at','cancelled_by','cancellation_reason']) IS DISTINCT FROM
      (to_jsonb(OLD)-ARRAY['status','version','approved_at','approved_by','cancelled_at','cancelled_by','cancellation_reason'])
    THEN RAISE EXCEPTION 'Count identity or terminal evidence is immutable' USING ERRCODE='23514'; END IF;
  ELSE
    IF NEW.status<>'open' OR NEW.version<>1 THEN RAISE EXCEPTION 'Count must open at version one' USING ERRCODE='23514'; END IF;
    IF NEW.preceding_count_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM {{schema}}.stock_counts WHERE id=NEW.preceding_count_id AND status IN ('approved','cancelled'))
    THEN RAISE EXCEPTION 'Preceding count must be terminal' USING ERRCODE='23514'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER stock_count_header_guard BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.stock_counts FOR EACH ROW EXECUTE FUNCTION {{schema}}.stock_count_header_guard();

CREATE FUNCTION {{schema}}.stock_count_line_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Count line cannot be deleted' USING ERRCODE='23514'; END IF;
  IF NOT EXISTS (SELECT 1 FROM {{schema}}.stock_counts WHERE id=NEW.count_id AND status='open') THEN RAISE EXCEPTION 'Count is terminal' USING ERRCODE='23514'; END IF;
  IF TG_OP='UPDATE' AND ((to_jsonb(NEW)-ARRAY['current_round_id','approved_observation_id','discrepancy_scaled','checked_stock_version','movement_id']) IS DISTINCT FROM
    (to_jsonb(OLD)-ARRAY['current_round_id','approved_observation_id','discrepancy_scaled','checked_stock_version','movement_id']) OR OLD.approved_observation_id IS NOT NULL)
  THEN RAISE EXCEPTION 'Count line evidence is immutable' USING ERRCODE='23514'; END IF;
  IF TG_OP='INSERT' AND NOT EXISTS (SELECT 1 FROM {{schema}}.stock_levels WHERE id=NEW.stock_level_id AND stock_unit=NEW.stock_unit)
  THEN RAISE EXCEPTION 'Frozen unit does not match Stock' USING ERRCODE='23514'; END IF;
  IF TG_OP='UPDATE' AND OLD.current_round_id IS NOT NULL AND NEW.current_round_id IS DISTINCT FROM OLD.current_round_id AND NOT EXISTS (
    SELECT 1 FROM {{schema}}.stock_count_rounds old_round JOIN {{schema}}.stock_count_rounds new_round ON new_round.line_id=old_round.line_id AND new_round.number=old_round.number+1
    WHERE old_round.id=OLD.current_round_id AND new_round.id=NEW.current_round_id)
  THEN RAISE EXCEPTION 'Current round must advance' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER stock_count_line_guard BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.stock_count_lines FOR EACH ROW EXECUTE FUNCTION {{schema}}.stock_count_line_guard();

CREATE FUNCTION {{schema}}.stock_count_insert_evidence_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM {{schema}}.stock_counts WHERE id=NEW.count_id AND status='open') THEN RAISE EXCEPTION 'Count is terminal' USING ERRCODE='23514'; END IF;
  IF TG_TABLE_NAME='stock_count_observations' THEN
    IF NOT EXISTS (SELECT 1 FROM {{schema}}.stock_count_lines WHERE id=NEW.line_id AND current_round_id=NEW.round_id)
    THEN RAISE EXCEPTION 'Observation round is superseded' USING ERRCODE='23514'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER stock_count_round_open BEFORE INSERT ON {{schema}}.stock_count_rounds FOR EACH ROW EXECUTE FUNCTION {{schema}}.stock_count_insert_evidence_guard();
CREATE TRIGGER stock_count_observation_current BEFORE INSERT ON {{schema}}.stock_count_observations FOR EACH ROW EXECUTE FUNCTION {{schema}}.stock_count_insert_evidence_guard();

-- Deferred checks inspect final transaction state: no partial approval, invalid
-- zero-variance outcome, unrelated observation, or movement claiming other facts.
CREATE FUNCTION {{schema}}.stock_count_final_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c {{schema}}.stock_counts%ROWTYPE; l record; n integer;
BEGIN
  SELECT * INTO c FROM {{schema}}.stock_counts WHERE id=COALESCE((to_jsonb(NEW)->>'count_id')::uuid,NEW.id);
  SELECT count(*) INTO n FROM {{schema}}.stock_count_lines WHERE count_id=c.id;
  IF n NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Count requires 1-100 lines' USING ERRCODE='23514'; END IF;
  FOR l IN SELECT line.*, r.baseline_scaled,r.baseline_version,o.observed_scaled,o.recorded_by,o.round_id,m.kind,m.delta_scaled,m.balance_after_scaled,m.balance_version,m.recorded_by AS movement_actor
    FROM {{schema}}.stock_count_lines line
    LEFT JOIN {{schema}}.stock_count_rounds r ON r.id=line.current_round_id
    LEFT JOIN {{schema}}.stock_count_observations o ON o.id=line.approved_observation_id
    LEFT JOIN {{schema}}.stock_movements m ON m.id=line.movement_id WHERE line.count_id=c.id
  LOOP
    IF l.current_round_id IS NULL THEN RAISE EXCEPTION 'Current round required' USING ERRCODE='23514'; END IF;
    IF c.status='approved' THEN
      IF l.approved_observation_id IS NULL OR l.round_id<>l.current_round_id OR l.discrepancy_scaled<>l.observed_scaled-l.baseline_scaled OR l.checked_stock_version<>l.baseline_version OR l.recorded_by=c.approved_by
      THEN RAISE EXCEPTION 'Invalid approved count evidence' USING ERRCODE='23514'; END IF;
      IF l.discrepancy_scaled<>0 AND (l.kind IS DISTINCT FROM 'count_correction' OR l.delta_scaled<>l.discrepancy_scaled OR l.balance_after_scaled<>l.observed_scaled OR l.balance_version<>l.baseline_version+1 OR l.movement_actor<>c.approved_by)
      THEN RAISE EXCEPTION 'Invalid count correction evidence' USING ERRCODE='23514'; END IF;
    ELSIF l.approved_observation_id IS NOT NULL THEN RAISE EXCEPTION 'Only approved counts have outcomes' USING ERRCODE='23514'; END IF;
  END LOOP;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER stock_count_complete AFTER INSERT OR UPDATE ON {{schema}}.stock_counts DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.stock_count_final_guard();
CREATE CONSTRAINT TRIGGER stock_count_line_complete AFTER INSERT OR UPDATE ON {{schema}}.stock_count_lines DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.stock_count_final_guard();
CREATE CONSTRAINT TRIGGER stock_count_movement_complete AFTER INSERT ON {{schema}}.stock_movements DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (NEW.kind='count_correction') EXECUTE FUNCTION {{schema}}.stock_count_final_guard();
