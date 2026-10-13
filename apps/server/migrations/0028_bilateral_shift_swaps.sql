-- Forward-only Stage A. Writers must be drained by the operator before upgrade.
ALTER TABLE {{schema}}.workforce_shift_transfer_requests ADD CONSTRAINT handoff_transfer_scope
  UNIQUE(company_id,id,location_id,source_shift_id);

CREATE TABLE {{schema}}.workforce_shift_swap_requests (
  company_id uuid NOT NULL, id uuid NOT NULL, location_id uuid NOT NULL,
  source_employee_id uuid NOT NULL, recipient_employee_id uuid NOT NULL,
  source_account_id uuid NOT NULL, recipient_account_id uuid NOT NULL,
  source_link_id uuid NOT NULL, recipient_link_id uuid NOT NULL,
  source_account_version bigint NOT NULL CHECK(source_account_version BETWEEN 1 AND 2147483647),
  recipient_account_version bigint NOT NULL CHECK(recipient_account_version BETWEEN 1 AND 2147483647),
  requested_at timestamptz NOT NULL DEFAULT clock_timestamp(), request_operation_id uuid NOT NULL,
  request_kind text NOT NULL DEFAULT 'request' CHECK(request_kind='request'),
  status text NOT NULL DEFAULT 'requested' CHECK(status IN ('requested','offered','confirmed','declined','withdrawn','rejected','approved')),
  version integer NOT NULL DEFAULT 1 CHECK(version BETWEEN 1 AND 4),
  offered_by uuid, offered_at timestamptz, offer_operation_id uuid,
  offer_kind text NOT NULL DEFAULT 'offer' CHECK(offer_kind='offer'),
  confirmed_by uuid, confirmed_at timestamptz, confirmation_operation_id uuid,
  confirmation_kind text NOT NULL DEFAULT 'confirm' CHECK(confirmation_kind='confirm'),
  terminal_by uuid, terminal_at timestamptz, terminal_operation_id uuid, terminal_kind text, terminal_reason text,
  PRIMARY KEY(company_id,id), UNIQUE(company_id,id,location_id),
  CHECK(source_employee_id<>recipient_employee_id AND source_account_id<>recipient_account_id),
  FOREIGN KEY(source_employee_id,company_id,location_id) REFERENCES {{schema}}.employees(id,company_id,location_id),
  FOREIGN KEY(recipient_employee_id,company_id,location_id) REFERENCES {{schema}}.employees(id,company_id,location_id),
  FOREIGN KEY(source_link_id,company_id,location_id,source_account_id,source_employee_id) REFERENCES {{schema}}.account_employee_links(id,company_id,location_id,account_id,employee_id),
  FOREIGN KEY(recipient_link_id,company_id,location_id,recipient_account_id,recipient_employee_id) REFERENCES {{schema}}.account_employee_links(id,company_id,location_id,account_id,employee_id),
  FOREIGN KEY(offered_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY(confirmed_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY(terminal_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  CONSTRAINT swap_consent_shape CHECK ((
    ((offered_by IS NULL AND offered_at IS NULL AND offer_operation_id IS NULL) OR
      (offered_by IS NOT NULL AND offered_by=recipient_account_id AND offered_at IS NOT NULL AND offered_at>=requested_at AND offer_operation_id IS NOT NULL)) AND
    ((confirmed_by IS NULL AND confirmed_at IS NULL AND confirmation_operation_id IS NULL) OR
      (confirmed_by IS NOT NULL AND confirmed_by=source_account_id AND offered_at IS NOT NULL AND confirmed_at IS NOT NULL AND confirmed_at>=offered_at AND confirmation_operation_id IS NOT NULL))
  ) IS TRUE),
  CONSTRAINT swap_lifecycle_shape CHECK ((
    (status='requested' AND version=1 AND offered_by IS NULL AND confirmed_by IS NULL) OR
    (status='offered' AND version=2 AND offered_by IS NOT NULL AND confirmed_by IS NULL) OR
    (status='confirmed' AND version=3 AND confirmed_by IS NOT NULL) OR
    (status IN ('declined','withdrawn','rejected','approved') AND version=CASE WHEN confirmed_by IS NOT NULL THEN 4 WHEN offered_by IS NOT NULL THEN 3 ELSE 2 END AND
      terminal_by IS NOT NULL AND terminal_at IS NOT NULL AND terminal_at>=COALESCE(confirmed_at,offered_at,requested_at) AND terminal_operation_id IS NOT NULL AND terminal_kind IS NOT NULL AND
      ((status='declined' AND confirmed_by IS NULL AND terminal_kind='decline' AND terminal_by=CASE WHEN offered_by IS NULL THEN recipient_account_id ELSE source_account_id END AND terminal_reason IS NULL) OR
       (status='withdrawn' AND terminal_kind IN ('source_withdraw','recipient_withdraw') AND terminal_reason IS NOT NULL AND
         (terminal_kind='source_withdraw' OR (offered_by IS NOT NULL AND terminal_by=recipient_account_id))) OR
       (status='rejected' AND terminal_kind='manager_reject' AND terminal_reason IS NOT NULL) OR
       (status='approved' AND confirmed_by IS NOT NULL AND terminal_kind='manager_approve' AND terminal_by<>source_account_id AND terminal_by<>recipient_account_id AND terminal_reason IS NULL)))
  ) IS TRUE),
  CONSTRAINT swap_active_terminal_shape CHECK ((status NOT IN ('requested','offered','confirmed') OR
    (terminal_by IS NULL AND terminal_at IS NULL AND terminal_operation_id IS NULL AND terminal_kind IS NULL AND terminal_reason IS NULL)) IS TRUE),
  -- Retained reasons match transferReason's Unicode trim and control bounds.
  CHECK(terminal_reason IS NULL OR (length(terminal_reason) BETWEEN 1 AND 500 AND
    terminal_reason !~ U&'^[\0009-\000D\0020\0085\00A0\1680\2000-\200A\2028\2029\202F\205F\3000\FEFF]|[\0009-\000D\0020\0085\00A0\1680\2000-\200A\2028\2029\202F\205F\3000\FEFF]$' AND
    terminal_reason !~ U&'[\0001-\001F\007F-\009F]'))
);
CREATE INDEX swap_self_source ON {{schema}}.workforce_shift_swap_requests(company_id,location_id,source_employee_id,id);
CREATE INDEX swap_self_recipient ON {{schema}}.workforce_shift_swap_requests(company_id,location_id,recipient_employee_id,id);
CREATE INDEX swap_manager ON {{schema}}.workforce_shift_swap_requests(company_id,location_id,status,id);

CREATE TABLE {{schema}}.workforce_shift_swap_legs (
  company_id uuid NOT NULL, request_id uuid NOT NULL, location_id uuid NOT NULL,
  leg text NOT NULL CHECK(leg IN ('a','b')),
  source_shift_id uuid NOT NULL, source_version bigint NOT NULL CHECK(source_version BETWEEN 1 AND 2147483647),
  source_employee_id uuid NOT NULL, incoming_employee_id uuid NOT NULL,
  starts_at timestamptz NOT NULL, ends_at timestamptz NOT NULL,
  work_references jsonb NOT NULL CHECK((jsonb_typeof(work_references)='array' AND jsonb_array_length(work_references) BETWEEN 1 AND 10) IS TRUE),
  replacement_shift_id uuid,
  PRIMARY KEY(company_id,request_id,leg),
  UNIQUE(company_id,request_id,location_id,leg,source_shift_id),
  UNIQUE(company_id,request_id,location_id,leg,source_shift_id,replacement_shift_id),
  UNIQUE(company_id,request_id,source_shift_id),
  UNIQUE(company_id,replacement_shift_id),
  UNIQUE(company_id,request_id,location_id,leg,replacement_shift_id),
  CHECK(source_employee_id<>incoming_employee_id AND starts_at<ends_at),
  CHECK(replacement_shift_id IS NULL OR replacement_shift_id<>source_shift_id),
  FOREIGN KEY(company_id,request_id,location_id) REFERENCES {{schema}}.workforce_shift_swap_requests(company_id,id,location_id),
  FOREIGN KEY(source_shift_id,company_id,location_id,source_employee_id) REFERENCES {{schema}}.shifts(id,company_id,location_id,employee_id),
  FOREIGN KEY(replacement_shift_id,company_id,location_id,incoming_employee_id) REFERENCES {{schema}}.shifts(id,company_id,location_id,employee_id) DEFERRABLE INITIALLY DEFERRED
);

-- Creation provenance is assigned only by the Shift INSERT trigger from a
-- previously bound leg. Ordinary/historical Shifts retain NULL provenance.
-- The reciprocal FK and deferred creation guard prevent an allocated draft
-- from committing separately from its approved exchange.
ALTER TABLE {{schema}}.shifts ADD COLUMN swap_request_id uuid, ADD COLUMN swap_leg text,
  ADD CONSTRAINT swap_shift_origin_shape CHECK ((
    (swap_request_id IS NULL AND swap_leg IS NULL) OR
    (swap_request_id IS NOT NULL AND swap_leg IS NOT NULL AND swap_leg IN ('a','b'))
  ) IS TRUE),
  ADD CONSTRAINT swap_shift_origin FOREIGN KEY(company_id,swap_request_id,location_id,swap_leg,id)
    REFERENCES {{schema}}.workforce_shift_swap_legs(company_id,request_id,location_id,leg,replacement_shift_id)
    DEFERRABLE INITIALLY DEFERRED;

CREATE FUNCTION {{schema}}.swap_shift_creation_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE l {{schema}}.workforce_shift_swap_legs%ROWTYPE; state text;
BEGIN
  IF TG_OP='UPDATE' THEN
    IF ROW(NEW.swap_request_id,NEW.swap_leg) IS DISTINCT FROM ROW(OLD.swap_request_id,OLD.swap_leg) THEN
      RAISE EXCEPTION 'Immutable Shift creation provenance' USING ERRCODE='23514',CONSTRAINT='swap_shift_creation';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.swap_request_id IS NOT NULL OR NEW.swap_leg IS NOT NULL THEN
    RAISE EXCEPTION 'Shift creation provenance is database owned' USING ERRCODE='23514',CONSTRAINT='swap_shift_creation';
  END IF;
  SELECT * INTO l FROM {{schema}}.workforce_shift_swap_legs
    WHERE company_id=NEW.company_id AND replacement_shift_id=NEW.id;
  IF FOUND THEN
    SELECT status INTO state FROM {{schema}}.workforce_shift_swap_requests WHERE company_id=l.company_id AND id=l.request_id;
    IF state IS DISTINCT FROM 'confirmed' OR NEW.status IS DISTINCT FROM 'draft' OR NEW.version IS DISTINCT FROM 1::bigint OR
      ROW(NEW.location_id,NEW.employee_id,NEW.starts_at,NEW.ends_at) IS DISTINCT FROM
      ROW(l.location_id,l.incoming_employee_id,l.starts_at,l.ends_at) THEN
      RAISE EXCEPTION 'Exact new swap draft required' USING ERRCODE='23514',CONSTRAINT='swap_shift_creation';
    END IF;
    NEW.swap_request_id:=l.request_id; NEW.swap_leg:=l.leg;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER swap_shift_creation_guard BEFORE INSERT OR UPDATE ON {{schema}}.shifts FOR EACH ROW EXECUTE FUNCTION {{schema}}.swap_shift_creation_guard();
CREATE FUNCTION {{schema}}.swap_shift_creation_complete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.swap_request_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM {{schema}}.workforce_shift_swap_requests WHERE company_id=NEW.company_id AND id=NEW.swap_request_id AND status='approved'
  ) THEN
    RAISE EXCEPTION 'Replacement creation must commit with approval' USING ERRCODE='23514',CONSTRAINT='swap_shift_creation_complete';
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER swap_shift_creation_complete AFTER INSERT ON {{schema}}.shifts DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.swap_shift_creation_complete();

CREATE TABLE {{schema}}.workforce_shift_swap_commands (
  company_id uuid NOT NULL, operation_id uuid NOT NULL, location_id uuid NOT NULL,
  request_id uuid NOT NULL, actor_id uuid NOT NULL,
  kind text NOT NULL CHECK(kind IN ('request','offer','confirm','decline','source_withdraw','recipient_withdraw','manager_reject','manager_approve')),
  expected_version bigint NOT NULL CHECK(expected_version BETWEEN 1 AND 2147483647),
  accepted_version integer NOT NULL CHECK(accepted_version BETWEEN 1 AND 4),
  status_code integer NOT NULL CHECK(status_code IN (200,201)),
  payload jsonb NOT NULL CHECK((jsonb_typeof(payload)='object' AND octet_length(payload::text)<=8192) IS TRUE),
  result jsonb NOT NULL CHECK((jsonb_typeof(result)='object' AND octet_length(result::text)<=65536) IS TRUE),
  committed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(company_id,operation_id),
  UNIQUE(company_id,operation_id,location_id,request_id,actor_id,kind),
  CHECK((kind='request' AND accepted_version=1 AND status_code=201) OR (kind<>'request' AND accepted_version=expected_version+1 AND status_code=200)),
  FOREIGN KEY(company_id,request_id,location_id) REFERENCES {{schema}}.workforce_shift_swap_requests(company_id,id,location_id),
  FOREIGN KEY(actor_id,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id)
);
ALTER TABLE {{schema}}.workforce_shift_swap_requests ADD CONSTRAINT swap_request_receipt
  FOREIGN KEY(company_id,request_operation_id,location_id,id,source_account_id,request_kind) REFERENCES {{schema}}.workforce_shift_swap_commands(company_id,operation_id,location_id,request_id,actor_id,kind) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE {{schema}}.workforce_shift_swap_requests ADD CONSTRAINT swap_offer_receipt
  FOREIGN KEY(company_id,offer_operation_id,location_id,id,offered_by,offer_kind) REFERENCES {{schema}}.workforce_shift_swap_commands(company_id,operation_id,location_id,request_id,actor_id,kind) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE {{schema}}.workforce_shift_swap_requests ADD CONSTRAINT swap_confirmation_receipt
  FOREIGN KEY(company_id,confirmation_operation_id,location_id,id,confirmed_by,confirmation_kind) REFERENCES {{schema}}.workforce_shift_swap_commands(company_id,operation_id,location_id,request_id,actor_id,kind) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE {{schema}}.workforce_shift_swap_requests ADD CONSTRAINT swap_terminal_receipt
  FOREIGN KEY(company_id,terminal_operation_id,location_id,id,terminal_by,terminal_kind) REFERENCES {{schema}}.workforce_shift_swap_commands(company_id,operation_id,location_id,request_id,actor_id,kind) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE {{schema}}.workforce_shift_handoff_claims (
  company_id uuid NOT NULL, shift_id uuid NOT NULL, location_id uuid NOT NULL,
  transfer_request_id uuid, swap_request_id uuid, leg text,
  PRIMARY KEY(company_id,shift_id),
  CONSTRAINT handoff_owner_shape CHECK ((
    (transfer_request_id IS NOT NULL AND swap_request_id IS NULL AND leg IS NULL) OR
    (transfer_request_id IS NULL AND swap_request_id IS NOT NULL AND leg IS NOT NULL AND leg IN ('a','b'))
  ) IS TRUE),
  FOREIGN KEY(company_id,transfer_request_id,location_id,shift_id) REFERENCES {{schema}}.workforce_shift_transfer_requests(company_id,id,location_id,source_shift_id),
  FOREIGN KEY(company_id,swap_request_id,location_id,leg,shift_id) REFERENCES {{schema}}.workforce_shift_swap_legs(company_id,request_id,location_id,leg,source_shift_id)
);
CREATE INDEX handoff_transfer_owner ON {{schema}}.workforce_shift_handoff_claims(company_id,transfer_request_id) WHERE transfer_request_id IS NOT NULL;
CREATE INDEX handoff_swap_owner ON {{schema}}.workforce_shift_handoff_claims(company_id,swap_request_id) WHERE swap_request_id IS NOT NULL;

CREATE TABLE {{schema}}.task_swap_links (
  company_id uuid NOT NULL, location_id uuid NOT NULL, request_id uuid NOT NULL,
  leg text NOT NULL CHECK(leg IN ('a','b')), position integer NOT NULL CHECK(position BETWEEN 0 AND 9),
  source_shift_id uuid NOT NULL, replacement_shift_id uuid NOT NULL,
  source_task_id uuid NOT NULL, replacement_task_id uuid NOT NULL,
  template_id uuid NOT NULL, revision_id uuid NOT NULL,
  PRIMARY KEY(company_id,request_id,leg,position),
  UNIQUE(company_id,source_task_id), UNIQUE(company_id,replacement_task_id),
  CHECK(source_shift_id<>replacement_shift_id AND source_task_id<>replacement_task_id),
  FOREIGN KEY(company_id,request_id,location_id,leg,source_shift_id,replacement_shift_id) REFERENCES {{schema}}.workforce_shift_swap_legs(company_id,request_id,location_id,leg,source_shift_id,replacement_shift_id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY(source_task_id,company_id,location_id,source_shift_id,template_id,revision_id,position) REFERENCES {{schema}}.task_instances(id,company_id,location_id,shift_id,template_id,revision_id,position),
  FOREIGN KEY(replacement_task_id,company_id,location_id,replacement_shift_id,template_id,revision_id,position) REFERENCES {{schema}}.task_instances(id,company_id,location_id,shift_id,template_id,revision_id,position)
);

-- Tasks-owned SQL ports: retained references contain no bodies or execution data.
CREATE FUNCTION {{schema}}.tasks_swap_references(c uuid,s uuid,l uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id::text,'templateId',template_id::text,'revisionId',revision_id::text,
    'position',position,'title',content::jsonb->>'title','knowledgeGuidance',COALESCE(content::jsonb->'knowledgeGuidance','null'::jsonb),
    'planogramGuidance',COALESCE(content::jsonb->'planogramGuidance','null'::jsonb)) ORDER BY position),'[]'::jsonb)
  FROM {{schema}}.task_instances WHERE company_id=c AND shift_id=s AND location_id=l
$$;
CREATE FUNCTION {{schema}}.tasks_swap_pristine(c uuid,s uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT count(*) BETWEEN 1 AND 10 AND NOT EXISTS (
    SELECT 1 FROM (SELECT position,row_number() OVER(ORDER BY position)-1 AS expected
      FROM {{schema}}.task_instances WHERE company_id=c AND shift_id=s) ordered WHERE position<>expected
  ) AND NOT EXISTS (
    SELECT 1 FROM {{schema}}.task_instances t WHERE t.company_id=c AND t.shift_id=s AND
      (t.status<>'open' OR t.version<>1 OR t.started_at IS NOT NULL OR t.started_by IS NOT NULL OR
       EXISTS(SELECT 1 FROM {{schema}}.task_step_results e WHERE e.instance_id=t.id) OR
       EXISTS(SELECT 1 FROM {{schema}}.task_numeric_attempts e WHERE e.instance_id=t.id) OR
       EXISTS(SELECT 1 FROM {{schema}}.task_blockings e WHERE e.instance_id=t.id) OR
       EXISTS(SELECT 1 FROM {{schema}}.task_execution_commands e WHERE e.instance_id=t.id)))
  FROM {{schema}}.task_instances WHERE company_id=c AND shift_id=s
$$;

CREATE FUNCTION {{schema}}.swap_request_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Swap evidence retained' USING ERRCODE='23514'; END IF;
  IF TG_OP='INSERT' THEN
    IF NEW.status<>'requested' OR NEW.version<>1 THEN RAISE EXCEPTION 'Request required' USING ERRCODE='23514'; END IF;
  ELSE
    IF OLD.status NOT IN ('requested','offered','confirmed') OR NEW.version<>OLD.version+1 OR
      NOT ((OLD.status='requested' AND NEW.status IN ('offered','declined','withdrawn','rejected')) OR
           (OLD.status='offered' AND NEW.status IN ('confirmed','declined','withdrawn','rejected')) OR
           (OLD.status='confirmed' AND NEW.status IN ('withdrawn','rejected','approved'))) OR
      (to_jsonb(NEW)-ARRAY['status','version','offered_by','offered_at','offer_operation_id','confirmed_by','confirmed_at','confirmation_operation_id','terminal_by','terminal_at','terminal_operation_id','terminal_kind','terminal_reason']) IS DISTINCT FROM
      (to_jsonb(OLD)-ARRAY['status','version','offered_by','offered_at','offer_operation_id','confirmed_by','confirmed_at','confirmation_operation_id','terminal_by','terminal_at','terminal_operation_id','terminal_kind','terminal_reason']) OR
      (OLD.offered_by IS NOT NULL AND ROW(NEW.offered_by,NEW.offered_at,NEW.offer_operation_id) IS DISTINCT FROM ROW(OLD.offered_by,OLD.offered_at,OLD.offer_operation_id)) OR
      (OLD.confirmed_by IS NOT NULL AND ROW(NEW.confirmed_by,NEW.confirmed_at,NEW.confirmation_operation_id) IS DISTINCT FROM ROW(OLD.confirmed_by,OLD.confirmed_at,OLD.confirmation_operation_id)) OR
      (OLD.status='requested' AND NEW.status<>'offered' AND NEW.offered_by IS NOT NULL) OR
      (OLD.status<>'offered' OR NEW.status<>'confirmed') AND NEW.confirmed_by IS DISTINCT FROM OLD.confirmed_by
    THEN RAISE EXCEPTION 'Immutable swap lifecycle or consent' USING ERRCODE='23514'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER swap_request_guard BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.workforce_shift_swap_requests FOR EACH ROW EXECUTE FUNCTION {{schema}}.swap_request_guard();

CREATE FUNCTION {{schema}}.swap_leg_guard() RETURNS trigger LANGUAGE plpgsql AS $$
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
    IF NOT FOUND OR s.status IS DISTINCT FROM 'published' OR clock_timestamp()>=NEW.starts_at OR
      ROW(s.version,s.starts_at,s.ends_at) IS DISTINCT FROM ROW(NEW.source_version,NEW.starts_at,NEW.ends_at) OR
      NEW.replacement_shift_id IS NOT NULL OR
      (NEW.leg='a' AND r.status<>'requested') OR (NEW.leg='b' AND r.status NOT IN ('requested','offered')) OR
      NEW.work_references IS DISTINCT FROM {{schema}}.tasks_swap_references(NEW.company_id,NEW.source_shift_id,NEW.location_id) OR
      {{schema}}.tasks_swap_pristine(NEW.company_id,NEW.source_shift_id) IS NOT TRUE
    THEN RAISE EXCEPTION 'Exact pristine swap leg required' USING ERRCODE='23514'; END IF;
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
CREATE TRIGGER swap_leg_guard BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.workforce_shift_swap_legs FOR EACH ROW EXECUTE FUNCTION {{schema}}.swap_leg_guard();
CREATE TRIGGER swap_command_guard BEFORE UPDATE OR DELETE ON {{schema}}.workforce_shift_swap_commands FOR EACH ROW EXECUTE FUNCTION {{schema}}.transfer_evidence_guard();
CREATE TRIGGER task_swap_link_guard BEFORE UPDATE OR DELETE ON {{schema}}.task_swap_links FOR EACH ROW EXECUTE FUNCTION {{schema}}.transfer_evidence_guard();
CREATE FUNCTION {{schema}}.tasks_swap_link_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE l {{schema}}.workforce_shift_swap_legs%ROWTYPE;
BEGIN
  SELECT * INTO l FROM {{schema}}.workforce_shift_swap_legs WHERE company_id=NEW.company_id AND request_id=NEW.request_id AND leg=NEW.leg;
  IF NOT FOUND OR l.work_references->NEW.position->>'id' IS DISTINCT FROM NEW.source_task_id::text OR
    l.work_references->NEW.position->>'templateId' IS DISTINCT FROM NEW.template_id::text OR
    l.work_references->NEW.position->>'revisionId' IS DISTINCT FROM NEW.revision_id::text THEN
    RAISE EXCEPTION 'Captured Tasks correspondence required' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tasks_swap_link_insert_guard BEFORE INSERT ON {{schema}}.task_swap_links FOR EACH ROW EXECUTE FUNCTION {{schema}}.tasks_swap_link_guard();

CREATE FUNCTION {{schema}}.handoff_claim_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE active boolean;
BEGIN
  IF TG_OP='UPDATE' THEN RAISE EXCEPTION 'Claim ownership immutable' USING ERRCODE='23514'; END IF;
  IF TG_OP='DELETE' THEN
    IF OLD.transfer_request_id IS NOT NULL THEN
      SELECT status IN ('proposed','accepted') INTO active FROM {{schema}}.workforce_shift_transfer_requests WHERE company_id=OLD.company_id AND id=OLD.transfer_request_id;
    ELSE
      SELECT status IN ('requested','offered','confirmed') INTO active FROM {{schema}}.workforce_shift_swap_requests WHERE company_id=OLD.company_id AND id=OLD.swap_request_id;
    END IF;
    IF active IS DISTINCT FROM false THEN RAISE EXCEPTION 'Terminal owner required for release' USING ERRCODE='23514'; END IF;
    RETURN OLD;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER handoff_claim_guard BEFORE UPDATE OR DELETE ON {{schema}}.workforce_shift_handoff_claims FOR EACH ROW EXECUTE FUNCTION {{schema}}.handoff_claim_guard();

CREATE FUNCTION {{schema}}.handoff_transfer_complete(c uuid,r uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE p {{schema}}.workforce_shift_transfer_requests%ROWTYPE; n integer;
BEGIN
  SELECT * INTO p FROM {{schema}}.workforce_shift_transfer_requests WHERE company_id=c AND id=r;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transfer claim parent missing' USING ERRCODE='23514'; END IF;
  SELECT count(*) INTO n FROM {{schema}}.workforce_shift_handoff_claims WHERE company_id=c AND transfer_request_id=r;
  IF n<>(CASE WHEN p.status IN ('proposed','accepted') THEN 1 ELSE 0 END) THEN
    RAISE EXCEPTION 'Exact transfer claim required' USING ERRCODE='23514',CONSTRAINT='handoff_transfer_complete';
  END IF;
END $$;
CREATE FUNCTION {{schema}}.handoff_swap_complete(c uuid,r uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE p {{schema}}.workforce_shift_swap_requests%ROWTYPE; n integer; active boolean;
BEGIN
  SELECT * INTO p FROM {{schema}}.workforce_shift_swap_requests WHERE company_id=c AND id=r;
  IF NOT FOUND THEN RAISE EXCEPTION 'Swap claim parent missing' USING ERRCODE='23514'; END IF;
  active:=p.status IN ('requested','offered','confirmed');
  n:=CASE WHEN p.offered_by IS NULL THEN 1 ELSE 2 END;
  IF (SELECT count(*) FROM {{schema}}.workforce_shift_swap_legs WHERE company_id=c AND request_id=r)<>n OR
    NOT EXISTS(SELECT 1 FROM {{schema}}.workforce_shift_swap_legs WHERE company_id=c AND request_id=r AND leg='a') OR
    (SELECT count(*) FROM {{schema}}.workforce_shift_handoff_claims WHERE company_id=c AND swap_request_id=r)<>(CASE WHEN active THEN n ELSE 0 END) OR
    EXISTS(SELECT 1 FROM {{schema}}.workforce_shift_swap_legs WHERE company_id=c AND request_id=r AND (replacement_shift_id IS NOT NULL) IS DISTINCT FROM (p.status='approved')) OR
    (p.status<>'approved' AND EXISTS(SELECT 1 FROM {{schema}}.task_swap_links WHERE company_id=c AND request_id=r))
  THEN RAISE EXCEPTION 'Exact swap legs and claims required' USING ERRCODE='23514',CONSTRAINT='handoff_swap_complete'; END IF;
END $$;
CREATE FUNCTION {{schema}}.handoff_parent_complete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_TABLE_NAME='workforce_shift_transfer_requests' THEN PERFORM {{schema}}.handoff_transfer_complete(NEW.company_id,NEW.id);
  ELSIF TG_TABLE_NAME='workforce_shift_swap_requests' THEN PERFORM {{schema}}.handoff_swap_complete(NEW.company_id,NEW.id);
  ELSE PERFORM {{schema}}.handoff_swap_complete(NEW.company_id,NEW.request_id); END IF;
  RETURN NULL;
END $$;
CREATE FUNCTION {{schema}}.handoff_claim_complete() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c {{schema}}.workforce_shift_handoff_claims%ROWTYPE;
BEGIN
  IF TG_OP='DELETE' THEN c:=OLD; ELSE c:=NEW; END IF;
  IF c.transfer_request_id IS NOT NULL THEN PERFORM {{schema}}.handoff_transfer_complete(c.company_id,c.transfer_request_id);
  ELSE PERFORM {{schema}}.handoff_swap_complete(c.company_id,c.swap_request_id); END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER handoff_transfer_complete AFTER INSERT OR UPDATE ON {{schema}}.workforce_shift_transfer_requests DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.handoff_parent_complete();
CREATE CONSTRAINT TRIGGER handoff_swap_complete AFTER INSERT OR UPDATE ON {{schema}}.workforce_shift_swap_requests DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.handoff_parent_complete();
CREATE CONSTRAINT TRIGGER handoff_leg_complete AFTER INSERT OR UPDATE ON {{schema}}.workforce_shift_swap_legs DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.handoff_parent_complete();
CREATE CONSTRAINT TRIGGER handoff_task_link_complete AFTER INSERT ON {{schema}}.task_swap_links DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.handoff_parent_complete();
CREATE CONSTRAINT TRIGGER handoff_claim_complete AFTER INSERT OR DELETE ON {{schema}}.workforce_shift_handoff_claims DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.handoff_claim_complete();

-- Tasks owns paired correspondence and complete snapshot equality at approval.
CREATE FUNCTION {{schema}}.tasks_swap_approval_complete(c uuid,r uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE l {{schema}}.workforce_shift_swap_legs%ROWTYPE; n integer;
BEGIN
  FOR l IN SELECT * FROM {{schema}}.workforce_shift_swap_legs WHERE company_id=c AND request_id=r ORDER BY leg LOOP
    n:=jsonb_array_length(l.work_references);
    IF l.work_references IS DISTINCT FROM {{schema}}.tasks_swap_references(c,l.source_shift_id,l.location_id) OR
      (SELECT count(*) FROM {{schema}}.task_swap_links WHERE company_id=c AND request_id=r AND leg=l.leg)<>n OR
      (SELECT count(*) FROM {{schema}}.task_instances WHERE company_id=c AND shift_id=l.replacement_shift_id)<>n OR
      EXISTS(SELECT 1 FROM {{schema}}.task_swap_links x JOIN {{schema}}.task_instances s ON s.id=x.source_task_id JOIN {{schema}}.task_instances b ON b.id=x.replacement_task_id
        WHERE x.company_id=c AND x.request_id=r AND x.leg=l.leg AND
        (s.status IS DISTINCT FROM 'cancelled' OR s.version IS DISTINCT FROM 2::bigint OR s.employee_id IS DISTINCT FROM l.source_employee_id OR
         s.started_at IS NOT NULL OR s.started_by IS NOT NULL OR
         b.status IS DISTINCT FROM 'open' OR b.version IS DISTINCT FROM 1::bigint OR b.employee_id IS DISTINCT FROM l.incoming_employee_id OR
         b.content::jsonb IS DISTINCT FROM s.content::jsonb OR
         EXISTS(SELECT 1 FROM {{schema}}.task_step_results e WHERE e.instance_id IN (s.id,b.id)) OR
         EXISTS(SELECT 1 FROM {{schema}}.task_numeric_attempts e WHERE e.instance_id IN (s.id,b.id)) OR
         EXISTS(SELECT 1 FROM {{schema}}.task_blockings e WHERE e.instance_id IN (s.id,b.id)) OR
         EXISTS(SELECT 1 FROM {{schema}}.task_execution_commands e WHERE e.instance_id IN (s.id,b.id)))) OR
      EXISTS((SELECT template_id,revision_id,position FROM {{schema}}.shift_template_selections WHERE shift_id=l.source_shift_id AND company_id=c)
        EXCEPT (SELECT template_id,revision_id,position FROM {{schema}}.shift_template_selections WHERE shift_id=l.replacement_shift_id AND company_id=c)) OR
      EXISTS((SELECT template_id,revision_id,position FROM {{schema}}.shift_template_selections WHERE shift_id=l.replacement_shift_id AND company_id=c)
        EXCEPT (SELECT template_id,revision_id,position FROM {{schema}}.shift_template_selections WHERE shift_id=l.source_shift_id AND company_id=c))
    THEN RAISE EXCEPTION 'Incomplete exact paired Tasks' USING ERRCODE='23514',CONSTRAINT='tasks_swap_approval_complete'; END IF;
  END LOOP;
END $$;
CREATE FUNCTION {{schema}}.swap_approval_complete() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE l {{schema}}.workforce_shift_swap_legs%ROWTYPE; a {{schema}}.shifts%ROWTYPE; b {{schema}}.shifts%ROWTYPE; first_start timestamptz;
BEGIN
  IF NEW.status<>'approved' THEN RETURN NULL; END IF;
  PERFORM {{schema}}.handoff_swap_complete(NEW.company_id,NEW.id);
  FOR l IN SELECT * FROM {{schema}}.workforce_shift_swap_legs WHERE company_id=NEW.company_id AND request_id=NEW.id ORDER BY leg LOOP
    SELECT * INTO a FROM {{schema}}.shifts WHERE company_id=NEW.company_id AND id=l.source_shift_id;
    SELECT * INTO b FROM {{schema}}.shifts WHERE company_id=NEW.company_id AND id=l.replacement_shift_id;
    IF a.status IS DISTINCT FROM 'cancelled' OR b.status IS DISTINCT FROM 'published' OR
      a.version IS DISTINCT FROM l.source_version+1 OR b.version IS DISTINCT FROM 2::bigint OR
      ROW(b.swap_request_id,b.swap_leg) IS DISTINCT FROM ROW(l.request_id,l.leg) OR
      ROW(a.employee_id,b.employee_id,a.starts_at,a.ends_at,b.starts_at,b.ends_at) IS DISTINCT FROM
      ROW(l.source_employee_id,l.incoming_employee_id,l.starts_at,l.ends_at,l.starts_at,l.ends_at)
    THEN RAISE EXCEPTION 'Incomplete exact paired Shifts' USING ERRCODE='23514'; END IF;
    first_start:=LEAST(first_start,l.starts_at);
  END LOOP;
  PERFORM {{schema}}.tasks_swap_approval_complete(NEW.company_id,NEW.id);
  -- Fresh approval only; ordinary later work and replay never update this parent.
  IF first_start IS NULL OR clock_timestamp()>=first_start THEN
    RAISE EXCEPTION 'Swap requires future originals' USING ERRCODE='23514',CONSTRAINT='swap_approval_future';
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER swap_approval_complete AFTER UPDATE ON {{schema}}.workforce_shift_swap_requests DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.swap_approval_complete();

CREATE FUNCTION {{schema}}.tasks_swap_link_projection(c uuid,r uuid,g text) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('sourceTaskId',source_task_id::text,'replacementTaskId',replacement_task_id::text,
    'sourceShiftId',source_shift_id::text,'replacementShiftId',replacement_shift_id::text,'templateId',template_id::text,'revisionId',revision_id::text,'position',position) ORDER BY position),'[]'::jsonb)
  FROM {{schema}}.task_swap_links WHERE company_id=c AND request_id=r AND leg=g
$$;
-- Same explicit UTC/offset grammar, calendar, precision and UTC range as
-- api_contracts.shiftInstant. JSON null is valid only for absent lifecycle facts.
-- Offset arithmetic also supports the protocol's offsets beyond PostgreSQL's
-- timestamptz input offset range, without accepting its permissive date parser.
CREATE FUNCTION {{schema}}.swap_receipt_instant(j jsonb, expected timestamptz) RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE parts text[]; instant timestamptz; zone text; offset_minutes integer;
BEGIN
  IF expected IS NULL THEN RETURN j IS NOT DISTINCT FROM 'null'::jsonb; END IF;
  IF jsonb_typeof(j) IS DISTINCT FROM 'string' THEN RETURN false; END IF;
  parts:=regexp_match(j #>> '{}','^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,6}))?(Z|[+-][0-9]{2}:[0-9]{2})$');
  IF parts IS NULL OR parts[1]::integer<1 OR parts[4]::integer>23 OR parts[5]::integer>59 OR parts[6]::integer>59 THEN RETURN false; END IF;
  zone:=parts[8]; offset_minutes:=0;
  IF zone<>'Z' THEN
    IF substring(zone,2,2)::integer>23 OR substring(zone,5,2)::integer>59 THEN RETURN false; END IF;
    offset_minutes:=(substring(zone,2,2)::integer*60+substring(zone,5,2)::integer)*(CASE left(zone,1) WHEN '+' THEN 1 ELSE -1 END);
  END IF;
  instant:=((make_date(parts[1]::integer,parts[2]::integer,parts[3]::integer)::timestamp +
    parts[4]::integer*interval '1 hour' + parts[5]::integer*interval '1 minute' + parts[6]::integer*interval '1 second' +
    COALESCE(rpad(parts[7],6,'0')::integer,0)*interval '1 microsecond') AT TIME ZONE 'UTC') - offset_minutes*interval '1 minute';
  RETURN instant>=timestamptz '0001-01-01 00:00:00+00' AND instant<timestamptz '10000-01-01 00:00:00+00' AND instant=expected;
EXCEPTION WHEN datetime_field_overflow THEN RETURN false;
END $$;
-- Every numeric receipt/intent field is an integer in this bounded wire
-- contract. jsonb equality alone treats 1 and 1.0 as equal, unlike Dart JSON.
CREATE FUNCTION {{schema}}.swap_receipt_integer_types(j jsonb) RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE child jsonb;
BEGIN
  IF jsonb_typeof(j)='number' THEN RETURN (j #>> '{}') ~ '^(0|[1-9][0-9]*)$'; END IF;
  IF jsonb_typeof(j)='object' THEN
    FOR child IN SELECT value FROM jsonb_each(j) LOOP
      IF {{schema}}.swap_receipt_integer_types(child) IS NOT TRUE THEN RETURN false; END IF;
    END LOOP;
  ELSIF jsonb_typeof(j)='array' THEN
    FOR child IN SELECT value FROM jsonb_array_elements(j) LOOP
      IF {{schema}}.swap_receipt_integer_types(child) IS NOT TRUE THEN RETURN false; END IF;
    END LOOP;
  END IF;
  RETURN j IS NOT NULL;
END $$;
CREATE FUNCTION {{schema}}.swap_command_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r {{schema}}.workforce_shift_swap_requests%ROWTYPE; a {{schema}}.workforce_shift_swap_legs%ROWTYPE;
  b {{schema}}.workforce_shift_swap_legs%ROWTYPE; keys text[]; expected jsonb; j jsonb; legs jsonb;
  state text; operation uuid; consent_actor uuid; l {{schema}}.workforce_shift_swap_legs%ROWTYPE;
BEGIN
  IF {{schema}}.swap_receipt_integer_types(NEW.payload) IS NOT TRUE OR {{schema}}.swap_receipt_integer_types(NEW.result) IS NOT TRUE THEN
    RAISE EXCEPTION 'Integer wire fields required' USING ERRCODE='23514',CONSTRAINT='swap_command_result';
  END IF;
  SELECT * INTO r FROM {{schema}}.workforce_shift_swap_requests WHERE company_id=NEW.company_id AND id=NEW.request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Receipt parent required' USING ERRCODE='23514'; END IF;
  SELECT * INTO a FROM {{schema}}.workforce_shift_swap_legs WHERE company_id=NEW.company_id AND request_id=NEW.request_id AND leg='a';
  SELECT * INTO b FROM {{schema}}.workforce_shift_swap_legs WHERE company_id=NEW.company_id AND request_id=NEW.request_id AND leg='b';
  keys:=ARRAY['operationId','expectedVersion'];
  IF NEW.kind='request' THEN
    keys:=ARRAY['operationId','requestId','sourceShiftId','expectedSourceVersion','recipientEmployeeId'];
    expected:=jsonb_build_object('operationId',NEW.operation_id::text,'requestId',r.id::text,'sourceShiftId',a.source_shift_id::text,
      'expectedSourceVersion',a.source_version,'recipientEmployeeId',r.recipient_employee_id::text);
    state:='requested'; operation:=r.request_operation_id; consent_actor:=r.source_account_id;
    IF NEW.expected_version IS DISTINCT FROM a.source_version THEN RAISE EXCEPTION 'Source version receipt mismatch' USING ERRCODE='23514'; END IF;
  ELSE
    expected:=jsonb_build_object('operationId',NEW.operation_id::text,'expectedVersion',NEW.expected_version);
    IF NEW.kind='offer' THEN
      keys:=keys||ARRAY['counterpartShiftId','expectedCounterpartVersion'];
      expected:=expected||jsonb_build_object('counterpartShiftId',b.source_shift_id::text,'expectedCounterpartVersion',b.source_version);
      state:='offered'; operation:=r.offer_operation_id; consent_actor:=r.recipient_account_id;
    ELSIF NEW.kind='confirm' THEN state:='confirmed'; operation:=r.confirmation_operation_id; consent_actor:=r.source_account_id;
    ELSE
      state:=CASE NEW.kind WHEN 'decline' THEN 'declined' WHEN 'manager_reject' THEN 'rejected' WHEN 'manager_approve' THEN 'approved' ELSE 'withdrawn' END;
      operation:=r.terminal_operation_id; consent_actor:=r.terminal_by;
      IF r.terminal_kind IS DISTINCT FROM NEW.kind THEN RAISE EXCEPTION 'Closing kind mismatch' USING ERRCODE='23514'; END IF;
      IF NEW.kind IN ('source_withdraw','recipient_withdraw','manager_reject') THEN
        keys:=keys||ARRAY['reason']; expected:=expected||jsonb_build_object('reason',r.terminal_reason);
      END IF;
    END IF;
  END IF;
  IF NEW.payload IS DISTINCT FROM expected OR NEW.operation_id IS DISTINCT FROM operation OR NEW.actor_id IS DISTINCT FROM consent_actor OR
     NEW.location_id IS DISTINCT FROM r.location_id OR NEW.accepted_version IS DISTINCT FROM r.version OR r.status IS DISTINCT FROM state THEN
    RAISE EXCEPTION 'Exact canonical command receipt required' USING ERRCODE='23514',CONSTRAINT='swap_command_intent';
  END IF;
  j:=NEW.result->'request';
  IF (jsonb_typeof(j)='object' AND jsonb_typeof(j->'sourceName')='string' AND jsonb_typeof(j->'recipientName')='string' AND
      length(j->>'sourceName') BETWEEN 1 AND 120 AND length(j->>'recipientName') BETWEEN 1 AND 120) IS NOT TRUE THEN
    RAISE EXCEPTION 'Bounded participant evidence required' USING ERRCODE='23514'; END IF;
  legs:='[]'::jsonb;
  FOR l IN SELECT * FROM {{schema}}.workforce_shift_swap_legs WHERE company_id=NEW.company_id AND request_id=NEW.request_id ORDER BY leg LOOP
    legs:=legs||jsonb_build_array(jsonb_build_object('leg',l.leg,'sourceShiftId',l.source_shift_id::text,'sourceVersion',l.source_version,
      'sourceEmployeeId',l.source_employee_id::text,'incomingEmployeeId',l.incoming_employee_id::text,
      'startsAt',j->'legs'->(CASE l.leg WHEN 'a' THEN 0 ELSE 1 END)->'startsAt',
      'endsAt',j->'legs'->(CASE l.leg WHEN 'a' THEN 0 ELSE 1 END)->'endsAt',
      'tasks',l.work_references,'replacementShiftId',l.replacement_shift_id::text,'taskLinks',{{schema}}.tasks_swap_link_projection(l.company_id,l.request_id,l.leg)));
    IF {{schema}}.swap_receipt_instant(j->'legs'->(CASE l.leg WHEN 'a' THEN 0 ELSE 1 END)->'startsAt',l.starts_at) IS NOT TRUE OR
       {{schema}}.swap_receipt_instant(j->'legs'->(CASE l.leg WHEN 'a' THEN 0 ELSE 1 END)->'endsAt',l.ends_at) IS NOT TRUE THEN
      RAISE EXCEPTION 'Receipt interval mismatch' USING ERRCODE='23514',CONSTRAINT='swap_command_result'; END IF;
  END LOOP;
  expected:=jsonb_build_object('id',r.id::text,'companyId',r.company_id::text,'locationId',r.location_id::text,
    'sourceEmployeeId',r.source_employee_id::text,'recipientEmployeeId',r.recipient_employee_id::text,
    'sourceName',j->'sourceName','recipientName',j->'recipientName','status',r.status,'version',r.version,
    'requestedAt',j->'requestedAt','requestOperationId',r.request_operation_id::text,
    'offeredAt',j->'offeredAt','offerOperationId',r.offer_operation_id::text,
    'confirmedAt',j->'confirmedAt','confirmationOperationId',r.confirmation_operation_id::text,
    'terminalAt',j->'terminalAt','terminalOperationId',r.terminal_operation_id::text,'terminalKind',r.terminal_kind,'terminalReason',r.terminal_reason,'legs',legs);
  IF NEW.result IS DISTINCT FROM jsonb_build_object('operationId',NEW.operation_id::text,'kind',NEW.kind,'acceptedVersion',NEW.accepted_version,
      'statusCode',NEW.status_code,'request',expected,'replayed',false) OR
      {{schema}}.swap_receipt_instant(j->'requestedAt',r.requested_at) IS NOT TRUE OR
      {{schema}}.swap_receipt_instant(j->'offeredAt',r.offered_at) IS NOT TRUE OR
      {{schema}}.swap_receipt_instant(j->'confirmedAt',r.confirmed_at) IS NOT TRUE OR
      {{schema}}.swap_receipt_instant(j->'terminalAt',r.terminal_at) IS NOT TRUE THEN
    RAISE EXCEPTION 'Exact original result required' USING ERRCODE='23514',CONSTRAINT='swap_command_result';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER swap_command_insert_guard BEFORE INSERT ON {{schema}}.workforce_shift_swap_commands FOR EACH ROW EXECUTE FUNCTION {{schema}}.swap_command_guard();

-- Active stale sources deliberately retain their occupancy. Terminal history has
-- no invented past claim. Validate every backfilled parent in this transaction.
INSERT INTO {{schema}}.workforce_shift_handoff_claims(company_id,shift_id,location_id,transfer_request_id)
  SELECT company_id,source_shift_id,location_id,id FROM {{schema}}.workforce_shift_transfer_requests WHERE status IN ('proposed','accepted');
DO $$ DECLARE p record; BEGIN
  FOR p IN SELECT company_id,id FROM {{schema}}.workforce_shift_transfer_requests LOOP
    PERFORM {{schema}}.handoff_transfer_complete(p.company_id,p.id);
  END LOOP;
END $$;
