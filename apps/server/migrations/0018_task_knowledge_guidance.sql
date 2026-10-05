-- Retain the original schema-1/2 validator and all old content bytes/evidence.
ALTER FUNCTION {{schema}}.valid_task_content(text) RENAME TO valid_legacy_task_content;
CREATE FUNCTION {{schema}}.valid_task_content(content text) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE body jsonb := content::jsonb; guidance jsonb;
BEGIN
  IF body->'schemaVersion' IN ('1'::jsonb,'2'::jsonb) THEN
    RETURN NOT body ? 'knowledgeGuidance' AND {{schema}}.valid_legacy_task_content(content);
  END IF;
  IF body->'schemaVersion' IS DISTINCT FROM '3'::jsonb
    OR jsonb_typeof(body) IS DISTINCT FROM 'object'
    OR NOT body ?& ARRAY['schemaVersion','title','steps','knowledgeGuidance']
    OR (SELECT count(*) FROM jsonb_object_keys(body))<>4 THEN RETURN false; END IF;
  guidance := body->'knowledgeGuidance';
  IF guidance<>'null'::jsonb THEN
    IF jsonb_typeof(guidance) IS DISTINCT FROM 'object'
      OR NOT guidance ?& ARRAY['articleId','revisionId']
      OR (SELECT count(*) FROM jsonb_object_keys(guidance))<>2
      OR jsonb_typeof(guidance->'articleId') IS DISTINCT FROM 'string'
      OR jsonb_typeof(guidance->'revisionId') IS DISTINCT FROM 'string'
      OR (guidance->>'articleId') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR (guidance->>'revisionId') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN RETURN false; END IF;
  END IF;
  RETURN {{schema}}.valid_legacy_task_content(
    ((body-'knowledgeGuidance') || '{"schemaVersion":2}'::jsonb)::text);
EXCEPTION WHEN OTHERS THEN RETURN false;
END $$;
ALTER TABLE {{schema}}.task_template_revisions DROP CONSTRAINT task_revision_content_schema;
ALTER TABLE {{schema}}.task_instances DROP CONSTRAINT task_instance_content_schema;
ALTER TABLE {{schema}}.task_template_revisions ADD CONSTRAINT task_revision_content_schema
  CHECK ({{schema}}.valid_task_content(content));
ALTER TABLE {{schema}}.task_instances ADD CONSTRAINT task_instance_content_schema
  CHECK ({{schema}}.valid_task_content(content) AND jsonb_array_length(content::jsonb->'steps') BETWEEN 1 AND 20);

-- Each field derives independently from immutable source content, never another
-- generated field. Durable published identity does not depend on Article activity.
ALTER TABLE {{schema}}.task_template_revisions
  ADD COLUMN knowledge_article_id uuid GENERATED ALWAYS AS ((content::jsonb #>> '{knowledgeGuidance,articleId}')::uuid) STORED,
  ADD COLUMN knowledge_revision_id uuid GENERATED ALWAYS AS ((content::jsonb #>> '{knowledgeGuidance,revisionId}')::uuid) STORED,
  ADD COLUMN knowledge_revision_state text GENERATED ALWAYS AS
    (CASE WHEN content::jsonb->'knowledgeGuidance'<>'null'::jsonb THEN 'published'::text END) STORED,
  ADD CONSTRAINT task_revision_knowledge_fk FOREIGN KEY (knowledge_revision_id,company_id,knowledge_article_id,knowledge_revision_state)
    REFERENCES {{schema}}.knowledge_revisions(id,company_id,article_id,status);
ALTER TABLE {{schema}}.task_instances
  ADD COLUMN knowledge_article_id uuid GENERATED ALWAYS AS ((content::jsonb #>> '{knowledgeGuidance,articleId}')::uuid) STORED,
  ADD COLUMN knowledge_revision_id uuid GENERATED ALWAYS AS ((content::jsonb #>> '{knowledgeGuidance,revisionId}')::uuid) STORED,
  ADD COLUMN knowledge_revision_state text GENERATED ALWAYS AS
    (CASE WHEN content::jsonb->'knowledgeGuidance'<>'null'::jsonb THEN 'published'::text END) STORED,
  ADD CONSTRAINT task_instance_knowledge_fk FOREIGN KEY (knowledge_revision_id,company_id,knowledge_article_id,knowledge_revision_state)
    REFERENCES {{schema}}.knowledge_revisions(id,company_id,article_id,status);

CREATE FUNCTION {{schema}}.check_task_guidance_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE source_content text;
BEGIN
  SELECT content INTO source_content FROM {{schema}}.task_template_revisions
    WHERE id=NEW.revision_id AND template_id=NEW.template_id
      AND company_id=NEW.company_id AND location_id=NEW.location_id AND status='published';
  IF source_content IS NULL OR
    (source_content::jsonb->'knowledgeGuidance') IS DISTINCT FROM (NEW.content::jsonb->'knowledgeGuidance') THEN
    RAISE EXCEPTION 'Task guidance must match its published template' USING ERRCODE='23514',CONSTRAINT='task_guidance_snapshot';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER task_guidance_snapshot BEFORE INSERT ON {{schema}}.task_instances
  FOR EACH ROW EXECUTE FUNCTION {{schema}}.check_task_guidance_snapshot();
-- Existing published Template and Task snapshot guards/grants remain intact.

-- BEFORE triggers cannot inspect NEW generated fields. Content stays protected;
-- all existing transition/version/evidence checks below are preserved.
CREATE OR REPLACE FUNCTION {{schema}}.protect_task_instance() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n integer; active integer; valid boolean := false;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Instances cannot be deleted' USING ERRCODE='23514'; END IF;
 IF (to_jsonb(NEW)-ARRAY['knowledge_article_id','knowledge_revision_id','knowledge_revision_state','title','status','version','started_at','started_by','completed_at','completed_by','cancelled_at','cancelled_by'])
  IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['knowledge_article_id','knowledge_revision_id','knowledge_revision_state','title','status','version','started_at','started_by','completed_at','completed_by','cancelled_at','cancelled_by'])
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

