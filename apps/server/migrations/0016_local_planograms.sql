-- Merchandising owns exactly these six tables. Layout instructions contain
-- Article identities only; live labels, availability and Stock stay with owners.
CREATE TABLE {{schema}}.merchandising_fixtures (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES {{schema}}.companies(id) ON DELETE RESTRICT,
  location_id uuid NOT NULL,
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 120 AND name=btrim(name) AND name !~ '[[:cntrl:]]'),
  kind text NOT NULL CHECK (kind IN ('shelf','refrigerated_case','counter','display')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  version bigint NOT NULL DEFAULT 1 CHECK (version BETWEEN 1 AND 9007199254740991),
  current_assignment_id uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by uuid NOT NULL REFERENCES {{schema}}.accounts(id),
  retired_at timestamptz,
  retired_by uuid REFERENCES {{schema}}.accounts(id),
  UNIQUE (id,company_id,location_id),
  FOREIGN KEY (location_id,company_id) REFERENCES {{schema}}.locations(id,company_id) ON DELETE RESTRICT,
  CHECK ((status='retired')=(retired_at IS NOT NULL AND retired_by IS NOT NULL))
);
CREATE TABLE {{schema}}.merchandising_planograms (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES {{schema}}.companies(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  version bigint NOT NULL DEFAULT 1 CHECK (version BETWEEN 1 AND 9007199254740991),
  authoring_location_id uuid,
  origin_fixture_id uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by uuid NOT NULL REFERENCES {{schema}}.accounts(id),
  retired_at timestamptz,
  retired_by uuid REFERENCES {{schema}}.accounts(id),
  UNIQUE (id,company_id),
  FOREIGN KEY (authoring_location_id,company_id) REFERENCES {{schema}}.locations(id,company_id) ON DELETE RESTRICT,
  FOREIGN KEY (origin_fixture_id,company_id,authoring_location_id) REFERENCES {{schema}}.merchandising_fixtures(id,company_id,location_id) ON DELETE RESTRICT,
  CHECK (origin_fixture_id IS NULL OR authoring_location_id IS NOT NULL),
  CHECK ((status='retired')=(retired_at IS NOT NULL AND retired_by IS NOT NULL))
);
CREATE TABLE {{schema}}.merchandising_planogram_revisions (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  planogram_id uuid NOT NULL,
  revision_number integer NOT NULL CHECK (revision_number>0),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','discarded')),
  title text NOT NULL CHECK (length(title) BETWEEN 1 AND 120 AND title=btrim(title) AND title !~ '[[:cntrl:]]'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by uuid NOT NULL REFERENCES {{schema}}.accounts(id),
  published_at timestamptz,
  published_by uuid REFERENCES {{schema}}.accounts(id),
  publish_operation_id uuid UNIQUE,
  publish_expected_version bigint,
  publication_version bigint,
  discarded_at timestamptz,
  discarded_by uuid REFERENCES {{schema}}.accounts(id),
  UNIQUE (id,company_id),
  UNIQUE (planogram_id,revision_number),
  FOREIGN KEY (planogram_id,company_id) REFERENCES {{schema}}.merchandising_planograms(id,company_id) ON DELETE RESTRICT,
  CHECK ((status='published')=(published_at IS NOT NULL AND published_by IS NOT NULL AND publish_operation_id IS NOT NULL AND publish_expected_version IS NOT NULL AND publication_version IS NOT NULL AND publish_expected_version>0 AND publication_version=publish_expected_version+1)),
  CHECK ((status='discarded')=(discarded_at IS NOT NULL AND discarded_by IS NOT NULL))
);
CREATE UNIQUE INDEX merchandising_one_draft ON {{schema}}.merchandising_planogram_revisions(planogram_id) WHERE status='draft';
CREATE TABLE {{schema}}.merchandising_planogram_zones (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  label text NOT NULL CHECK (length(label) BETWEEN 1 AND 80 AND label=btrim(label) AND label !~ '[[:cntrl:]]'),
  ordinal integer NOT NULL CHECK (ordinal BETWEEN 1 AND 10),
  UNIQUE (id,company_id,revision_id),
  UNIQUE (revision_id,ordinal),
  FOREIGN KEY (revision_id,company_id) REFERENCES {{schema}}.merchandising_planogram_revisions(id,company_id) ON DELETE RESTRICT
);
CREATE TABLE {{schema}}.merchandising_planogram_placements (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  zone_id uuid NOT NULL,
  ordinal integer NOT NULL CHECK (ordinal BETWEEN 1 AND 100),
  article_id uuid NOT NULL,
  facings bigint CHECK (facings BETWEEN 1 AND 9007199254740991),
  UNIQUE (zone_id,ordinal),
  FOREIGN KEY (zone_id,company_id,revision_id) REFERENCES {{schema}}.merchandising_planogram_zones(id,company_id,revision_id) ON DELETE RESTRICT,
  FOREIGN KEY (article_id,company_id) REFERENCES {{schema}}.articles(id,company_id) ON DELETE RESTRICT
);
CREATE TABLE {{schema}}.merchandising_planogram_assignments (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  fixture_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  operation_id uuid NOT NULL UNIQUE,
  expected_version bigint NOT NULL CHECK (expected_version>0),
  applied_version bigint NOT NULL CHECK (applied_version=expected_version+1 AND applied_version<=9007199254740991),
  assigned_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  assigned_by uuid NOT NULL REFERENCES {{schema}}.accounts(id),
  UNIQUE (id,company_id,location_id,fixture_id),
  UNIQUE (fixture_id,applied_version),
  FOREIGN KEY (fixture_id,company_id,location_id) REFERENCES {{schema}}.merchandising_fixtures(id,company_id,location_id) ON DELETE RESTRICT,
  FOREIGN KEY (revision_id,company_id) REFERENCES {{schema}}.merchandising_planogram_revisions(id,company_id) ON DELETE RESTRICT
);
ALTER TABLE {{schema}}.merchandising_fixtures ADD CONSTRAINT merchandising_current_assignment_fk
  FOREIGN KEY (current_assignment_id,company_id,location_id,id)
  REFERENCES {{schema}}.merchandising_planogram_assignments(id,company_id,location_id,fixture_id) ON DELETE RESTRICT;

-- Protect frozen evidence even when the runtime role can edit draft content.
CREATE FUNCTION {{schema}}.merchandising_frozen_revision() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status <> 'draft' THEN RAISE EXCEPTION 'Frozen revision' USING ERRCODE='23514'; END IF;
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Revision evidence retained' USING ERRCODE='23514'; END IF;
  IF NEW.id<>OLD.id OR NEW.company_id<>OLD.company_id OR NEW.planogram_id<>OLD.planogram_id OR NEW.revision_number<>OLD.revision_number OR NEW.created_at<>OLD.created_at OR NEW.created_by<>OLD.created_by THEN
    RAISE EXCEPTION 'Revision identity immutable' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER merchandising_revision_immutable BEFORE UPDATE OR DELETE ON {{schema}}.merchandising_planogram_revisions FOR EACH ROW EXECUTE FUNCTION {{schema}}.merchandising_frozen_revision();
CREATE FUNCTION {{schema}}.merchandising_draft_child() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE rid uuid; cid uuid;
BEGIN
  IF TG_OP<>'INSERT' THEN
    rid:=OLD.revision_id; cid:=OLD.company_id;
    PERFORM 1 FROM {{schema}}.merchandising_planogram_revisions WHERE id=rid AND company_id=cid AND status='draft' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Frozen layout' USING ERRCODE='23514'; END IF;
  END IF;
  IF TG_OP<>'DELETE' THEN
    PERFORM 1 FROM {{schema}}.merchandising_planogram_revisions WHERE id=NEW.revision_id AND company_id=NEW.company_id AND status='draft' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Frozen layout' USING ERRCODE='23514'; END IF;
    RETURN NEW;
  END IF;
  RETURN OLD;
END $$;
CREATE TRIGGER merchandising_zone_immutable BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.merchandising_planogram_zones FOR EACH ROW EXECUTE FUNCTION {{schema}}.merchandising_draft_child();
CREATE TRIGGER merchandising_placement_immutable BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.merchandising_planogram_placements FOR EACH ROW EXECUTE FUNCTION {{schema}}.merchandising_draft_child();
CREATE FUNCTION {{schema}}.merchandising_assignment_evidence() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'Assignment append only' USING ERRCODE='23514'; END IF;
  PERFORM 1 FROM {{schema}}.merchandising_planogram_revisions WHERE id=NEW.revision_id AND company_id=NEW.company_id AND status='published' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Published revision required' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER merchandising_assignment_immutable BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.merchandising_planogram_assignments FOR EACH ROW EXECUTE FUNCTION {{schema}}.merchandising_assignment_evidence();

CREATE FUNCTION {{schema}}.merchandising_terminal_resource() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' OR OLD.status='retired' THEN RAISE EXCEPTION 'Resource evidence retained' USING ERRCODE='23514'; END IF;
  IF NEW.id<>OLD.id OR NEW.company_id<>OLD.company_id OR NEW.created_at<>OLD.created_at OR NEW.created_by<>OLD.created_by THEN RAISE EXCEPTION 'Identity immutable' USING ERRCODE='23514'; END IF;
  IF TG_TABLE_NAME='merchandising_fixtures' THEN
    IF NEW.location_id<>OLD.location_id THEN RAISE EXCEPTION 'Location immutable' USING ERRCODE='23514'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER merchandising_fixture_terminal BEFORE UPDATE OR DELETE ON {{schema}}.merchandising_fixtures FOR EACH ROW EXECUTE FUNCTION {{schema}}.merchandising_terminal_resource();
CREATE TRIGGER merchandising_planogram_terminal BEFORE UPDATE OR DELETE ON {{schema}}.merchandising_planograms FOR EACH ROW EXECUTE FUNCTION {{schema}}.merchandising_terminal_resource();
