-- Preserve non-temporal integrity failures before reporting ordinary expiry.
CREATE OR REPLACE FUNCTION {{schema}}.swap_leg_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r {{schema}}.workforce_shift_swap_requests%ROWTYPE; s {{schema}}.shifts%ROWTYPE;
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Swap leg retained' USING ERRCODE='23514'; END IF;
  SELECT * INTO r FROM {{schema}}.workforce_shift_swap_requests WHERE company_id=NEW.company_id AND id=NEW.request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Swap parent required' USING ERRCODE='23514'; END IF;
  IF ROW(NEW.source_employee_id,NEW.incoming_employee_id) IS DISTINCT FROM
    ROW(CASE WHEN NEW.leg='a' THEN r.source_employee_id ELSE r.recipient_employee_id END,
        CASE WHEN NEW.leg='a' THEN r.recipient_employee_id ELSE r.source_employee_id END)
  THEN RAISE EXCEPTION 'Swap leg owner mismatch' USING ERRCODE='23514'; END IF;
  IF TG_OP='INSERT' THEN
    SELECT * INTO s FROM {{schema}}.shifts WHERE company_id=NEW.company_id AND id=NEW.source_shift_id;
    IF NOT FOUND OR s.status IS DISTINCT FROM 'published' OR
      ROW(s.version,s.starts_at,s.ends_at) IS DISTINCT FROM ROW(NEW.source_version,NEW.starts_at,NEW.ends_at) OR
      NEW.replacement_shift_id IS NOT NULL OR
      (NEW.leg='a' AND r.status<>'requested') OR (NEW.leg='b' AND r.status NOT IN ('requested','offered')) OR
      NEW.work_references IS DISTINCT FROM {{schema}}.tasks_swap_references(NEW.company_id,NEW.source_shift_id,NEW.location_id) OR
      {{schema}}.tasks_swap_pristine(NEW.company_id,NEW.source_shift_id) IS NOT TRUE
    THEN RAISE EXCEPTION 'Exact pristine swap leg required' USING ERRCODE='23514'; END IF;
    -- Leave malformed leg labels and scoped FK tuples to their existing table
    -- constraints instead of masking those integrity errors with clock expiry.
    IF NEW.leg IN ('a','b') AND NEW.location_id=r.location_id AND
      ROW(s.location_id,s.employee_id)=ROW(NEW.location_id,NEW.source_employee_id) AND
      clock_timestamp()>=NEW.starts_at THEN
      RAISE EXCEPTION 'Future swap leg required' USING ERRCODE='23514',CONSTRAINT='swap_leg_future';
    END IF;
  ELSE
    IF (to_jsonb(NEW)-'replacement_shift_id') IS DISTINCT FROM (to_jsonb(OLD)-'replacement_shift_id') OR
      OLD.replacement_shift_id IS NOT NULL OR NEW.replacement_shift_id IS NULL OR r.status NOT IN ('confirmed','approved')
    THEN RAISE EXCEPTION 'Immutable swap leg' USING ERRCODE='23514'; END IF;
    IF EXISTS(SELECT 1 FROM {{schema}}.shifts WHERE id=NEW.replacement_shift_id) THEN
      RAISE EXCEPTION 'Replacement must be bound before Shift creation' USING ERRCODE='23514',CONSTRAINT='swap_replacement_creation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
