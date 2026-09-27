-- Workforce owns shifts and ordered explicit revision selections.
ALTER TABLE {{schema}}.task_template_revisions ADD CONSTRAINT revision_scope_unique
  UNIQUE (id, template_id, company_id, location_id);
CREATE TABLE {{schema}}.shifts (
  id uuid PRIMARY KEY, company_id uuid NOT NULL, location_id uuid NOT NULL,
  employee_id uuid NOT NULL, starts_at timestamptz NOT NULL, ends_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')),
  version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(), updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by uuid NOT NULL REFERENCES {{schema}}.accounts(id),
  creation_input text NOT NULL CHECK (octet_length(creation_input) <= 8192),
  published_at timestamptz, published_by uuid REFERENCES {{schema}}.accounts(id), publication_version bigint,
  CHECK (starts_at < ends_at),
  CHECK ((status='draft' AND published_at IS NULL AND published_by IS NULL AND publication_version IS NULL)
    OR (status='published' AND published_at IS NOT NULL AND published_by IS NOT NULL AND publication_version IS NOT NULL AND publication_version > 0)),
  UNIQUE(id, company_id, location_id), UNIQUE(id, company_id, location_id, employee_id),
  FOREIGN KEY(employee_id, company_id, location_id) REFERENCES {{schema}}.employees(id, company_id, location_id)
);
CREATE INDEX shifts_page ON {{schema}}.shifts(company_id, starts_at, id);
CREATE INDEX shifts_employee_time ON {{schema}}.shifts(company_id, employee_id, starts_at, ends_at) WHERE status='published';
CREATE TABLE {{schema}}.shift_template_selections (
  shift_id uuid NOT NULL, company_id uuid NOT NULL, location_id uuid NOT NULL,
  template_id uuid NOT NULL, revision_id uuid NOT NULL, position integer NOT NULL CHECK(position BETWEEN 0 AND 9),
  PRIMARY KEY(shift_id, template_id), UNIQUE(shift_id, position),
  FOREIGN KEY(shift_id, company_id, location_id) REFERENCES {{schema}}.shifts(id, company_id, location_id),
  FOREIGN KEY(revision_id, template_id, company_id, location_id) REFERENCES {{schema}}.task_template_revisions(id, template_id, company_id, location_id)
);
-- Tasks owns immutable instruction snapshots, independent of later template edits.
CREATE TABLE {{schema}}.task_instances (
  id uuid PRIMARY KEY, company_id uuid NOT NULL, location_id uuid NOT NULL,
  shift_id uuid NOT NULL, employee_id uuid NOT NULL, template_id uuid NOT NULL, revision_id uuid NOT NULL,
  position integer NOT NULL CHECK(position BETWEEN 0 AND 9),
  content text NOT NULL CHECK(octet_length(content) <= 8192),
  title text GENERATED ALWAYS AS (content::jsonb ->> 'title') STORED NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK(status='open'), version bigint NOT NULL DEFAULT 1 CHECK(version=1),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(shift_id, template_id), UNIQUE(shift_id, position),
  CHECK (content::jsonb -> 'schemaVersion' = '1'::jsonb AND jsonb_array_length(content::jsonb -> 'steps') BETWEEN 1 AND 20),
  FOREIGN KEY(shift_id, company_id, location_id, employee_id) REFERENCES {{schema}}.shifts(id, company_id, location_id, employee_id),
  FOREIGN KEY(revision_id, template_id, company_id, location_id) REFERENCES {{schema}}.task_template_revisions(id, template_id, company_id, location_id)
);
CREATE FUNCTION {{schema}}.protect_published_shift() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status='published' THEN RAISE EXCEPTION 'Published shifts are immutable' USING ERRCODE='23514'; END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER shifts_immutable BEFORE UPDATE OR DELETE ON {{schema}}.shifts FOR EACH ROW EXECUTE FUNCTION {{schema}}.protect_published_shift();
CREATE FUNCTION {{schema}}.protect_shift_selection() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM {{schema}}.shifts WHERE id=CASE WHEN TG_OP='DELETE' THEN OLD.shift_id ELSE NEW.shift_id END AND status='published') THEN
    RAISE EXCEPTION 'Published selections are immutable' USING ERRCODE='23514';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER selections_immutable BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.shift_template_selections FOR EACH ROW EXECUTE FUNCTION {{schema}}.protect_shift_selection();
CREATE FUNCTION {{schema}}.protect_task_instance() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Task instances are read only in P1b.3' USING ERRCODE='23514';
END; $$;
CREATE TRIGGER instances_immutable BEFORE UPDATE OR DELETE ON {{schema}}.task_instances FOR EACH ROW EXECUTE FUNCTION {{schema}}.protect_task_instance();
