-- Tasks owns execution within the existing instance aggregate.
ALTER TABLE {{schema}}.task_instances
  DROP CONSTRAINT task_instances_status_check,
  DROP CONSTRAINT task_instances_version_check,
  ADD COLUMN started_at timestamptz,
  ADD COLUMN started_by uuid REFERENCES {{schema}}.accounts(id),
  ADD COLUMN completed_at timestamptz,
  ADD COLUMN completed_by uuid REFERENCES {{schema}}.accounts(id),
  ADD CONSTRAINT task_execution_status CHECK(status IN ('open','in_progress','completed')),
  ADD CONSTRAINT task_execution_version CHECK(version > 0),
  ADD CONSTRAINT task_execution_scope UNIQUE(id,company_id,location_id),
  ADD CONSTRAINT task_execution_times CHECK(
    (status='open' AND version=1 AND started_at IS NULL AND started_by IS NULL AND completed_at IS NULL AND completed_by IS NULL)
    OR (status='in_progress' AND version>=2 AND started_at IS NOT NULL AND started_by IS NOT NULL AND completed_at IS NULL AND completed_by IS NULL)
    OR (status='completed' AND started_at IS NOT NULL AND started_by IS NOT NULL AND completed_at>=started_at AND completed_at IS NOT NULL AND completed_by IS NOT NULL));
CREATE INDEX task_execution_running ON {{schema}}.task_instances(company_id,location_id,employee_id,id) WHERE status='in_progress';
CREATE TABLE {{schema}}.task_step_results (
  instance_id uuid NOT NULL, company_id uuid NOT NULL, location_id uuid NOT NULL,
  step_id uuid NOT NULL, position integer NOT NULL CHECK(position BETWEEN 0 AND 19),
  confirmed_at timestamptz NOT NULL, confirmed_by uuid NOT NULL REFERENCES {{schema}}.accounts(id),
  PRIMARY KEY(instance_id,step_id), UNIQUE(instance_id,position),
  FOREIGN KEY(instance_id,company_id,location_id) REFERENCES {{schema}}.task_instances(id,company_id,location_id)
);
CREATE TABLE {{schema}}.task_execution_commands (
  operation_id uuid PRIMARY KEY, company_id uuid NOT NULL, location_id uuid NOT NULL,
  instance_id uuid NOT NULL, actor_id uuid NOT NULL REFERENCES {{schema}}.accounts(id),
  input text NOT NULL CHECK(octet_length(input)<=1024),
  result text NOT NULL CHECK(octet_length(result)<=8192),
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(instance_id,company_id,location_id) REFERENCES {{schema}}.task_instances(id,company_id,location_id)
);
CREATE OR REPLACE FUNCTION {{schema}}.protect_task_instance() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Instances cannot be deleted' USING ERRCODE='23514'; END IF;
  IF (to_jsonb(NEW)-ARRAY['title','status','version','started_at','started_by','completed_at','completed_by'])
      IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['title','status','version','started_at','started_by','completed_at','completed_by'])
      OR OLD.status='completed' OR NEW.version<>OLD.version+1 THEN
    RAISE EXCEPTION 'Immutable instance or invalid version' USING ERRCODE='23514';
  END IF;
  SELECT count(*) INTO n FROM {{schema}}.task_step_results WHERE instance_id=OLD.id;
  IF OLD.status='open' THEN
    IF NEW.status<>'in_progress' OR n<>0 THEN RAISE EXCEPTION 'Invalid start' USING ERRCODE='23514'; END IF;
  ELSE
    IF NEW.started_at IS DISTINCT FROM OLD.started_at OR NEW.started_by IS DISTINCT FROM OLD.started_by
      OR NEW.status NOT IN ('in_progress','completed')
      OR (NEW.status='in_progress' AND NEW.version<>n+2)
      OR (NEW.status='completed' AND (n<>jsonb_array_length(OLD.content::jsonb->'steps') OR NEW.version<>n+3)) THEN
      RAISE EXCEPTION 'Invalid execution transition' USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NEW;
END; $$;
CREATE FUNCTION {{schema}}.protect_task_step() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE task {{schema}}.task_instances; n integer;
BEGIN
  IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'Step results are immutable' USING ERRCODE='23514'; END IF;
  SELECT * INTO task FROM {{schema}}.task_instances WHERE id=NEW.instance_id FOR UPDATE;
  SELECT count(*) INTO n FROM {{schema}}.task_step_results WHERE instance_id=NEW.instance_id;
  IF task.status<>'in_progress' OR NEW.position<>n OR task.version<>n+2
    OR task.content::jsonb->'steps'->n->>'id' IS DISTINCT FROM NEW.step_id::text
    OR NEW.confirmed_at<task.started_at THEN
    RAISE EXCEPTION 'Invalid confirmation sequence' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER task_step_immutable BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.task_step_results
  FOR EACH ROW EXECUTE FUNCTION {{schema}}.protect_task_step();
