-- Schemas 1-3 retain the exact predecessor validator and stored evidence.
ALTER FUNCTION {{schema}}.valid_task_content(text) RENAME TO valid_pre_planogram_task_content;
CREATE FUNCTION {{schema}}.valid_task_content(content text) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE body jsonb := content::jsonb; pin jsonb;
BEGIN
  IF body->'schemaVersion' IN ('1'::jsonb,'2'::jsonb,'3'::jsonb) THEN
    RETURN NOT body ? 'planogramGuidance' AND {{schema}}.valid_pre_planogram_task_content(content);
  END IF;
  IF body->'schemaVersion' IS DISTINCT FROM '4'::jsonb
    OR jsonb_typeof(body) IS DISTINCT FROM 'object'
    OR NOT body ?& ARRAY['schemaVersion','title','steps','knowledgeGuidance','planogramGuidance']
    OR (SELECT count(*) FROM jsonb_object_keys(body))<>5
    OR octet_length(content)>8192 THEN RETURN false; END IF;
  pin := body->'planogramGuidance';
  IF pin<>'null'::jsonb THEN
    IF jsonb_typeof(pin) IS DISTINCT FROM 'object'
      OR NOT pin ?& ARRAY['fixtureId','assignmentId','revisionId']
      OR (SELECT count(*) FROM jsonb_object_keys(pin))<>3
      OR jsonb_typeof(pin->'fixtureId') IS DISTINCT FROM 'string'
      OR jsonb_typeof(pin->'assignmentId') IS DISTINCT FROM 'string'
      OR jsonb_typeof(pin->'revisionId') IS DISTINCT FROM 'string'
      OR (pin->>'fixtureId') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR (pin->>'assignmentId') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR (pin->>'revisionId') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN RETURN false; END IF;
  END IF;
  RETURN {{schema}}.valid_pre_planogram_task_content(
    ((body-'planogramGuidance') || '{"schemaVersion":3}'::jsonb)::text);
EXCEPTION WHEN OTHERS THEN RETURN false;
END $$;
ALTER TABLE {{schema}}.task_template_revisions DROP CONSTRAINT task_revision_content_schema;
ALTER TABLE {{schema}}.task_instances DROP CONSTRAINT task_instance_content_schema;
ALTER TABLE {{schema}}.task_template_revisions ADD CONSTRAINT task_revision_content_schema
  CHECK ({{schema}}.valid_task_content(content));
ALTER TABLE {{schema}}.task_instances ADD CONSTRAINT task_instance_content_schema
  CHECK ({{schema}}.valid_task_content(content) AND jsonb_array_length(content::jsonb->'steps') BETWEEN 1 AND 20);

-- Assignment evidence is append-only and published-only. Current/lifecycle state
-- is intentionally absent from this permanent key and retained foreign keys.
ALTER TABLE {{schema}}.merchandising_planogram_assignments
  ADD CONSTRAINT merchandising_assignment_deployment_key UNIQUE (id,company_id,location_id,fixture_id,revision_id);

ALTER TABLE {{schema}}.task_template_revisions
  ADD COLUMN planogram_fixture_id uuid GENERATED ALWAYS AS ((content::jsonb #>> '{planogramGuidance,fixtureId}')::uuid) STORED,
  ADD COLUMN planogram_assignment_id uuid GENERATED ALWAYS AS ((content::jsonb #>> '{planogramGuidance,assignmentId}')::uuid) STORED,
  ADD COLUMN planogram_revision_id uuid GENERATED ALWAYS AS ((content::jsonb #>> '{planogramGuidance,revisionId}')::uuid) STORED,
  ADD CONSTRAINT task_revision_planogram_fk FOREIGN KEY (planogram_assignment_id,company_id,location_id,planogram_fixture_id,planogram_revision_id)
    REFERENCES {{schema}}.merchandising_planogram_assignments(id,company_id,location_id,fixture_id,revision_id) ON DELETE RESTRICT;

ALTER TABLE {{schema}}.task_instances
  ADD COLUMN planogram_fixture_id uuid GENERATED ALWAYS AS ((content::jsonb #>> '{planogramGuidance,fixtureId}')::uuid) STORED,
  ADD COLUMN planogram_assignment_id uuid GENERATED ALWAYS AS ((content::jsonb #>> '{planogramGuidance,assignmentId}')::uuid) STORED,
  ADD COLUMN planogram_revision_id uuid GENERATED ALWAYS AS ((content::jsonb #>> '{planogramGuidance,revisionId}')::uuid) STORED,
  ADD CONSTRAINT task_instance_planogram_fk FOREIGN KEY (planogram_assignment_id,company_id,location_id,planogram_fixture_id,planogram_revision_id)
    REFERENCES {{schema}}.merchandising_planogram_assignments(id,company_id,location_id,fixture_id,revision_id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION {{schema}}.check_task_guidance_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE source_content text;
BEGIN
  SELECT content INTO source_content FROM {{schema}}.task_template_revisions
    WHERE id=NEW.revision_id AND template_id=NEW.template_id
      AND company_id=NEW.company_id AND location_id=NEW.location_id AND status='published';
  IF source_content IS NULL OR
    (source_content::jsonb->'knowledgeGuidance') IS DISTINCT FROM (NEW.content::jsonb->'knowledgeGuidance') OR
    (source_content::jsonb->'planogramGuidance') IS DISTINCT FROM (NEW.content::jsonb->'planogramGuidance') THEN
    RAISE EXCEPTION 'Task guidance must match its published template' USING ERRCODE='23514',CONSTRAINT='task_guidance_snapshot';
  END IF;
  RETURN NEW;
END $$;

-- BEFORE triggers cannot inspect newly computed generated fields. The immutable
-- source content and every existing execution transition/evidence check remain.
CREATE OR REPLACE FUNCTION {{schema}}.protect_task_instance() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n integer; active integer; valid boolean := false;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Instances cannot be deleted' USING ERRCODE='23514'; END IF;
 IF (to_jsonb(NEW)-ARRAY['knowledge_article_id','knowledge_revision_id','knowledge_revision_state','planogram_fixture_id','planogram_assignment_id','planogram_revision_id','title','status','version','started_at','started_by','completed_at','completed_by','cancelled_at','cancelled_by'])
  IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['knowledge_article_id','knowledge_revision_id','knowledge_revision_state','planogram_fixture_id','planogram_assignment_id','planogram_revision_id','title','status','version','started_at','started_by','completed_at','completed_by','cancelled_at','cancelled_by'])
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


-- MigrationRunner retains column-restricted runtime UPDATE grants. No new grant.
