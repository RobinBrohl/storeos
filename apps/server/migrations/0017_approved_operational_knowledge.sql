-- Knowledge owns two tables. Publication is approval; no receipt/outbox.
CREATE TABLE {{schema}}.knowledge_articles (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES {{schema}}.companies(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  version bigint NOT NULL DEFAULT 1 CHECK (version BETWEEN 1 AND 9007199254740991),
  current_published_revision_id uuid,
  active_draft_revision_id uuid,
  current_published_state text GENERATED ALWAYS AS
    (CASE WHEN current_published_revision_id IS NOT NULL THEN 'published'::text END) STORED,
  active_draft_state text GENERATED ALWAYS AS
    (CASE WHEN active_draft_revision_id IS NOT NULL THEN 'draft'::text END) STORED,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by uuid NOT NULL REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  retired_at timestamptz,
  retired_by uuid REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  UNIQUE (id,company_id),
  CHECK ((status='active' AND retired_at IS NULL AND retired_by IS NULL) OR
    (status='retired' AND retired_at IS NOT NULL AND retired_by IS NOT NULL AND active_draft_revision_id IS NULL))
);
CREATE TABLE {{schema}}.knowledge_revisions (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  article_id uuid NOT NULL,
  revision_number integer NOT NULL CHECK (revision_number>0),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','discarded')),
  title text NOT NULL,
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by uuid NOT NULL REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  published_at timestamptz,
  published_by uuid REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  publish_operation_id uuid,
  publish_expected_version bigint,
  publication_version bigint,
  discarded_at timestamptz,
  discarded_by uuid REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  CONSTRAINT knowledge_revision_number_unique UNIQUE (article_id,revision_number),
  CONSTRAINT knowledge_publication_operation_unique UNIQUE (company_id,publish_operation_id),
  UNIQUE (id,company_id,article_id,status),
  FOREIGN KEY (article_id,company_id) REFERENCES {{schema}}.knowledge_articles(id,company_id) ON DELETE RESTRICT,
  CONSTRAINT knowledge_content_bounds CHECK
    (length(title)<=120 AND title !~ '[\x01-\x1F\x7F]' AND position(chr(13) in body)=0 AND
     octet_length(title)+octet_length(body)<=8192),
  CONSTRAINT knowledge_publication_evidence CHECK (
    (status='published' AND published_at IS NOT NULL AND published_by IS NOT NULL AND
      publish_operation_id IS NOT NULL AND publish_expected_version IS NOT NULL AND
      publish_expected_version BETWEEN 1 AND 9007199254740990 AND publication_version IS NOT NULL AND
      publication_version=publish_expected_version+1 AND title !~ '^[[:space:]]*$' AND body !~ '^[[:space:]]*$') OR
    (status<>'published' AND published_at IS NULL AND published_by IS NULL AND publish_operation_id IS NULL AND
      publish_expected_version IS NULL AND publication_version IS NULL)),
  CONSTRAINT knowledge_discard_evidence CHECK (
    (status='discarded' AND discarded_at IS NOT NULL AND discarded_by IS NOT NULL) OR
    (status<>'discarded' AND discarded_at IS NULL AND discarded_by IS NULL))
);
CREATE UNIQUE INDEX knowledge_one_draft ON {{schema}}.knowledge_revisions(article_id) WHERE status='draft';
ALTER TABLE {{schema}}.knowledge_articles ADD CONSTRAINT knowledge_current_published_fk
  FOREIGN KEY (current_published_revision_id,company_id,id,current_published_state)
  REFERENCES {{schema}}.knowledge_revisions(id,company_id,article_id,status) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE {{schema}}.knowledge_articles ADD CONSTRAINT knowledge_active_draft_fk
  FOREIGN KEY (active_draft_revision_id,company_id,id,active_draft_state)
  REFERENCES {{schema}}.knowledge_revisions(id,company_id,article_id,status) DEFERRABLE INITIALLY DEFERRED;

-- FKs protect pointer state/ownership. Triggers freeze evidence and serialize
-- monotonic allocation, including writers outside the application Company lock.
CREATE FUNCTION {{schema}}.knowledge_revision_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE article_status text; next_number integer;
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'Knowledge evidence retained' USING ERRCODE='23514',CONSTRAINT='knowledge_revision_retained';
  END IF;
  IF TG_OP='UPDATE' THEN
    IF OLD.status<>'draft' OR NEW.id<>OLD.id OR NEW.company_id<>OLD.company_id OR
      NEW.article_id<>OLD.article_id OR NEW.revision_number<>OLD.revision_number OR
      NEW.created_at<>OLD.created_at OR NEW.created_by<>OLD.created_by THEN
      RAISE EXCEPTION 'Knowledge revision frozen' USING ERRCODE='23514',CONSTRAINT='knowledge_revision_frozen';
    END IF;
  END IF;
  SELECT status INTO article_status FROM {{schema}}.knowledge_articles
    WHERE id=NEW.article_id AND company_id=NEW.company_id FOR UPDATE;
  IF article_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Active Knowledge article required' USING ERRCODE='23514',CONSTRAINT='knowledge_article_active';
  END IF;
  IF TG_OP='INSERT' THEN
    SELECT COALESCE(max(revision_number),0)+1 INTO next_number FROM {{schema}}.knowledge_revisions
      WHERE article_id=NEW.article_id AND company_id=NEW.company_id;
    IF NEW.status<>'draft' OR NEW.revision_number<>next_number THEN
      RAISE EXCEPTION 'Next draft revision required' USING ERRCODE='23514',CONSTRAINT='knowledge_next_revision';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER knowledge_revision_guard BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.knowledge_revisions
  FOR EACH ROW EXECUTE FUNCTION {{schema}}.knowledge_revision_guard();
CREATE FUNCTION {{schema}}.knowledge_article_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' OR OLD.status='retired' THEN
    RAISE EXCEPTION 'Knowledge article retained/terminal' USING ERRCODE='23514',CONSTRAINT='knowledge_article_terminal';
  END IF;
  IF NEW.id<>OLD.id OR NEW.company_id<>OLD.company_id OR NEW.created_at<>OLD.created_at OR NEW.created_by<>OLD.created_by THEN
    RAISE EXCEPTION 'Knowledge identity immutable' USING ERRCODE='23514',CONSTRAINT='knowledge_article_identity';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER knowledge_article_guard BEFORE UPDATE OR DELETE ON {{schema}}.knowledge_articles
  FOR EACH ROW EXECUTE FUNCTION {{schema}}.knowledge_article_guard();
