-- Workforce/Tasks: a published shift may be terminally cancelled while every
-- materialized task instance is still pristine open. Started work is never
-- reconciled; the transaction is refused instead. Existing blocked-origin
-- cancellation evidence stays valid and unchanged.
ALTER TABLE {{schema}}.shifts
 ADD COLUMN cancelled_at timestamptz,
 ADD COLUMN cancelled_by uuid REFERENCES {{schema}}.accounts(id),
 ADD COLUMN cancellation_reason text CHECK(char_length(cancellation_reason) BETWEEN 1 AND 500),
 ADD COLUMN cancellation_version bigint CHECK(cancellation_version>0);
-- Locate the original unnamed status/state checks (names are PostgreSQL-generated).
DO $$ DECLARE item record; BEGIN
 FOR item IN SELECT conname FROM pg_constraint
 WHERE conrelid='{{schema}}.shifts'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%draft%' LOOP
  EXECUTE format('ALTER TABLE {{schema}}.shifts DROP CONSTRAINT %I',item.conname);
 END LOOP;
END; $$;
ALTER TABLE {{schema}}.shifts ADD CONSTRAINT shifts_status
 CHECK(status IN ('draft','published','cancelled')),
 ADD CONSTRAINT shifts_state CHECK(
 (status='draft' AND published_at IS NULL AND published_by IS NULL AND publication_version IS NULL
  AND cancelled_at IS NULL AND cancelled_by IS NULL AND cancellation_reason IS NULL AND cancellation_version IS NULL)
 OR (status='published' AND published_at IS NOT NULL AND published_by IS NOT NULL AND publication_version IS NOT NULL AND publication_version>0
  AND cancelled_at IS NULL AND cancelled_by IS NULL AND cancellation_reason IS NULL AND cancellation_version IS NULL)
 OR (status='cancelled' AND published_at IS NOT NULL AND published_by IS NOT NULL AND publication_version IS NOT NULL AND publication_version>0
  AND cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL AND cancellation_reason IS NOT NULL AND cancellation_version IS NOT NULL));
-- Published shifts stay immutable except for the single published -> cancelled
-- transition; cancelled shifts are terminal and cannot be deleted.
CREATE OR REPLACE FUNCTION {{schema}}.protect_published_shift() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN
  IF OLD.status IN ('published','cancelled') THEN RAISE EXCEPTION 'Published shifts are immutable' USING ERRCODE='23514'; END IF;
  RETURN OLD;
 END IF;
 IF OLD.status='published' AND NEW.status='cancelled' THEN
  IF (to_jsonb(NEW)-ARRAY['status','version','updated_at','cancelled_at','cancelled_by','cancellation_reason','cancellation_version'])
   IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version','updated_at','cancelled_at','cancelled_by','cancellation_reason','cancellation_version']) THEN
   RAISE EXCEPTION 'Invalid shift cancellation' USING ERRCODE='23514'; END IF;
  RETURN NEW;
 END IF;
 IF OLD.status IN ('published','cancelled') THEN RAISE EXCEPTION 'Published shifts are immutable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
-- Cancelled shifts keep their published selections frozen as evidence.
CREATE OR REPLACE FUNCTION {{schema}}.protect_shift_selection() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM {{schema}}.shifts WHERE id=CASE WHEN TG_OP='DELETE' THEN OLD.shift_id ELSE NEW.shift_id END AND status IN ('published','cancelled')) THEN
  RAISE EXCEPTION 'Published selections are immutable' USING ERRCODE='23514';
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END; $$;
ALTER TABLE {{schema}}.task_instances
 ADD COLUMN cancelled_at timestamptz,
 ADD COLUMN cancelled_by uuid REFERENCES {{schema}}.accounts(id);
ALTER TABLE {{schema}}.task_instances DROP CONSTRAINT task_execution_status,
 DROP CONSTRAINT task_execution_times,
 ADD CONSTRAINT task_execution_status CHECK(status IN ('open','in_progress','blocked','completed','cancelled')),
 ADD CONSTRAINT task_execution_times CHECK(
 (status='open' AND version=1 AND started_at IS NULL AND started_by IS NULL AND completed_at IS NULL AND completed_by IS NULL
  AND cancelled_at IS NULL AND cancelled_by IS NULL)
 OR (status IN ('in_progress','blocked') AND version>=2 AND started_at IS NOT NULL AND started_by IS NOT NULL AND completed_at IS NULL AND completed_by IS NULL
  AND cancelled_at IS NULL AND cancelled_by IS NULL)
 OR (status='cancelled' AND version=2 AND started_at IS NULL AND started_by IS NULL AND completed_at IS NULL AND completed_by IS NULL
  AND cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL)
 OR (status='cancelled' AND version>=4 AND started_at IS NOT NULL AND started_by IS NOT NULL AND completed_at IS NULL AND completed_by IS NULL
  AND cancelled_at IS NULL AND cancelled_by IS NULL)
 OR (status='completed' AND version>=3 AND started_at IS NOT NULL AND started_by IS NOT NULL AND completed_at IS NOT NULL AND completed_at>=started_at AND completed_by IS NOT NULL
  AND cancelled_at IS NULL AND cancelled_by IS NULL));
-- open -> cancelled (version 1 -> 2) requires pristine evidence: no results, no
-- active blocking, cancellation fields set. Blocked-origin cancellation keeps its
-- blocking disposition and must not set the instance-level cancellation fields.
CREATE OR REPLACE FUNCTION {{schema}}.protect_task_instance() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n integer; active integer; valid boolean := false;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Instances cannot be deleted' USING ERRCODE='23514'; END IF;
 IF (to_jsonb(NEW)-ARRAY['title','status','version','started_at','started_by','completed_at','completed_by','cancelled_at','cancelled_by'])
  IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['title','status','version','started_at','started_by','completed_at','completed_by','cancelled_at','cancelled_by'])
  OR OLD.status IN ('completed','cancelled') OR NEW.version<>OLD.version+1 THEN
  RAISE EXCEPTION 'Immutable instance or invalid version' USING ERRCODE='23514'; END IF;
 SELECT count(*) INTO n FROM {{schema}}.task_step_results WHERE instance_id=OLD.id;
 SELECT count(*) INTO active FROM {{schema}}.task_blockings WHERE instance_id=OLD.id AND resolved_at IS NULL;
 IF OLD.status='open' THEN
  valid := (NEW.status='in_progress' AND n=0 AND active=0 AND NEW.cancelled_at IS NULL AND NEW.cancelled_by IS NULL)
   OR (NEW.status='cancelled' AND n=0 AND active=0 AND NEW.cancelled_at IS NOT NULL AND NEW.cancelled_by IS NOT NULL);
 ELSE
  IF NEW.cancelled_at IS NOT NULL OR NEW.cancelled_by IS NOT NULL THEN
   RAISE EXCEPTION 'Unexpected cancellation evidence' USING ERRCODE='23514'; END IF;
  IF NEW.started_at IS DISTINCT FROM OLD.started_at OR NEW.started_by IS DISTINCT FROM OLD.started_by THEN
   RAISE EXCEPTION 'Immutable start' USING ERRCODE='23514'; END IF;
  IF OLD.status='in_progress' AND NEW.status='blocked' THEN
   SELECT active=1 AND EXISTS(SELECT 1 FROM {{schema}}.task_blockings WHERE instance_id=OLD.id AND reported_version=NEW.version AND resolved_at IS NULL) INTO valid;
  ELSIF OLD.status='blocked' AND NEW.status='in_progress' THEN
   SELECT active=0 AND EXISTS(SELECT 1 FROM {{schema}}.task_blockings WHERE instance_id=OLD.id AND resolved_version=NEW.version AND resolution_kind='resumed') INTO valid;
  ELSIF OLD.status='blocked' AND NEW.status='cancelled' THEN
   SELECT active=0 AND EXISTS(SELECT 1 FROM {{schema}}.task_blockings WHERE instance_id=OLD.id AND resolved_version=NEW.version AND resolution_kind='cancelled') INTO valid;
  ELSIF OLD.status='in_progress' AND NEW.status='in_progress' THEN
   SELECT active=0 AND EXISTS(SELECT 1 FROM {{schema}}.task_step_results WHERE instance_id=OLD.id AND accepted_version=NEW.version) INTO valid;
  ELSIF OLD.status='in_progress' AND NEW.status='completed' THEN
   valid := active=0 AND n=jsonb_array_length(OLD.content::jsonb->'steps');
  END IF;
 END IF;
 IF NOT valid THEN RAISE EXCEPTION 'Invalid execution transition' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
