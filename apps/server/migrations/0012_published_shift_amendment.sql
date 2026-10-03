-- Workforce: the interval of a published shift may be amended while every
-- materialized task instance is still pristine open. The effective execution
-- window is always read from the current shift row: task instances, snapshots,
-- receipts and step evidence store no interval and are not touched. Only the
-- most recent amendment is recorded on the shift; earlier amendments remain in
-- the append-only audit. A DB-level exclusion constraint backs the application
-- overlap check for published shifts of one employee; drafts and cancelled
-- shifts stay outside it, and back-to-back intervals remain allowed.
--
-- CREATE EXTENSION IF NOT EXISTS is not concurrency-safe: concurrent schema
-- migrations in one database (the integration suite migrates isolated schemas
-- in parallel) can observe "duplicate key value violates unique constraint
-- pg_extension_name_index". Reproduced against the supported PostgreSQL 17
-- image. The DO block tolerates only duplicate_object/unique_violation and
-- re-raises every other failure, so a missing or uninstallable extension still
-- fails the migration loudly.
DO $$ BEGIN
 CREATE EXTENSION IF NOT EXISTS btree_gist;
EXCEPTION WHEN duplicate_object OR unique_violation THEN NULL;
END $$;
ALTER TABLE {{schema}}.shifts
 ADD COLUMN amended_at timestamptz,
 ADD COLUMN amended_by uuid REFERENCES {{schema}}.accounts(id),
 ADD COLUMN amendment_version bigint CHECK (amendment_version>0);
-- Draft has no evidence at all; published/cancelled keep their existing
-- evidence requirements and may carry either no amendment or one complete
-- last-amendment record.
ALTER TABLE {{schema}}.shifts DROP CONSTRAINT shifts_state,
 ADD CONSTRAINT shifts_state CHECK(
 (status='draft' AND published_at IS NULL AND published_by IS NULL AND publication_version IS NULL
  AND cancelled_at IS NULL AND cancelled_by IS NULL AND cancellation_reason IS NULL AND cancellation_version IS NULL
  AND amended_at IS NULL AND amended_by IS NULL AND amendment_version IS NULL)
 OR (status='published' AND published_at IS NOT NULL AND published_by IS NOT NULL AND publication_version IS NOT NULL AND publication_version>0
  AND cancelled_at IS NULL AND cancelled_by IS NULL AND cancellation_reason IS NULL AND cancellation_version IS NULL
  AND ((amended_at IS NULL AND amended_by IS NULL AND amendment_version IS NULL)
   OR (amended_at IS NOT NULL AND amended_by IS NOT NULL AND amendment_version IS NOT NULL)))
 OR (status='cancelled' AND published_at IS NOT NULL AND published_by IS NOT NULL AND publication_version IS NOT NULL AND publication_version>0
  AND cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL AND cancellation_reason IS NOT NULL AND cancellation_version IS NOT NULL
  AND ((amended_at IS NULL AND amended_by IS NULL AND amendment_version IS NULL)
   OR (amended_at IS NOT NULL AND amended_by IS NOT NULL AND amendment_version IS NOT NULL))));
-- Defense in depth for the M2 finding: one published interval per employee,
-- half-open, independent of the application overload check.
ALTER TABLE {{schema}}.shifts
 ADD CONSTRAINT shifts_published_no_overlap EXCLUDE USING gist (
  company_id WITH =, employee_id WITH =, tstzrange(starts_at, ends_at, '[)') WITH &&
 ) WHERE (status='published');
-- Published shifts stay immutable except for the single published -> cancelled
-- transition (unchanged) and the bounded published -> published interval
-- amendment. An amendment must change at least one bound, advance the version
-- by exactly one, and pair the pre-amendment version with an actor and
-- timestamp; everything else, including publication, cancellation and
-- employee/location evidence, stays unchanged.
CREATE OR REPLACE FUNCTION {{schema}}.protect_published_shift() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN
  IF OLD.status IN ('published','cancelled') THEN RAISE EXCEPTION 'Published shifts are immutable' USING ERRCODE='23514'; END IF;
  RETURN OLD;
 END IF;
 IF OLD.status='published' AND NEW.status='cancelled' THEN
  IF (to_jsonb(NEW)-ARRAY['status','version','updated_at','cancelled_at','cancelled_by','cancellation_reason','cancellation_version'])
   IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version','updated_at','cancelled_at','cancelled_by','cancellation_reason','cancellation_version']) THEN
   RAISE EXCEPTION 'Invalid shift cancellation' USING ERRCODE='23514'; END IF;
  RETURN NEW;
 END IF;
 IF OLD.status='published' AND NEW.status='published' THEN
  IF (to_jsonb(NEW)-ARRAY['starts_at','ends_at','version','updated_at','amended_at','amended_by','amendment_version'])
   IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['starts_at','ends_at','version','updated_at','amended_at','amended_by','amendment_version'])
   OR NEW.version<>OLD.version+1
   OR NEW.amendment_version IS DISTINCT FROM OLD.version
   OR NEW.amended_at IS NULL
   OR NEW.amended_by IS NULL
   OR (NEW.starts_at IS NOT DISTINCT FROM OLD.starts_at AND NEW.ends_at IS NOT DISTINCT FROM OLD.ends_at)
   OR NEW.starts_at>=NEW.ends_at THEN
   RAISE EXCEPTION 'Invalid shift amendment' USING ERRCODE='23514'; END IF;
  RETURN NEW;
 END IF;
 IF OLD.status IN ('published','cancelled') THEN RAISE EXCEPTION 'Published shifts are immutable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
