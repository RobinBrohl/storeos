-- Tasks owns blocking history and the execution version of every confirmation.
ALTER TABLE {{schema}}.task_instances DROP CONSTRAINT task_execution_status,
 DROP CONSTRAINT task_execution_times,
 ADD CONSTRAINT task_execution_status CHECK(status IN ('open','in_progress','blocked','completed')),
 ADD CONSTRAINT task_execution_times CHECK(
 (status='open' AND version=1 AND started_at IS NULL AND started_by IS NULL AND completed_at IS NULL AND completed_by IS NULL)
 OR (status IN ('in_progress','blocked') AND version>=2 AND started_at IS NOT NULL AND started_by IS NOT NULL AND completed_at IS NULL AND completed_by IS NULL)
 OR (status='completed' AND version>=3 AND started_at IS NOT NULL AND started_by IS NOT NULL AND completed_at IS NOT NULL AND completed_at>=started_at AND completed_by IS NOT NULL));
-- Disable only the immutable-row trigger for this owner-run, atomic backfill.
ALTER TABLE {{schema}}.task_step_results DISABLE TRIGGER task_step_immutable;
ALTER TABLE {{schema}}.task_step_results ADD COLUMN accepted_version bigint;
UPDATE {{schema}}.task_step_results SET accepted_version=position+3;
ALTER TABLE {{schema}}.task_step_results ALTER COLUMN accepted_version SET NOT NULL,
 ADD CHECK(accepted_version>=3), ADD UNIQUE(instance_id,accepted_version);
ALTER TABLE {{schema}}.task_step_results ENABLE TRIGGER task_step_immutable;
ALTER TABLE {{schema}}.task_execution_commands DROP CONSTRAINT task_execution_commands_input_check,
 ADD CONSTRAINT task_execution_commands_input_check CHECK(octet_length(input)<=4096);
CREATE TABLE {{schema}}.task_blockings (
 id uuid PRIMARY KEY, instance_id uuid NOT NULL, company_id uuid NOT NULL, location_id uuid NOT NULL,
 step_id uuid, reason text NOT NULL CHECK(char_length(reason) BETWEEN 1 AND 500),
 reported_at timestamptz NOT NULL, reported_by uuid NOT NULL REFERENCES {{schema}}.accounts(id),
 reported_version bigint NOT NULL CHECK(reported_version>=3),
 resolution text CHECK(char_length(resolution) BETWEEN 1 AND 500),
 resolved_at timestamptz, resolved_by uuid REFERENCES {{schema}}.accounts(id), resolved_version bigint,
 FOREIGN KEY(instance_id,company_id,location_id) REFERENCES {{schema}}.task_instances(id,company_id,location_id),
 UNIQUE(instance_id,reported_version), UNIQUE(instance_id,resolved_version),
 CHECK((resolution IS NULL AND resolved_at IS NULL AND resolved_by IS NULL AND resolved_version IS NULL)
 OR (resolution IS NOT NULL AND resolved_at IS NOT NULL AND resolved_by IS NOT NULL AND resolved_version IS NOT NULL
 AND resolved_version>reported_version AND resolved_at>=reported_at))
);
CREATE UNIQUE INDEX task_blockings_one_open ON {{schema}}.task_blockings(instance_id) WHERE resolved_at IS NULL;
CREATE INDEX task_blockings_history ON {{schema}}.task_blockings(company_id,instance_id,reported_version DESC);
CREATE INDEX task_blocked_page ON {{schema}}.task_instances(company_id,location_id,id) WHERE status='blocked';
CREATE FUNCTION {{schema}}.protect_task_blocking() RETURNS trigger LANGUAGE plpgsql AS $$
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
  IF (to_jsonb(NEW)-ARRAY['resolution','resolved_at','resolved_by','resolved_version']) IS DISTINCT FROM
     (to_jsonb(OLD)-ARRAY['resolution','resolved_at','resolved_by','resolved_version'])
   OR OLD.resolved_at IS NOT NULL OR NEW.resolved_at IS NULL OR task.status<>'blocked'
   OR NEW.resolved_version<>task.version+1 THEN
   RAISE EXCEPTION 'Invalid resolution' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER task_blocking_immutable BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.task_blockings
 FOR EACH ROW EXECUTE FUNCTION {{schema}}.protect_task_blocking();
CREATE OR REPLACE FUNCTION {{schema}}.protect_task_step() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE task {{schema}}.task_instances; n integer;
BEGIN
 IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'Step results are immutable' USING ERRCODE='23514'; END IF;
 SELECT * INTO task FROM {{schema}}.task_instances WHERE id=NEW.instance_id FOR UPDATE;
 SELECT count(*) INTO n FROM {{schema}}.task_step_results WHERE instance_id=NEW.instance_id;
 IF task.status<>'in_progress' OR NEW.position<>n OR NEW.accepted_version<>task.version+1
  OR task.content::jsonb->'steps'->n->>'id' IS DISTINCT FROM NEW.step_id::text OR NEW.confirmed_at<task.started_at THEN
  RAISE EXCEPTION 'Invalid confirmation sequence' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE OR REPLACE FUNCTION {{schema}}.protect_task_instance() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n integer; active integer; valid boolean := false;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Instances cannot be deleted' USING ERRCODE='23514'; END IF;
 IF (to_jsonb(NEW)-ARRAY['title','status','version','started_at','started_by','completed_at','completed_by'])
  IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['title','status','version','started_at','started_by','completed_at','completed_by'])
  OR OLD.status='completed' OR NEW.version<>OLD.version+1 THEN
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
   SELECT active=0 AND EXISTS(SELECT 1 FROM {{schema}}.task_blockings WHERE instance_id=OLD.id AND resolved_version=NEW.version) INTO valid;
  ELSIF OLD.status='in_progress' AND NEW.status='in_progress' THEN
   SELECT active=0 AND EXISTS(SELECT 1 FROM {{schema}}.task_step_results WHERE instance_id=OLD.id AND accepted_version=NEW.version) INTO valid;
  ELSIF OLD.status='in_progress' AND NEW.status='completed' THEN
   valid := active=0 AND n=jsonb_array_length(OLD.content::jsonb->'steps');
  END IF;
 END IF;
 IF NOT valid THEN RAISE EXCEPTION 'Invalid execution transition' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
