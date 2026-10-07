CREATE VIEW {{schema}}.inventory_recipe_article_projection AS
  SELECT id,company_id,sku,name,unit,is_active FROM {{schema}}.articles;

-- Production owns composition evidence. Inventory releases only Article context; no Stock effect.
CREATE TABLE {{schema}}.production_recipes (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES {{schema}}.companies(id) ON DELETE RESTRICT,
  produced_article_id uuid NOT NULL,
  CONSTRAINT recipe_produced_unique UNIQUE (company_id,produced_article_id),
  FOREIGN KEY (produced_article_id,company_id) REFERENCES {{schema}}.articles(id,company_id) ON DELETE RESTRICT,
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
CREATE TABLE {{schema}}.production_recipe_revisions (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  recipe_id uuid NOT NULL,
  revision_number integer NOT NULL CHECK (revision_number>0),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','discarded')),
  produced_sku text NOT NULL,
  produced_name text NOT NULL,
  produced_unit text NOT NULL,
  batch_description text NOT NULL,
  preparation text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by uuid NOT NULL REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  published_at timestamptz,
  published_by uuid REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  publish_operation_id uuid,
  publish_expected_version bigint,
  publication_version bigint,
  discarded_at timestamptz,
  discarded_by uuid REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  CONSTRAINT recipe_revision_number_unique UNIQUE (recipe_id,revision_number),
  CONSTRAINT recipe_publication_operation_unique UNIQUE (company_id,publish_operation_id),
  UNIQUE (id,company_id,recipe_id,status),
  UNIQUE (id,company_id,recipe_id),
  FOREIGN KEY (recipe_id,company_id) REFERENCES {{schema}}.production_recipes(id,company_id) ON DELETE RESTRICT,
  CONSTRAINT recipe_content_bounds CHECK
    (length(batch_description)<=120 AND batch_description !~ '[\x01-\x1F\x7F]' AND position(chr(13) in preparation)=0 AND
     octet_length(preparation)<=8192 AND length(produced_sku) BETWEEN 1 AND 64 AND length(produced_name) BETWEEN 1 AND 200 AND length(produced_unit) BETWEEN 1 AND 32),
  CONSTRAINT recipe_publication_evidence CHECK (
    (status='published' AND published_at IS NOT NULL AND published_by IS NOT NULL AND
      publish_operation_id IS NOT NULL AND publish_expected_version IS NOT NULL AND
      publish_expected_version BETWEEN 1 AND 9007199254740990 AND publication_version IS NOT NULL AND
      publication_version=publish_expected_version+1 AND batch_description !~ '^[[:space:]]*$' AND preparation !~ '^[[:space:]]*$') OR
    (status<>'published' AND published_at IS NULL AND published_by IS NULL AND publish_operation_id IS NULL AND
      publish_expected_version IS NULL AND publication_version IS NULL)),
  CONSTRAINT recipe_discard_evidence CHECK (
    (status='discarded' AND discarded_at IS NOT NULL AND discarded_by IS NOT NULL) OR
    (status<>'discarded' AND discarded_at IS NULL AND discarded_by IS NULL))
);
CREATE UNIQUE INDEX recipe_one_draft ON {{schema}}.production_recipe_revisions(recipe_id) WHERE status='draft';
ALTER TABLE {{schema}}.production_recipes ADD CONSTRAINT recipe_current_published_fk
  FOREIGN KEY (current_published_revision_id,company_id,id,current_published_state)
  REFERENCES {{schema}}.production_recipe_revisions(id,company_id,recipe_id,status) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE {{schema}}.production_recipes ADD CONSTRAINT recipe_active_draft_fk
  FOREIGN KEY (active_draft_revision_id,company_id,id,active_draft_state)
  REFERENCES {{schema}}.production_recipe_revisions(id,company_id,recipe_id,status) DEFERRABLE INITIALLY DEFERRED;

-- FKs protect pointer state/ownership. Triggers freeze evidence and serialize
-- monotonic allocation, including writers outside the application Company lock.
CREATE FUNCTION {{schema}}.recipe_revision_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE recipe_status text; next_number integer;
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'Recipe evidence retained' USING ERRCODE='23514',CONSTRAINT='recipe_revision_retained';
  END IF;
  IF TG_OP='UPDATE' THEN
    IF OLD.status<>'draft' OR NEW.id<>OLD.id OR NEW.company_id<>OLD.company_id OR
      NEW.recipe_id<>OLD.recipe_id OR NEW.revision_number<>OLD.revision_number OR
      NEW.created_at<>OLD.created_at OR NEW.created_by<>OLD.created_by OR
      NEW.produced_sku<>OLD.produced_sku OR NEW.produced_name<>OLD.produced_name OR NEW.produced_unit<>OLD.produced_unit THEN
      RAISE EXCEPTION 'Recipe revision frozen' USING ERRCODE='23514',CONSTRAINT='recipe_revision_frozen';
    END IF;
  END IF;
  SELECT status INTO recipe_status FROM {{schema}}.production_recipes
    WHERE id=NEW.recipe_id AND company_id=NEW.company_id FOR UPDATE;
  IF recipe_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Active Recipe article required' USING ERRCODE='23514',CONSTRAINT='recipe_article_active';
  END IF;
  IF TG_OP='INSERT' THEN
    SELECT COALESCE(max(revision_number),0)+1 INTO next_number FROM {{schema}}.production_recipe_revisions
      WHERE recipe_id=NEW.recipe_id AND company_id=NEW.company_id;
    IF NEW.status<>'draft' OR NEW.revision_number<>next_number THEN
      RAISE EXCEPTION 'Next draft revision required' USING ERRCODE='23514',CONSTRAINT='recipe_next_revision';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER recipe_revision_guard BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.production_recipe_revisions
  FOR EACH ROW EXECUTE FUNCTION {{schema}}.recipe_revision_guard();
CREATE FUNCTION {{schema}}.recipe_article_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' OR OLD.status='retired' THEN
    RAISE EXCEPTION 'Recipe article retained/terminal' USING ERRCODE='23514',CONSTRAINT='recipe_article_terminal';
  END IF;
  IF NEW.id<>OLD.id OR NEW.company_id<>OLD.company_id OR NEW.produced_article_id<>OLD.produced_article_id OR NEW.created_at<>OLD.created_at OR NEW.created_by<>OLD.created_by THEN
    RAISE EXCEPTION 'Recipe identity immutable' USING ERRCODE='23514',CONSTRAINT='recipe_recipe_identity';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER recipe_article_guard BEFORE UPDATE OR DELETE ON {{schema}}.production_recipes
  FOR EACH ROW EXECUTE FUNCTION {{schema}}.recipe_article_guard();

CREATE TABLE {{schema}}.production_recipe_ingredients (
  id uuid NOT NULL,
  company_id uuid NOT NULL,
  recipe_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  position integer NOT NULL CHECK (position BETWEEN 1 AND 50),
  article_id uuid NOT NULL,
  quantity_scaled bigint NOT NULL CHECK (quantity_scaled BETWEEN 1 AND 999999999999999),
  sku text NOT NULL CHECK (length(sku) BETWEEN 1 AND 64),
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 200),
  unit text NOT NULL CHECK (length(unit) BETWEEN 1 AND 32),
  PRIMARY KEY (revision_id,id),
  UNIQUE (revision_id,position),
  UNIQUE (revision_id,article_id),
  FOREIGN KEY (revision_id,company_id,recipe_id) REFERENCES {{schema}}.production_recipe_revisions(id,company_id,recipe_id) ON DELETE RESTRICT,
  FOREIGN KEY (article_id,company_id) REFERENCES {{schema}}.articles(id,company_id) ON DELETE RESTRICT
);
CREATE FUNCTION {{schema}}.recipe_ingredient_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE parent_status text; produced uuid;
BEGIN
  IF TG_OP IN ('UPDATE','DELETE') THEN
    SELECT status INTO parent_status FROM {{schema}}.production_recipe_revisions WHERE id=OLD.revision_id FOR UPDATE;
    IF parent_status IS DISTINCT FROM 'draft' THEN
      RAISE EXCEPTION 'Terminal Recipe ingredients frozen' USING ERRCODE='23514',CONSTRAINT='recipe_ingredient_frozen';
    END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.id,NEW.company_id,NEW.recipe_id,NEW.revision_id) IS DISTINCT FROM ROW(OLD.id,OLD.company_id,OLD.recipe_id,OLD.revision_id) THEN
    RAISE EXCEPTION 'Ingredient identity retained' USING ERRCODE='23514',CONSTRAINT='recipe_ingredient_identity';
  END IF;
  SELECT status INTO parent_status FROM {{schema}}.production_recipe_revisions WHERE id=NEW.revision_id FOR UPDATE;
  SELECT produced_article_id INTO produced FROM {{schema}}.production_recipes WHERE id=NEW.recipe_id;
  IF parent_status IS DISTINCT FROM 'draft' OR produced=NEW.article_id THEN
    RAISE EXCEPTION 'Editable distinct ingredient required' USING ERRCODE='23514',CONSTRAINT='recipe_ingredient_reference';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER recipe_ingredient_guard BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.production_recipe_ingredients
  FOR EACH ROW EXECUTE FUNCTION {{schema}}.recipe_ingredient_guard();

-- Deferred checks inspect the final whole document after draft row replacement.
CREATE FUNCTION {{schema}}.recipe_composition_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE rid uuid; rev {{schema}}.production_recipe_revisions%ROWTYPE; produced uuid;
  n integer; last_position integer; bytes bigint;
BEGIN
  IF TG_TABLE_NAME='production_recipe_revisions' THEN rid=NEW.id;
  ELSIF TG_OP='DELETE' THEN rid=OLD.revision_id;
  ELSE rid=NEW.revision_id; END IF;
  SELECT * INTO rev FROM {{schema}}.production_recipe_revisions WHERE id=rid;
  SELECT produced_article_id INTO produced FROM {{schema}}.production_recipes WHERE id=rev.recipe_id;
  SELECT count(*),COALESCE(max(position),0),COALESCE(sum(octet_length(id::text || position::text || article_id::text || sku || name || unit ||
    (quantity_scaled/1000)::text || '.' || lpad((quantity_scaled%1000)::text,3,'0'))),0)
    INTO n,last_position,bytes FROM {{schema}}.production_recipe_ingredients WHERE revision_id=rid;
  bytes=bytes+octet_length(rev.batch_description || rev.preparation || produced::text || rev.produced_sku || rev.produced_name || rev.produced_unit);
  IF n>50 OR last_position<>n OR bytes>32768 OR (rev.status='published' AND n=0) THEN
    RAISE EXCEPTION 'Invalid composition bounds/order' USING ERRCODE='23514',CONSTRAINT='recipe_composition_bounds';
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER recipe_composition_revision AFTER INSERT OR UPDATE ON {{schema}}.production_recipe_revisions
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.recipe_composition_guard();
CREATE CONSTRAINT TRIGGER recipe_composition_ingredients AFTER INSERT OR UPDATE OR DELETE ON {{schema}}.production_recipe_ingredients
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.recipe_composition_guard();
