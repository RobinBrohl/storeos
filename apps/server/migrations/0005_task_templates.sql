-- Owned by tasks. Scope IDs and published content never change.
CREATE TABLE {{schema}}.task_templates (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (id, company_id, location_id),
  FOREIGN KEY (location_id, company_id) REFERENCES {{schema}}.locations(id, company_id) ON DELETE RESTRICT
);
CREATE INDEX task_templates_company_page ON {{schema}}.task_templates(company_id, id);

CREATE TABLE {{schema}}.task_template_revisions (
  id uuid PRIMARY KEY,
  template_id uuid NOT NULL,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  revision_number integer NOT NULL CHECK (revision_number > 0),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published')),
  -- Compact canonical JSON preserves an exact UTF-8 size boundary across runtimes.
  content text NOT NULL CHECK (octet_length(content) <= 8192),
  title text GENERATED ALWAYS AS (content::jsonb ->> 'title') STORED NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  published_at timestamptz,
  published_by uuid REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  publication_version bigint,
  FOREIGN KEY (template_id, company_id, location_id)
    REFERENCES {{schema}}.task_templates(id, company_id, location_id) ON DELETE RESTRICT,
  UNIQUE (template_id, revision_number),
  CHECK (jsonb_typeof(content::jsonb) = 'object'
    AND content::jsonb ?& ARRAY['schemaVersion', 'title', 'steps']
    AND content::jsonb -> 'schemaVersion' = '1'::jsonb
    AND length(title) BETWEEN 1 AND 120
    AND jsonb_typeof(content::jsonb -> 'steps') = 'array'
    AND jsonb_array_length(content::jsonb -> 'steps') BETWEEN 0 AND 20),
  CHECK ((status = 'draft' AND published_at IS NULL AND published_by IS NULL AND publication_version IS NULL)
    OR (status = 'published' AND published_at IS NOT NULL AND published_by IS NOT NULL
      AND publication_version > 0 AND publication_version IS NOT NULL
      AND jsonb_array_length(content::jsonb -> 'steps') > 0))
);
CREATE UNIQUE INDEX task_templates_one_draft ON {{schema}}.task_template_revisions(template_id) WHERE status = 'draft';

CREATE FUNCTION {{schema}}.protect_template_revision() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'published' THEN
    RAISE EXCEPTION 'Published template revisions are immutable' USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER task_template_revision_immutable BEFORE UPDATE OR DELETE
  ON {{schema}}.task_template_revisions FOR EACH ROW EXECUTE FUNCTION {{schema}}.protect_template_revision();
