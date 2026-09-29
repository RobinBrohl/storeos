-- Additive Tasks schema: old snapshots and command receipts are never rewritten.
CREATE FUNCTION {{schema}}.valid_task_content(content text) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE body jsonb := content::jsonb; step jsonb;
BEGIN
 IF jsonb_typeof(body)<>'object' OR NOT body ?& ARRAY['schemaVersion','title','steps']
  OR body->'schemaVersion' NOT IN ('1'::jsonb,'2'::jsonb)
  OR jsonb_typeof(body->'steps')<>'array' OR jsonb_array_length(body->'steps')>20
  OR length(body->>'title') NOT BETWEEN 1 AND 120 THEN RETURN false; END IF;
 FOR step IN SELECT * FROM jsonb_array_elements(body->'steps') LOOP
  IF step->>'type'='confirmation' THEN CONTINUE; END IF;
  IF body->'schemaVersion'<>'2'::jsonb OR step->>'type' IS DISTINCT FROM 'number'
   OR NOT step ?& ARRAY['unit','minimum','maximum']
   OR jsonb_typeof(step->'unit')<>'string' OR length(step->>'unit') NOT BETWEEN 1 AND 32
   OR jsonb_typeof(step->'minimum')<>'string' OR jsonb_typeof(step->'maximum')<>'string'
   OR (step->>'minimum') !~ '^-?[0-9]{1,6}(\.[0-9]{1,3})?$'
   OR (step->>'maximum') !~ '^-?[0-9]{1,6}(\.[0-9]{1,3})?$' THEN RETURN false; END IF;
  IF (step->>'minimum')::numeric>(step->>'maximum')::numeric THEN RETURN false; END IF;
 END LOOP;
 RETURN true;
END; $$;
-- Locate only the old content-schema checks (names were PostgreSQL-generated).
DO $$ DECLARE item record; BEGIN
 FOR item IN SELECT conrelid::regclass AS tbl, conname FROM pg_constraint
 WHERE conrelid IN ('{{schema}}.task_template_revisions'::regclass,'{{schema}}.task_instances'::regclass)
 AND contype='c' AND pg_get_constraintdef(oid) LIKE '%schemaVersion%' LOOP
  EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I',item.tbl,item.conname);
 END LOOP;
END; $$;
ALTER TABLE {{schema}}.task_template_revisions ADD CONSTRAINT task_revision_content_schema
 CHECK({{schema}}.valid_task_content(content));
ALTER TABLE {{schema}}.task_instances ADD CONSTRAINT task_instance_content_schema
 CHECK({{schema}}.valid_task_content(content) AND jsonb_array_length(content::jsonb->'steps') BETWEEN 1 AND 20);

CREATE TABLE {{schema}}.task_numeric_attempts (
 id uuid PRIMARY KEY, instance_id uuid NOT NULL, company_id uuid NOT NULL, location_id uuid NOT NULL,
 step_id uuid NOT NULL, value_scaled integer NOT NULL CHECK(value_scaled BETWEEN -999999999 AND 999999999),
 in_range boolean NOT NULL, recorded_at timestamptz NOT NULL,
 recorded_by uuid NOT NULL REFERENCES {{schema}}.accounts(id), accepted_version bigint NOT NULL CHECK(accepted_version>=3),
 FOREIGN KEY(instance_id,company_id,location_id) REFERENCES {{schema}}.task_instances(id,company_id,location_id),
 UNIQUE(instance_id,accepted_version)
);
CREATE INDEX task_numeric_attempts_history ON {{schema}}.task_numeric_attempts(company_id,instance_id,accepted_version DESC);
ALTER TABLE {{schema}}.task_step_results ADD COLUMN numeric_attempt_id uuid UNIQUE REFERENCES {{schema}}.task_numeric_attempts(id);
ALTER TABLE {{schema}}.task_blockings ADD COLUMN numeric_attempt_id uuid UNIQUE REFERENCES {{schema}}.task_numeric_attempts(id);

CREATE FUNCTION {{schema}}.protect_task_number() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE task {{schema}}.task_instances; n integer; step jsonb; valid boolean;
BEGIN
 IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'Numeric attempts are immutable' USING ERRCODE='23514'; END IF;
 SELECT * INTO STRICT task FROM {{schema}}.task_instances WHERE id=NEW.instance_id FOR UPDATE;
 SELECT count(*) INTO n FROM {{schema}}.task_step_results WHERE instance_id=NEW.instance_id;
 step := task.content::jsonb->'steps'->n;
 IF task.status<>'in_progress' OR NEW.accepted_version<>task.version+1
  OR NEW.recorded_at<task.started_at OR step->>'id' IS DISTINCT FROM NEW.step_id::text
  OR step->>'type' IS DISTINCT FROM 'number' THEN
  RAISE EXCEPTION 'Invalid numeric attempt sequence' USING ERRCODE='23514'; END IF;
 valid := NEW.value_scaled BETWEEN (step->>'minimum')::numeric*1000 AND (step->>'maximum')::numeric*1000;
 IF NEW.in_range IS DISTINCT FROM valid THEN RAISE EXCEPTION 'Invalid numeric evaluation' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER numeric_attempt_immutable BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.task_numeric_attempts
 FOR EACH ROW EXECUTE FUNCTION {{schema}}.protect_task_number();

CREATE FUNCTION {{schema}}.check_numeric_result() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE attempt {{schema}}.task_numeric_attempts; step jsonb; version bigint; actor uuid; at_time timestamptz;
BEGIN
 IF TG_TABLE_NAME='task_step_results' THEN
  SELECT content::jsonb->'steps'->NEW.position INTO step FROM {{schema}}.task_instances WHERE id=NEW.instance_id;
  IF (step->>'type'='number') IS DISTINCT FROM (NEW.numeric_attempt_id IS NOT NULL) THEN
   RAISE EXCEPTION 'Numeric step requires a matching attempt' USING ERRCODE='23514'; END IF;
  version:=NEW.accepted_version; actor:=NEW.confirmed_by; at_time:=NEW.confirmed_at;
 ELSE
  version:=NEW.reported_version; actor:=NEW.reported_by; at_time:=NEW.reported_at;
 END IF;
 IF NEW.numeric_attempt_id IS NOT NULL THEN
  SELECT * INTO STRICT attempt FROM {{schema}}.task_numeric_attempts WHERE id=NEW.numeric_attempt_id;
  IF attempt.instance_id<>NEW.instance_id OR attempt.company_id<>NEW.company_id OR attempt.location_id<>NEW.location_id
   OR attempt.step_id IS DISTINCT FROM NEW.step_id OR attempt.accepted_version<>version
   OR attempt.recorded_by<>actor OR attempt.recorded_at<>at_time
   OR attempt.in_range<>(TG_TABLE_NAME='task_step_results') THEN
   RAISE EXCEPTION 'Mismatching numeric evidence' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER numeric_step_evidence BEFORE INSERT ON {{schema}}.task_step_results
 FOR EACH ROW EXECUTE FUNCTION {{schema}}.check_numeric_result();
CREATE TRIGGER numeric_blocking_evidence BEFORE INSERT ON {{schema}}.task_blockings
 FOR EACH ROW EXECUTE FUNCTION {{schema}}.check_numeric_result();

-- An attempt cannot commit without its outcome and aggregate version update.
CREATE FUNCTION {{schema}}.check_numeric_outcome() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM {{schema}}.task_instances WHERE id=NEW.instance_id AND version>=NEW.accepted_version)
 OR (NEW.in_range AND NOT EXISTS(SELECT 1 FROM {{schema}}.task_step_results WHERE numeric_attempt_id=NEW.id))
 OR (NOT NEW.in_range AND NOT EXISTS(SELECT 1 FROM {{schema}}.task_blockings WHERE numeric_attempt_id=NEW.id)) THEN
  RAISE EXCEPTION 'Missing numeric outcome' USING ERRCODE='23514'; END IF;
 RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER numeric_outcome AFTER INSERT ON {{schema}}.task_numeric_attempts
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.check_numeric_outcome();
