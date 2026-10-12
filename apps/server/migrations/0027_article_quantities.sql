-- P4.15. Additive only: legacy Article, Stock, snapshots and receipts are untouched.
-- Inventory owns profiles, revisions and commands. Packages are bounded direct
-- revision content; neither labels nor foreign module records infer semantics.
CREATE FUNCTION {{schema}}.quantity_packages_valid(value jsonb) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE p jsonb; ids text[] := '{}'; labels text[] := '{}';
BEGIN
  IF jsonb_typeof(value) <> 'array' OR jsonb_array_length(value) > 16 THEN RETURN false; END IF;
  FOR p IN SELECT * FROM jsonb_array_elements(value) LOOP
    IF jsonb_typeof(p) <> 'object' OR (SELECT count(*) FROM jsonb_object_keys(p)) <> 3
       OR NOT (p ?& ARRAY['id','label','content'])
       OR jsonb_typeof(p->'id') <> 'string' OR jsonb_typeof(p->'label') <> 'string'
       OR jsonb_typeof(p->'content') <> 'string'
       OR p->>'id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       OR length(p->>'label') NOT BETWEEN 1 AND 32 OR p->>'label' <> btrim(p->>'label')
       OR p->>'label' ~ '[[:cntrl:]]'
       OR p->>'content' !~ '^(0|[1-9][0-9]{0,11})(\.[0-9]{0,5}[1-9])?$'
       OR p->>'id' = ANY(ids) OR p->>'label' = ANY(labels) THEN RETURN false; END IF;
    IF (p->>'content')::numeric <= 0 THEN RETURN false; END IF;
    ids := array_append(ids,p->>'id'); labels := array_append(labels,p->>'label');
  END LOOP;
  RETURN true;
END $$;

CREATE TABLE {{schema}}.inventory_quantity_profiles (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  article_id uuid NOT NULL,
  base_unit text NOT NULL CHECK (base_unit IN ('g','kg','mL','L','piece')),
  dimension text GENERATED ALWAYS AS (CASE WHEN base_unit IN ('g','kg') THEN 'mass'
    WHEN base_unit IN ('mL','L') THEN 'volume' ELSE 'count' END) STORED,
  version bigint NOT NULL CHECK (version BETWEEN 1 AND 9007199254740990),
  status text NOT NULL CHECK (status IN ('active','suspended')),
  UNIQUE (company_id,article_id),
  UNIQUE (id,company_id,article_id),
  FOREIGN KEY (article_id,company_id) REFERENCES {{schema}}.articles(id,company_id) ON DELETE RESTRICT
);
CREATE TABLE {{schema}}.inventory_quantity_revisions (
  profile_id uuid NOT NULL,
  company_id uuid NOT NULL,
  article_id uuid NOT NULL,
  version bigint NOT NULL CHECK (version BETWEEN 1 AND 9007199254740990),
  status text NOT NULL CHECK (status IN ('active','suspended')),
  packages jsonb NOT NULL CHECK ({{schema}}.quantity_packages_valid(packages)),
  reason text NOT NULL CHECK (length(reason) BETWEEN 1 AND 500 AND reason=btrim(reason) AND reason !~ '[[:cntrl:]]'),
  recorded_by uuid NOT NULL REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (profile_id,version),
  UNIQUE (profile_id,company_id,article_id,version),
  UNIQUE (profile_id,company_id,article_id,version,status),
  FOREIGN KEY (profile_id,company_id,article_id) REFERENCES {{schema}}.inventory_quantity_profiles(id,company_id,article_id) ON DELETE RESTRICT
);
ALTER TABLE {{schema}}.inventory_quantity_profiles ADD CONSTRAINT quantity_profile_current_revision
  FOREIGN KEY (id,company_id,article_id,version,status)
  REFERENCES {{schema}}.inventory_quantity_revisions(profile_id,company_id,article_id,version,status)
  DEFERRABLE INITIALLY DEFERRED;
CREATE TABLE {{schema}}.inventory_quantity_commands (
  operation_id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  article_id uuid NOT NULL,
  profile_id uuid NOT NULL,
  version bigint NOT NULL,
  kind text NOT NULL CHECK (kind IN ('configure','replace','suspend')),
  recorded_by uuid NOT NULL REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload)='object' AND octet_length(payload::text)<12000),
  result jsonb NOT NULL CHECK (jsonb_typeof(result)='object' AND octet_length(result::text)<14000),
  UNIQUE (profile_id,version),
  FOREIGN KEY (profile_id,company_id,article_id,version)
    REFERENCES {{schema}}.inventory_quantity_revisions(profile_id,company_id,article_id,version) ON DELETE RESTRICT
);

-- Stock owns prospective immutable binding and conversion command evidence.
CREATE TABLE {{schema}}.stock_quantity_bindings (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  article_id uuid NOT NULL,
  stock_level_id uuid NOT NULL,
  profile_id uuid NOT NULL,
  profile_version bigint NOT NULL,
  stock_version bigint NOT NULL CHECK (stock_version BETWEEN 1 AND 9007199254740990),
  unit text NOT NULL CHECK (unit IN ('g','kg','mL','L','piece') OR unit ~ '^pack:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),
  label text NOT NULL CHECK (length(label) BETWEEN 1 AND 32 AND label=btrim(label) AND label !~ '[[:cntrl:]]'),
  numerator text NOT NULL CHECK (numerator ~ '^[1-9][0-9]{0,39}$'),
  denominator text NOT NULL CHECK (denominator ~ '^[1-9][0-9]{0,39}$'),
  reason text NOT NULL CHECK (length(reason) BETWEEN 1 AND 500 AND reason=btrim(reason) AND reason !~ '[[:cntrl:]]'),
  recorded_by uuid NOT NULL REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (stock_level_id),
  UNIQUE (id,company_id,location_id,article_id,stock_level_id,profile_id),
  FOREIGN KEY (stock_level_id,company_id,location_id,article_id)
    REFERENCES {{schema}}.stock_levels(id,company_id,location_id,article_id) ON DELETE RESTRICT,
  FOREIGN KEY (profile_id,company_id,article_id,profile_version)
    REFERENCES {{schema}}.inventory_quantity_revisions(profile_id,company_id,article_id,version) ON DELETE RESTRICT
);
CREATE TABLE {{schema}}.stock_quantity_corrections (
  operation_id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  article_id uuid NOT NULL,
  stock_level_id uuid NOT NULL,
  binding_id uuid NOT NULL,
  profile_id uuid NOT NULL,
  profile_version bigint NOT NULL,
  expected_version bigint NOT NULL CHECK (expected_version BETWEEN 1 AND 9007199254740990),
  input_quantity text NOT NULL CHECK (input_quantity ~ '^(0|[1-9][0-9]{0,11})(\.[0-9]{0,5}[1-9])?$'),
  numerator text NOT NULL CHECK (numerator ~ '^[1-9][0-9]{0,39}$'),
  denominator text NOT NULL CHECK (denominator ~ '^[1-9][0-9]{0,39}$'),
  before_scaled bigint NOT NULL CHECK (before_scaled BETWEEN 0 AND 999999999999999),
  target_scaled bigint NOT NULL CHECK (target_scaled BETWEEN 0 AND 999999999999999),
  delta_scaled bigint NOT NULL CHECK (delta_scaled=target_scaled-before_scaled),
  movement_id uuid UNIQUE REFERENCES {{schema}}.stock_movements(id) ON DELETE RESTRICT,
  reason text NOT NULL CHECK (length(reason) BETWEEN 1 AND 500 AND reason=btrim(reason) AND reason !~ '[[:cntrl:]]'),
  recorded_by uuid NOT NULL REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload)='object' AND octet_length(payload::text)<8000),
  result jsonb NOT NULL CHECK (jsonb_typeof(result)='object' AND octet_length(result::text)<8000),
  CHECK ((delta_scaled=0 AND movement_id IS NULL) OR (delta_scaled<>0 AND movement_id=operation_id)),
  CHECK (input_quantity::numeric * numerator::numeric * 1000 = target_scaled::numeric * denominator::numeric),
  FOREIGN KEY (binding_id,company_id,location_id,article_id,stock_level_id,profile_id)
    REFERENCES {{schema}}.stock_quantity_bindings(id,company_id,location_id,article_id,stock_level_id,profile_id) ON DELETE RESTRICT,
  FOREIGN KEY (profile_id,company_id,article_id,profile_version)
    REFERENCES {{schema}}.inventory_quantity_revisions(profile_id,company_id,article_id,version) ON DELETE RESTRICT
);
CREATE INDEX stock_quantity_corrections_page ON {{schema}}.stock_quantity_corrections(company_id,location_id,stock_level_id,operation_id);

CREATE FUNCTION {{schema}}.quantity_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Quantity evidence is immutable' USING ERRCODE='23514'; END $$;
CREATE TRIGGER quantity_revisions_immutable BEFORE UPDATE OR DELETE ON {{schema}}.inventory_quantity_revisions FOR EACH ROW EXECUTE FUNCTION {{schema}}.quantity_append_only();
CREATE TRIGGER quantity_commands_immutable BEFORE UPDATE OR DELETE ON {{schema}}.inventory_quantity_commands FOR EACH ROW EXECUTE FUNCTION {{schema}}.quantity_append_only();
CREATE TRIGGER quantity_bindings_immutable BEFORE UPDATE OR DELETE ON {{schema}}.stock_quantity_bindings FOR EACH ROW EXECUTE FUNCTION {{schema}}.quantity_append_only();
CREATE TRIGGER quantity_corrections_immutable BEFORE UPDATE OR DELETE ON {{schema}}.stock_quantity_corrections FOR EACH ROW EXECUTE FUNCTION {{schema}}.quantity_append_only();

CREATE FUNCTION {{schema}}.quantity_profile_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' OR (TG_OP='UPDATE' AND (OLD.status='suspended' OR NEW.version<>OLD.version+1
     OR (NEW.id,NEW.company_id,NEW.article_id,NEW.base_unit) IS DISTINCT FROM (OLD.id,OLD.company_id,OLD.article_id,OLD.base_unit))) THEN
    RAISE EXCEPTION 'Immutable anchor or invalid quantity transition' USING ERRCODE='23514';
  END IF;
  IF TG_OP='INSERT' AND (NEW.version<>1 OR NEW.status<>'active') THEN
    RAISE EXCEPTION 'Invalid initial quantity profile' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER quantity_profile_guard BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.inventory_quantity_profiles FOR EACH ROW EXECUTE FUNCTION {{schema}}.quantity_profile_guard();

-- A revision must have an original receipt; profile versions form a complete
-- append-only chain and suspension cannot modify the prior package contents.
CREATE FUNCTION {{schema}}.quantity_revision_final() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE prior {{schema}}.inventory_quantity_revisions; current {{schema}}.inventory_quantity_profiles;
BEGIN
  SELECT * INTO current FROM {{schema}}.inventory_quantity_profiles WHERE id=NEW.profile_id;
  IF NEW.version>current.version OR NOT EXISTS (SELECT 1 FROM {{schema}}.inventory_quantity_commands c
      WHERE c.profile_id=NEW.profile_id AND c.version=NEW.version AND c.recorded_by=NEW.recorded_by
      AND c.result->>'id'=NEW.profile_id::text AND (c.result->>'version')::bigint=NEW.version
      AND c.result->'packages'=NEW.packages AND c.result->>'reason'=NEW.reason
      AND c.kind=CASE WHEN NEW.version=1 THEN 'configure' WHEN NEW.status='suspended' THEN 'suspend' ELSE 'replace' END) THEN
    RAISE EXCEPTION 'Quantity revision receipt mismatch' USING ERRCODE='23514';
  END IF;
  IF NEW.version>1 THEN
    SELECT * INTO prior FROM {{schema}}.inventory_quantity_revisions WHERE profile_id=NEW.profile_id AND version=NEW.version-1;
    IF NOT FOUND OR prior.status<>'active' OR (NEW.status='suspended' AND NEW.packages<>prior.packages) THEN
      RAISE EXCEPTION 'Invalid quantity revision chain' USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER quantity_revision_final AFTER INSERT ON {{schema}}.inventory_quantity_revisions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.quantity_revision_final();

-- Inventory's narrow SQL read port exists only for database integrity guards.
-- It resolves an exact retained revision, never a label or another Article.
CREATE FUNCTION {{schema}}.inventory_quantity_factor(profile uuid, company uuid, article uuid, revision bigint, unit text)
RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE base text; packages jsonb; content text;
BEGIN
  SELECT p.base_unit,r.packages INTO base,packages FROM {{schema}}.inventory_quantity_profiles p
    JOIN {{schema}}.inventory_quantity_revisions r ON r.profile_id=p.id AND r.version=revision
    WHERE p.id=profile AND p.company_id=company AND p.article_id=article AND r.status='active';
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF unit=base THEN RETURN 1; END IF;
  IF (unit='g' AND base='kg') OR (unit='mL' AND base='L') THEN RETURN 0.001; END IF;
  IF (unit='kg' AND base='g') OR (unit='L' AND base='mL') THEN RETURN 1000; END IF;
  SELECT p->>'content' INTO content FROM jsonb_array_elements(packages) p WHERE 'pack:'||(p->>'id')=unit;
  RETURN content::numeric;
END $$;
CREATE FUNCTION {{schema}}.stock_quantity_binding_final() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE factor numeric;
BEGIN
  factor:={{schema}}.inventory_quantity_factor(NEW.profile_id,NEW.company_id,NEW.article_id,NEW.profile_version,NEW.unit);
  IF factor IS NULL OR factor*NEW.denominator::numeric<>NEW.numerator::numeric
     OR EXISTS (SELECT 1 FROM {{schema}}.stock_quantity_corrections WHERE operation_id=NEW.id)
     OR EXISTS (SELECT 1 FROM {{schema}}.stock_movements WHERE id=NEW.id) THEN
    RAISE EXCEPTION 'Invalid Stock quantity binding' USING ERRCODE='23514';
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER stock_quantity_binding_final AFTER INSERT ON {{schema}}.stock_quantity_bindings DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.stock_quantity_binding_final();

CREATE FUNCTION {{schema}}.stock_quantity_correction_final() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE movement {{schema}}.stock_movements; binding {{schema}}.stock_quantity_bindings; factor numeric; review jsonb;
BEGIN
  review:=NEW.payload->'review';
  SELECT * INTO binding FROM {{schema}}.stock_quantity_bindings WHERE id=NEW.binding_id;
  factor:={{schema}}.inventory_quantity_factor(NEW.profile_id,NEW.company_id,NEW.article_id,NEW.profile_version,review->>'inputUnit');
  IF factor IS NULL OR factor*binding.denominator::numeric*NEW.denominator::numeric<>binding.numerator::numeric*NEW.numerator::numeric THEN
    RAISE EXCEPTION 'Stock conversion factor mismatch' USING ERRCODE='23514';
  END IF;
  IF EXISTS (SELECT 1 FROM {{schema}}.stock_quantity_bindings WHERE id=NEW.operation_id) THEN
    RAISE EXCEPTION 'Stock quantity operation identity reused' USING ERRCODE='23514';
  END IF;
  IF NEW.delta_scaled<>0 THEN
    SELECT * INTO movement FROM {{schema}}.stock_movements WHERE id=NEW.movement_id;
    IF NOT FOUND OR (movement.company_id,movement.location_id,movement.article_id,movement.stock_level_id,movement.kind,
       movement.delta_scaled,movement.balance_after_scaled,movement.balance_version,movement.recorded_by,movement.note)
       IS DISTINCT FROM (NEW.company_id,NEW.location_id,NEW.article_id,NEW.stock_level_id,'adjustment'::text,
       NEW.delta_scaled,NEW.target_scaled,NEW.expected_version+1,NEW.recorded_by,NEW.reason) THEN
      RAISE EXCEPTION 'Stock conversion movement mismatch' USING ERRCODE='23514';
    END IF;
  END IF;
  IF review->>'bindingId' IS DISTINCT FROM NEW.binding_id::text
     OR review->>'levelId' IS DISTINCT FROM NEW.stock_level_id::text
     OR review->>'profileId' IS DISTINCT FROM NEW.profile_id::text
     OR (review->>'profileVersion')::bigint IS DISTINCT FROM NEW.profile_version
     OR (review->>'stockVersion')::bigint IS DISTINCT FROM NEW.expected_version
     OR review->>'inputQuantity' IS DISTINCT FROM NEW.input_quantity
     OR review->>'numerator' IS DISTINCT FROM NEW.numerator
     OR review->>'denominator' IS DISTINCT FROM NEW.denominator
     OR (review->>'currentQuantity')::numeric*1000 IS DISTINCT FROM NEW.before_scaled::numeric
     OR (review->>'targetQuantity')::numeric*1000 IS DISTINCT FROM NEW.target_scaled::numeric
     OR (review->>'delta')::numeric*1000 IS DISTINCT FROM NEW.delta_scaled::numeric
     OR NEW.result->'review' IS DISTINCT FROM review
     OR NEW.result->>'operationId' IS DISTINCT FROM NEW.operation_id::text
     OR NEW.result->>'reason' IS DISTINCT FROM NEW.reason
     OR NEW.result->>'recordedBy' IS DISTINCT FROM NEW.recorded_by::text
     OR NEW.result->>'movementId' IS DISTINCT FROM NEW.movement_id::text
     OR (NEW.result->>'balanceVersion')::bigint IS DISTINCT FROM (NEW.expected_version+(CASE WHEN NEW.delta_scaled=0 THEN 0 ELSE 1 END)) THEN
    RAISE EXCEPTION 'Stock conversion receipt mismatch' USING ERRCODE='23514';
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER stock_quantity_correction_final AFTER INSERT ON {{schema}}.stock_quantity_corrections DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.stock_quantity_correction_final();
