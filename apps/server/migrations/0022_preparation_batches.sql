-- Production-owned operator declarations; no Stock, Task or event effects.
CREATE TABLE {{schema}}.production_preparation_batches (
  id uuid NOT NULL,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  recipe_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  revision_status text NOT NULL DEFAULT 'published' CHECK (revision_status='published'),
  employee_id uuid NOT NULL,
  opened_by uuid NOT NULL,
  opened_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  planned_declared_batch_count integer CHECK (planned_declared_batch_count BETWEEN 1 AND 9999),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','completed','cancelled')),
  version integer NOT NULL DEFAULT 1,
  open_operation_id uuid NOT NULL,
  open_kind text NOT NULL DEFAULT 'open' CHECK (open_kind='open'),
  actual_declared_batch_count integer CHECK (actual_declared_batch_count BETWEEN 1 AND 9999),
  completed_by uuid,
  completed_at timestamptz,
  completion_note text CHECK (completion_note IS NULL OR (length(completion_note) BETWEEN 1 AND 500 AND completion_note=btrim(completion_note) AND completion_note !~ '[[:cntrl:]]')),
  cancelled_by uuid,
  cancelled_at timestamptz,
  cancellation_reason text CHECK (cancellation_reason IS NULL OR (length(cancellation_reason) BETWEEN 1 AND 500 AND cancellation_reason=btrim(cancellation_reason) AND cancellation_reason !~ '[[:cntrl:]]')),
  terminal_operation_id uuid,
  terminal_kind text,
  terminal_actor uuid GENERATED ALWAYS AS (COALESCE(completed_by,cancelled_by)) STORED,
  PRIMARY KEY (company_id,id),
  UNIQUE (company_id,id,location_id),
  FOREIGN KEY (location_id,company_id) REFERENCES {{schema}}.locations(id,company_id),
  FOREIGN KEY (employee_id,company_id,location_id) REFERENCES {{schema}}.employees(id,company_id,location_id),
  FOREIGN KEY (opened_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY (completed_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY (cancelled_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY (revision_id,company_id,recipe_id,revision_status) REFERENCES {{schema}}.production_recipe_revisions(id,company_id,recipe_id,status),
  CONSTRAINT preparation_batch_shape CHECK (
    (status='open' AND version=1 AND actual_declared_batch_count IS NULL AND completed_by IS NULL AND completed_at IS NULL AND completion_note IS NULL AND cancelled_by IS NULL AND cancelled_at IS NULL AND cancellation_reason IS NULL AND terminal_operation_id IS NULL AND terminal_kind IS NULL) OR
    (status='completed' AND version=2 AND actual_declared_batch_count IS NOT NULL AND completed_by IS NOT NULL AND completed_at IS NOT NULL AND completed_at>=opened_at AND cancelled_by IS NULL AND cancelled_at IS NULL AND cancellation_reason IS NULL AND terminal_operation_id IS NOT NULL AND terminal_kind IS NOT NULL AND terminal_kind='complete') OR
    (status='cancelled' AND version=2 AND actual_declared_batch_count IS NULL AND completed_by IS NULL AND completed_at IS NULL AND completion_note IS NULL AND cancelled_by IS NOT NULL AND cancelled_at IS NOT NULL AND cancelled_at>=opened_at AND cancellation_reason IS NOT NULL AND terminal_operation_id IS NOT NULL AND terminal_kind IS NOT NULL AND terminal_kind IN ('employee_cancel','manager_cancel')))
);
CREATE INDEX preparation_batch_self_history ON {{schema}}.production_preparation_batches(company_id,location_id,employee_id,id);
CREATE INDEX preparation_batch_manager_history ON {{schema}}.production_preparation_batches(company_id,location_id,status,id);

CREATE TABLE {{schema}}.production_preparation_batch_commands (
  company_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  location_id uuid NOT NULL,
  batch_id uuid NOT NULL,
  actor_id uuid NOT NULL,
  kind text NOT NULL CHECK (kind IN ('open','complete','employee_cancel','manager_cancel','count_correct')),
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload)='object' AND octet_length(payload::text)<=16384),
  result jsonb NOT NULL CHECK (jsonb_typeof(result)='object' AND octet_length(result::text)<=32768),
  accepted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (company_id,operation_id),
  UNIQUE (company_id,operation_id,batch_id,location_id,actor_id,kind),
  FOREIGN KEY (company_id,batch_id,location_id) REFERENCES {{schema}}.production_preparation_batches(company_id,id,location_id),
  FOREIGN KEY (actor_id,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id)
);
ALTER TABLE {{schema}}.production_preparation_batches ADD CONSTRAINT preparation_batch_open_receipt
  FOREIGN KEY (company_id,open_operation_id,id,location_id,opened_by,open_kind)
  REFERENCES {{schema}}.production_preparation_batch_commands(company_id,operation_id,batch_id,location_id,actor_id,kind) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE {{schema}}.production_preparation_batches ADD CONSTRAINT preparation_batch_terminal_receipt
  FOREIGN KEY (company_id,terminal_operation_id,id,location_id,terminal_actor,terminal_kind)
  REFERENCES {{schema}}.production_preparation_batch_commands(company_id,operation_id,batch_id,location_id,actor_id,kind) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE {{schema}}.production_preparation_batch_count_corrections (
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  batch_id uuid NOT NULL,
  correction_number integer NOT NULL CHECK (correction_number>0),
  previous_effective_count integer NOT NULL CHECK (previous_effective_count BETWEEN 0 AND 9999),
  replacement_declared_batch_count integer NOT NULL CHECK (replacement_declared_batch_count BETWEEN 0 AND 9999),
  corrected_by uuid NOT NULL,
  corrected_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  reason text NOT NULL CHECK (length(reason) BETWEEN 1 AND 500 AND reason=btrim(reason) AND reason !~ '[[:cntrl:]]'),
  operation_id uuid NOT NULL,
  command_kind text NOT NULL DEFAULT 'count_correct' CHECK (command_kind='count_correct'),
  PRIMARY KEY (company_id,batch_id,correction_number),
  UNIQUE (company_id,operation_id),
  FOREIGN KEY (company_id,batch_id,location_id) REFERENCES {{schema}}.production_preparation_batches(company_id,id,location_id),
  FOREIGN KEY (corrected_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY (company_id,operation_id,batch_id,location_id,corrected_by,command_kind)
    REFERENCES {{schema}}.production_preparation_batch_commands(company_id,operation_id,batch_id,location_id,actor_id,kind) DEFERRABLE INITIALLY DEFERRED
);

CREATE FUNCTION {{schema}}.preparation_batch_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Preparation evidence retained' USING ERRCODE='23514'; END IF;
  IF TG_OP='INSERT' THEN
    IF NEW.status<>'open' OR NEW.version<>1 THEN RAISE EXCEPTION 'Batch must open' USING ERRCODE='23514'; END IF;
  ELSE
    IF OLD.status<>'open' OR NEW.status NOT IN ('completed','cancelled') OR NEW.version<>2 OR
      (to_jsonb(NEW)-ARRAY['status','version','actual_declared_batch_count','completed_by','completed_at','completion_note','cancelled_by','cancelled_at','cancellation_reason','terminal_operation_id','terminal_kind','terminal_actor']) IS DISTINCT FROM
      (to_jsonb(OLD)-ARRAY['status','version','actual_declared_batch_count','completed_by','completed_at','completion_note','cancelled_by','cancelled_at','cancellation_reason','terminal_operation_id','terminal_kind','terminal_actor'])
    THEN RAISE EXCEPTION 'Frozen preparation identity or terminal evidence' USING ERRCODE='23514'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER preparation_batch_guard BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.production_preparation_batches FOR EACH ROW EXECUTE FUNCTION {{schema}}.preparation_batch_guard();
CREATE FUNCTION {{schema}}.preparation_evidence_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Immutable preparation evidence' USING ERRCODE='23514'; END $$;
CREATE TRIGGER preparation_command_immutable BEFORE UPDATE OR DELETE ON {{schema}}.production_preparation_batch_commands FOR EACH ROW EXECUTE FUNCTION {{schema}}.preparation_evidence_immutable();
CREATE TRIGGER preparation_correction_immutable BEFORE UPDATE OR DELETE ON {{schema}}.production_preparation_batch_count_corrections FOR EACH ROW EXECUTE FUNCTION {{schema}}.preparation_evidence_immutable();
CREATE FUNCTION {{schema}}.preparation_correction_chain() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE b {{schema}}.production_preparation_batches%ROWTYPE; n integer; effective integer;
BEGIN
  SELECT * INTO b FROM {{schema}}.production_preparation_batches WHERE company_id=NEW.company_id AND id=NEW.batch_id FOR UPDATE;
  IF b.status IS DISTINCT FROM 'completed' THEN RAISE EXCEPTION 'Completed batch required' USING ERRCODE='23514'; END IF;
  SELECT correction_number,replacement_declared_batch_count INTO n,effective FROM {{schema}}.production_preparation_batch_count_corrections WHERE company_id=NEW.company_id AND batch_id=NEW.batch_id ORDER BY correction_number DESC LIMIT 1;
  IF NEW.correction_number<>COALESCE(n,0)+1 OR NEW.previous_effective_count<>COALESCE(effective,b.actual_declared_batch_count) OR NEW.corrected_at<b.completed_at THEN
    RAISE EXCEPTION 'Invalid correction chain' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER preparation_correction_chain BEFORE INSERT ON {{schema}}.production_preparation_batch_count_corrections FOR EACH ROW EXECUTE FUNCTION {{schema}}.preparation_correction_chain();
