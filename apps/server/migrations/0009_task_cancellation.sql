-- Tasks owns cancellation as the terminal disposition of an existing blocking.
ALTER TABLE {{schema}}.task_blockings DISABLE TRIGGER task_blocking_immutable;
ALTER TABLE {{schema}}.task_blockings ADD COLUMN resolution_kind text;
UPDATE {{schema}}.task_blockings SET resolution_kind='resumed' WHERE resolved_at IS NOT NULL;
ALTER TABLE {{schema}}.task_blockings ADD CONSTRAINT task_blocking_resolution_kind CHECK(
 (resolved_at IS NULL AND resolution_kind IS NULL) OR
 (resolved_at IS NOT NULL AND resolution_kind IS NOT NULL AND resolution_kind IN ('resumed','cancelled')));
ALTER TABLE {{schema}}.task_blockings ENABLE TRIGGER task_blocking_immutable;
CREATE UNIQUE INDEX task_blockings_one_cancellation ON {{schema}}.task_blockings(instance_id) WHERE resolution_kind='cancelled';
CREATE INDEX task_cancelled_page ON {{schema}}.task_instances(company_id,location_id,id) WHERE status='cancelled';
ALTER TABLE {{schema}}.task_instances DROP CONSTRAINT task_execution_status,
 DROP CONSTRAINT task_execution_times,
 ADD CONSTRAINT task_execution_status CHECK(status IN ('open','in_progress','blocked','completed','cancelled')),
 ADD CONSTRAINT task_execution_times CHECK(
 (status='open' AND version=1 AND started_at IS NULL AND started_by IS NULL AND completed_at IS NULL AND completed_by IS NULL)
 OR (status IN ('in_progress','blocked') AND version>=2 AND started_at IS NOT NULL AND started_by IS NOT NULL AND completed_at IS NULL AND completed_by IS NULL)
 OR (status='cancelled' AND version>=4 AND started_at IS NOT NULL AND started_by IS NOT NULL AND completed_at IS NULL AND completed_by IS NULL)
 OR (status='completed' AND version>=3 AND started_at IS NOT NULL AND started_by IS NOT NULL AND completed_at IS NOT NULL AND completed_at>=started_at AND completed_by IS NOT NULL));
CREATE OR REPLACE FUNCTION {{schema}}.protect_task_blocking() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE task {{schema}}.task_instances; n integer;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Blocking history is immutable' USING ERRCODE='23514'; END IF;
 SELECT * INTO task FROM {{schema}}.task_instances WHERE id=NEW.instance_id FOR UPDATE;
 IF TG_OP='INSERT' THEN
  SELECT count(*) INTO n FROM {{schema}}.task_step_results WHERE instance_id=NEW.instance_id;
  IF task.status<>'in_progress' OR NEW.reported_version<>task.version+1 OR NEW.resolved_at IS NOT NULL
   OR NEW.reported_at<task.started_at
   OR NEW.step_id::text IS DISTINCT FROM (task.content::jsonb->'steps'->n->>'id') THEN
   RAISE EXCEPTION 'Invalid blocking' USING ERRCODE='23514'; END IF;
 ELSE
  IF (to_jsonb(NEW)-ARRAY['resolution','resolved_at','resolved_by','resolved_version','resolution_kind']) IS DISTINCT FROM
     (to_jsonb(OLD)-ARRAY['resolution','resolved_at','resolved_by','resolved_version','resolution_kind'])
   OR OLD.resolved_at IS NOT NULL OR NEW.resolved_at IS NULL OR task.status<>'blocked'
   OR NEW.resolved_version<>task.version+1 THEN
   RAISE EXCEPTION 'Invalid resolution' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE OR REPLACE FUNCTION {{schema}}.protect_task_instance() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n integer; active integer; valid boolean := false;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Instances cannot be deleted' USING ERRCODE='23514'; END IF;
 IF (to_jsonb(NEW)-ARRAY['title','status','version','started_at','started_by','completed_at','completed_by'])
  IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['title','status','version','started_at','started_by','completed_at','completed_by'])
  OR OLD.status IN ('completed','cancelled') OR NEW.version<>OLD.version+1 THEN
  RAISE EXCEPTION 'Immutable instance or invalid version' USING ERRCODE='23514'; END IF;
 SELECT count(*) INTO n FROM {{schema}}.task_step_results WHERE instance_id=OLD.id;
 SELECT count(*) INTO active FROM {{schema}}.task_blockings WHERE instance_id=OLD.id AND resolved_at IS NULL;
 IF OLD.status='open' THEN
  valid := NEW.status='in_progress' AND n=0 AND active=0;
 ELSE
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
