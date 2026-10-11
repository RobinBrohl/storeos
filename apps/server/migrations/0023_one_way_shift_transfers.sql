-- Identity and Tasks anchors add scoped FK targets only; no historical rows change.
ALTER TABLE {{schema}}.account_employee_links ADD CONSTRAINT transfer_link_scope
  UNIQUE(id,company_id,location_id,account_id,employee_id);
ALTER TABLE {{schema}}.task_instances ADD CONSTRAINT transfer_task_scope
  UNIQUE(id,company_id,location_id,shift_id,template_id,revision_id,position);

-- Workforce owns immutable proposal identity, consent and Shift lineage.
CREATE TABLE {{schema}}.workforce_shift_transfer_requests (
  company_id uuid NOT NULL, location_id uuid NOT NULL, id uuid NOT NULL,
  source_shift_id uuid NOT NULL, source_version bigint NOT NULL CHECK(source_version>0),
  source_employee_id uuid NOT NULL, recipient_employee_id uuid NOT NULL,
  starts_at timestamptz NOT NULL, ends_at timestamptz NOT NULL,
  proposed_by uuid NOT NULL, proposed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  source_link_id uuid NOT NULL, recipient_link_id uuid NOT NULL, recipient_account_id uuid NOT NULL,
  source_account_version bigint NOT NULL CHECK(source_account_version>0),
  recipient_account_version bigint NOT NULL CHECK(recipient_account_version>0),
  proposal_operation_id uuid NOT NULL,
  proposal_kind text NOT NULL DEFAULT 'propose' CHECK(proposal_kind='propose'),
  status text NOT NULL DEFAULT 'proposed' CHECK(status IN ('proposed','accepted','declined','withdrawn','rejected','approved')),
  version integer NOT NULL DEFAULT 1 CHECK(version BETWEEN 1 AND 3),
  accepted_by uuid, accepted_at timestamptz, acceptance_operation_id uuid,
  acceptance_kind text NOT NULL DEFAULT 'accept' CHECK(acceptance_kind='accept'),
  terminal_by uuid, terminal_at timestamptz, terminal_reason text,
  terminal_operation_id uuid, terminal_kind text,
  replacement_shift_id uuid,
  PRIMARY KEY(company_id,id), UNIQUE(company_id,id,location_id),
  UNIQUE(company_id,id,location_id,source_shift_id,replacement_shift_id),
  CHECK(source_employee_id<>recipient_employee_id AND starts_at<ends_at),
  CHECK(terminal_reason IS NULL OR (length(terminal_reason) BETWEEN 1 AND 500 AND terminal_reason=btrim(terminal_reason) AND terminal_reason !~ '[[:cntrl:]]')),
  FOREIGN KEY(source_shift_id,company_id,location_id,source_employee_id) REFERENCES {{schema}}.shifts(id,company_id,location_id,employee_id),
  FOREIGN KEY(replacement_shift_id,company_id,location_id,recipient_employee_id) REFERENCES {{schema}}.shifts(id,company_id,location_id,employee_id),
  FOREIGN KEY(source_employee_id,company_id,location_id) REFERENCES {{schema}}.employees(id,company_id,location_id),
  FOREIGN KEY(recipient_employee_id,company_id,location_id) REFERENCES {{schema}}.employees(id,company_id,location_id),
  FOREIGN KEY(source_link_id,company_id,location_id,proposed_by,source_employee_id) REFERENCES {{schema}}.account_employee_links(id,company_id,location_id,account_id,employee_id),
  FOREIGN KEY(recipient_link_id,company_id,location_id,recipient_account_id,recipient_employee_id) REFERENCES {{schema}}.account_employee_links(id,company_id,location_id,account_id,employee_id),
  FOREIGN KEY(proposed_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY(accepted_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY(terminal_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  CONSTRAINT transfer_consent_shape CHECK(
    (accepted_by IS NULL AND accepted_at IS NULL AND acceptance_operation_id IS NULL) OR
    (accepted_by IS NOT NULL AND accepted_by=recipient_account_id AND accepted_at IS NOT NULL AND accepted_at>=proposed_at AND acceptance_operation_id IS NOT NULL)),
  CONSTRAINT transfer_lifecycle_shape CHECK(
    (status='proposed' AND version=1 AND accepted_by IS NULL AND terminal_by IS NULL AND terminal_at IS NULL AND terminal_reason IS NULL AND terminal_operation_id IS NULL AND terminal_kind IS NULL AND replacement_shift_id IS NULL) OR
    (status='accepted' AND version=2 AND accepted_by IS NOT NULL AND terminal_by IS NULL AND terminal_at IS NULL AND terminal_reason IS NULL AND terminal_operation_id IS NULL AND terminal_kind IS NULL AND replacement_shift_id IS NULL) OR
    (status IN ('declined','withdrawn','rejected','approved') AND version=CASE WHEN accepted_by IS NULL THEN 2 ELSE 3 END AND terminal_by IS NOT NULL AND terminal_at IS NOT NULL AND terminal_at>=COALESCE(accepted_at,proposed_at) AND terminal_operation_id IS NOT NULL AND terminal_kind IS NOT NULL AND
      ((status='declined' AND accepted_by IS NULL AND terminal_kind='decline' AND terminal_by=recipient_account_id AND terminal_reason IS NULL AND replacement_shift_id IS NULL) OR
       (status='withdrawn' AND terminal_kind IN ('source_withdraw','recipient_withdraw') AND terminal_reason IS NOT NULL AND replacement_shift_id IS NULL AND (terminal_kind='source_withdraw' OR (accepted_by IS NOT NULL AND terminal_by=accepted_by))) OR
       (status='rejected' AND terminal_kind='manager_reject' AND terminal_reason IS NOT NULL AND replacement_shift_id IS NULL) OR
       (status='approved' AND terminal_kind='manager_approve' AND accepted_by IS NOT NULL AND terminal_by<>proposed_by AND terminal_by<>accepted_by AND terminal_reason IS NULL AND replacement_shift_id IS NOT NULL))))
);
CREATE UNIQUE INDEX transfer_active_source ON {{schema}}.workforce_shift_transfer_requests(company_id,source_shift_id) WHERE status IN ('proposed','accepted');
CREATE UNIQUE INDEX transfer_approved_source ON {{schema}}.workforce_shift_transfer_requests(company_id,source_shift_id) WHERE status='approved';
CREATE UNIQUE INDEX transfer_replacement ON {{schema}}.workforce_shift_transfer_requests(company_id,replacement_shift_id) WHERE replacement_shift_id IS NOT NULL;
CREATE INDEX transfer_self_source ON {{schema}}.workforce_shift_transfer_requests(company_id,location_id,source_employee_id,id);
CREATE INDEX transfer_self_recipient ON {{schema}}.workforce_shift_transfer_requests(company_id,location_id,recipient_employee_id,id);
CREATE INDEX transfer_manager ON {{schema}}.workforce_shift_transfer_requests(company_id,location_id,status,id);

CREATE TABLE {{schema}}.workforce_shift_transfer_commands (
  company_id uuid NOT NULL, operation_id uuid NOT NULL, location_id uuid NOT NULL,
  request_id uuid NOT NULL, actor_id uuid NOT NULL,
  kind text NOT NULL CHECK(kind IN ('propose','accept','decline','source_withdraw','recipient_withdraw','manager_reject','manager_approve')),
  expected_version bigint NOT NULL CHECK(expected_version>0),
  payload jsonb NOT NULL CHECK(jsonb_typeof(payload)='object' AND octet_length(payload::text)<=8192),
  result jsonb NOT NULL CHECK(jsonb_typeof(result)='object' AND octet_length(result::text)<=32768),
  committed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(company_id,operation_id),
  UNIQUE(company_id,operation_id,location_id,request_id,actor_id,kind),
  FOREIGN KEY(company_id,request_id,location_id) REFERENCES {{schema}}.workforce_shift_transfer_requests(company_id,id,location_id),
  FOREIGN KEY(actor_id,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id)
);
ALTER TABLE {{schema}}.workforce_shift_transfer_requests ADD CONSTRAINT transfer_proposal_receipt
  FOREIGN KEY(company_id,proposal_operation_id,location_id,id,proposed_by,proposal_kind) REFERENCES {{schema}}.workforce_shift_transfer_commands(company_id,operation_id,location_id,request_id,actor_id,kind) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE {{schema}}.workforce_shift_transfer_requests ADD CONSTRAINT transfer_acceptance_receipt
  FOREIGN KEY(company_id,acceptance_operation_id,location_id,id,accepted_by,acceptance_kind) REFERENCES {{schema}}.workforce_shift_transfer_commands(company_id,operation_id,location_id,request_id,actor_id,kind) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE {{schema}}.workforce_shift_transfer_requests ADD CONSTRAINT transfer_terminal_receipt
  FOREIGN KEY(company_id,terminal_operation_id,location_id,id,terminal_by,terminal_kind) REFERENCES {{schema}}.workforce_shift_transfer_commands(company_id,operation_id,location_id,request_id,actor_id,kind) DEFERRABLE INITIALLY DEFERRED;

-- Tasks owns exact append-only source/replacement correspondence.
CREATE TABLE {{schema}}.task_transfer_links (
  company_id uuid NOT NULL, location_id uuid NOT NULL, request_id uuid NOT NULL,
  source_shift_id uuid NOT NULL, replacement_shift_id uuid NOT NULL,
  source_task_id uuid NOT NULL, replacement_task_id uuid NOT NULL,
  template_id uuid NOT NULL, revision_id uuid NOT NULL, position integer NOT NULL CHECK(position BETWEEN 0 AND 9),
  PRIMARY KEY(company_id,request_id,position),
  UNIQUE(company_id,source_task_id), UNIQUE(company_id,replacement_task_id),
  CHECK(source_shift_id<>replacement_shift_id AND source_task_id<>replacement_task_id),
  FOREIGN KEY(company_id,request_id,location_id,source_shift_id,replacement_shift_id) REFERENCES {{schema}}.workforce_shift_transfer_requests(company_id,id,location_id,source_shift_id,replacement_shift_id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY(source_task_id,company_id,location_id,source_shift_id,template_id,revision_id,position) REFERENCES {{schema}}.task_instances(id,company_id,location_id,shift_id,template_id,revision_id,position),
  FOREIGN KEY(replacement_task_id,company_id,location_id,replacement_shift_id,template_id,revision_id,position) REFERENCES {{schema}}.task_instances(id,company_id,location_id,shift_id,template_id,revision_id,position)
);
CREATE FUNCTION {{schema}}.transfer_request_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Transfer evidence retained' USING ERRCODE='23514'; END IF;
  IF TG_OP='INSERT' THEN
    IF NEW.status<>'proposed' OR NEW.version<>1 THEN RAISE EXCEPTION 'Proposal required' USING ERRCODE='23514'; END IF;
  ELSE
    IF OLD.status NOT IN ('proposed','accepted') OR NEW.version<>OLD.version+1 OR
      NOT ((OLD.status='proposed' AND NEW.status IN ('accepted','declined','withdrawn','rejected')) OR (OLD.status='accepted' AND NEW.status IN ('withdrawn','rejected','approved'))) OR
      (to_jsonb(NEW)-ARRAY['status','version','accepted_by','accepted_at','acceptance_operation_id','terminal_by','terminal_at','terminal_reason','terminal_operation_id','terminal_kind','replacement_shift_id']) IS DISTINCT FROM
      (to_jsonb(OLD)-ARRAY['status','version','accepted_by','accepted_at','acceptance_operation_id','terminal_by','terminal_at','terminal_reason','terminal_operation_id','terminal_kind','replacement_shift_id']) OR
      (OLD.accepted_by IS NOT NULL AND ROW(NEW.accepted_by,NEW.accepted_at,NEW.acceptance_operation_id) IS DISTINCT FROM ROW(OLD.accepted_by,OLD.accepted_at,OLD.acceptance_operation_id)) OR
      (OLD.status='proposed' AND NEW.status<>'accepted' AND NEW.accepted_by IS NOT NULL)
    THEN RAISE EXCEPTION 'Immutable proposal, consent or terminal evidence' USING ERRCODE='23514'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER transfer_request_guard BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.workforce_shift_transfer_requests FOR EACH ROW EXECUTE FUNCTION {{schema}}.transfer_request_guard();
CREATE FUNCTION {{schema}}.transfer_evidence_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Immutable transfer evidence' USING ERRCODE='23514'; END $$;
CREATE TRIGGER transfer_command_guard BEFORE UPDATE OR DELETE ON {{schema}}.workforce_shift_transfer_commands FOR EACH ROW EXECUTE FUNCTION {{schema}}.transfer_evidence_guard();
CREATE TRIGGER task_transfer_link_guard BEFORE UPDATE OR DELETE ON {{schema}}.task_transfer_links FOR EACH ROW EXECUTE FUNCTION {{schema}}.transfer_evidence_guard();

-- Check approval-time effects at commit, without imposing permanent current
-- lifecycle requirements on replacement work that will execute normally later.
CREATE FUNCTION {{schema}}.transfer_approval_complete() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n integer; m integer; a {{schema}}.shifts%ROWTYPE; b {{schema}}.shifts%ROWTYPE;
BEGIN
  IF NEW.status<>'approved' THEN RETURN NULL; END IF;
  SELECT * INTO a FROM {{schema}}.shifts WHERE id=NEW.source_shift_id AND company_id=NEW.company_id;
  SELECT * INTO b FROM {{schema}}.shifts WHERE id=NEW.replacement_shift_id AND company_id=NEW.company_id;
  SELECT count(*) INTO n FROM {{schema}}.task_instances WHERE company_id=NEW.company_id AND shift_id=a.id;
  SELECT count(*) INTO m FROM {{schema}}.task_transfer_links WHERE company_id=NEW.company_id AND request_id=NEW.id;
  IF a.status IS DISTINCT FROM 'cancelled' OR b.status IS DISTINCT FROM 'published' OR
    a.employee_id<>NEW.source_employee_id OR b.employee_id<>NEW.recipient_employee_id OR a.version<>NEW.source_version+1 OR b.version<>2 OR
    ROW(a.starts_at,a.ends_at,b.starts_at,b.ends_at) IS DISTINCT FROM ROW(NEW.starts_at,NEW.ends_at,NEW.starts_at,NEW.ends_at) OR
    n NOT BETWEEN 1 AND 10 OR m<>n OR
    (SELECT count(*) FROM {{schema}}.task_instances WHERE company_id=NEW.company_id AND shift_id=b.id)<>n OR
    EXISTS(SELECT 1 FROM {{schema}}.task_transfer_links l JOIN {{schema}}.task_instances s ON s.id=l.source_task_id JOIN {{schema}}.task_instances r ON r.id=l.replacement_task_id WHERE l.company_id=NEW.company_id AND l.request_id=NEW.id AND (s.status<>'cancelled' OR r.status<>'open' OR r.version<>1 OR s.content::jsonb IS DISTINCT FROM r.content::jsonb)) OR
    EXISTS((SELECT template_id,revision_id,position FROM {{schema}}.shift_template_selections WHERE shift_id=a.id) EXCEPT (SELECT template_id,revision_id,position FROM {{schema}}.shift_template_selections WHERE shift_id=b.id)) OR
    EXISTS((SELECT template_id,revision_id,position FROM {{schema}}.shift_template_selections WHERE shift_id=b.id) EXCEPT (SELECT template_id,revision_id,position FROM {{schema}}.shift_template_selections WHERE shift_id=a.id))
  THEN RAISE EXCEPTION 'Incomplete exact transfer replacement' USING ERRCODE='23514'; END IF;
  -- Evaluate wall-clock time last, at the deferred fresh-approval boundary.
  -- Historical receipt replay does not update the request or fire this trigger.
  IF clock_timestamp() >= NEW.starts_at THEN
    RAISE EXCEPTION 'Transfer requires a future source Shift'
      USING ERRCODE='23514', CONSTRAINT='transfer_approval_future';
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER transfer_approval_complete AFTER UPDATE ON {{schema}}.workforce_shift_transfer_requests DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.transfer_approval_complete();
