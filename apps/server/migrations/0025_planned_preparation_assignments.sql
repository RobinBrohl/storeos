-- Production requests retain exact approved instructions; execution belongs to Batch.
ALTER TABLE {{schema}}.production_preparation_batches ADD CONSTRAINT preparation_batch_assignment_anchor
  UNIQUE(company_id,id,location_id,employee_id,recipe_id,revision_id,planned_declared_batch_count);

CREATE TABLE {{schema}}.production_preparation_assignments (
  id uuid NOT NULL,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  recipe_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  revision_status text NOT NULL DEFAULT 'published' CHECK(revision_status='published'),
  planned_declared_batch_count integer NOT NULL CHECK(planned_declared_batch_count BETWEEN 1 AND 9999),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  create_operation_id uuid NOT NULL,
  create_kind text NOT NULL DEFAULT 'create' CHECK(create_kind='create'),
  status text NOT NULL DEFAULT 'assigned',
  version integer NOT NULL DEFAULT 1,
  batch_id uuid,
  batch_operation_id uuid,
  batch_kind text NOT NULL DEFAULT 'open' CHECK(batch_kind='open'),
  started_by uuid,
  started_at timestamptz,
  withdrawn_by uuid,
  withdrawn_at timestamptz,
  withdrawal_reason text,
  terminal_operation_id uuid,
  terminal_actor uuid GENERATED ALWAYS AS(COALESCE(started_by,withdrawn_by)) STORED,
  terminal_kind text GENERATED ALWAYS AS(CASE status WHEN 'started' THEN 'start' WHEN 'withdrawn' THEN 'withdraw' END) STORED,
  PRIMARY KEY(company_id,id),
  UNIQUE(company_id,id,location_id),
  UNIQUE(company_id,batch_id),
  FOREIGN KEY(location_id,company_id) REFERENCES {{schema}}.locations(id,company_id),
  FOREIGN KEY(employee_id,company_id,location_id) REFERENCES {{schema}}.employees(id,company_id,location_id),
  FOREIGN KEY(created_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY(started_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY(withdrawn_by,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  FOREIGN KEY(revision_id,company_id,recipe_id,revision_status) REFERENCES {{schema}}.production_recipe_revisions(id,company_id,recipe_id,status),
  FOREIGN KEY(company_id,batch_id,location_id,employee_id,recipe_id,revision_id,planned_declared_batch_count)
    REFERENCES {{schema}}.production_preparation_batches(company_id,id,location_id,employee_id,recipe_id,revision_id,planned_declared_batch_count),
  FOREIGN KEY(company_id,batch_operation_id,batch_id,location_id,started_by,batch_kind)
    REFERENCES {{schema}}.production_preparation_batch_commands(company_id,operation_id,batch_id,location_id,actor_id,kind) DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT preparation_assignment_shape CHECK((
    (status='assigned' AND version=1 AND batch_id IS NULL AND batch_operation_id IS NULL AND started_by IS NULL AND started_at IS NULL AND withdrawn_by IS NULL AND withdrawn_at IS NULL AND withdrawal_reason IS NULL AND terminal_operation_id IS NULL) OR
    (status='started' AND version=2 AND batch_id IS NOT NULL AND batch_operation_id IS NOT NULL AND started_by IS NOT NULL AND started_at IS NOT NULL AND started_at>=created_at AND withdrawn_by IS NULL AND withdrawn_at IS NULL AND withdrawal_reason IS NULL AND terminal_operation_id IS NOT NULL AND batch_operation_id<>terminal_operation_id) OR
    (status='withdrawn' AND version=2 AND batch_id IS NULL AND batch_operation_id IS NULL AND started_by IS NULL AND started_at IS NULL AND withdrawn_by IS NOT NULL AND withdrawn_at IS NOT NULL AND withdrawn_at>=created_at AND withdrawal_reason IS NOT NULL AND length(withdrawal_reason) BETWEEN 1 AND 500 AND withdrawal_reason=btrim(withdrawal_reason) AND withdrawal_reason !~ '[[:cntrl:]]' AND terminal_operation_id IS NOT NULL)
  ) IS TRUE)
);
CREATE INDEX preparation_assignment_manager_page ON {{schema}}.production_preparation_assignments(company_id,location_id,status,id);
CREATE INDEX preparation_assignment_self_page ON {{schema}}.production_preparation_assignments(company_id,location_id,employee_id,id);

-- Every mandatory JSON comparison rejects SQL NULL, missing fields and JSON null.
CREATE FUNCTION {{schema}}.preparation_assignment_command_shape(k text,p jsonb,r jsonb) RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE keys text[]; f text; n numeric;
BEGIN
  IF jsonb_typeof(p) IS DISTINCT FROM 'object' OR jsonb_typeof(r) IS DISTINCT FROM 'object' OR
     jsonb_typeof(r->'assignment') IS DISTINCT FROM 'object' OR r->'replayed' IS DISTINCT FROM 'false'::jsonb THEN RETURN false; END IF;
  keys:=CASE k WHEN 'create' THEN ARRAY['operationId','id','recipeId','revisionId','employeeId','expectedEmployeeVersion','plannedDeclaredBatchCount']
    WHEN 'withdraw' THEN ARRAY['operationId','expectedVersion','reason'] WHEN 'start' THEN ARRAY['operationId','expectedVersion'] ELSE NULL END;
  IF keys IS NULL OR (SELECT count(*) FROM jsonb_object_keys(p))<>cardinality(keys) OR NOT(p ?& keys) THEN RETURN false; END IF;
  FOREACH f IN ARRAY (CASE WHEN k='create' THEN ARRAY['operationId','id','recipeId','revisionId','employeeId'] ELSE ARRAY['operationId'] END) LOOP
    IF jsonb_typeof(p->f) IS DISTINCT FROM 'string' OR (p->>f) !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN false; END IF;
  END LOOP;
  FOREACH f IN ARRAY (CASE WHEN k='create' THEN ARRAY['expectedEmployeeVersion','plannedDeclaredBatchCount'] ELSE ARRAY['expectedVersion'] END) LOOP
    IF jsonb_typeof(p->f) IS DISTINCT FROM 'number' OR (p->>f) !~ '^[0-9]+$' THEN RETURN false; END IF;
    n:=(p->>f)::numeric;
    IF n<1 OR n>(CASE f WHEN 'expectedEmployeeVersion' THEN 9007199254740991 WHEN 'plannedDeclaredBatchCount' THEN 9999 ELSE 2 END) THEN RETURN false; END IF;
  END LOOP;
  IF k='withdraw' AND (jsonb_typeof(p->'reason') IS DISTINCT FROM 'string' OR length(p->>'reason') NOT BETWEEN 1 AND 500 OR (p->>'reason')<>btrim(p->>'reason') OR (p->>'reason')~'[[:cntrl:]]') THEN RETURN false; END IF;
  IF k='start' THEN
    IF jsonb_typeof(r->'batch') IS DISTINCT FROM 'object' OR (SELECT count(*) FROM jsonb_object_keys(r))<>3 THEN RETURN false; END IF;
  ELSIF (SELECT count(*) FROM jsonb_object_keys(r))<>2 THEN RETURN false;
  END IF;
  RETURN true;
END $$;
CREATE TABLE {{schema}}.production_preparation_assignment_commands (
  company_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  location_id uuid NOT NULL,
  assignment_id uuid NOT NULL,
  actor_id uuid NOT NULL,
  kind text NOT NULL CHECK(kind IN('create','withdraw','start')),
  payload jsonb NOT NULL,
  result jsonb NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(company_id,operation_id),
  UNIQUE(company_id,operation_id,assignment_id,location_id,actor_id,kind),
  FOREIGN KEY(company_id,assignment_id,location_id) REFERENCES {{schema}}.production_preparation_assignments(company_id,id,location_id),
  FOREIGN KEY(actor_id,company_id,location_id) REFERENCES {{schema}}.accounts(id,company_id,location_id),
  CHECK(octet_length(payload::text)<=16384 AND octet_length(result::text)<=32768 AND {{schema}}.preparation_assignment_command_shape(kind,payload,result) IS TRUE),
  CHECK((payload->>'operationId'=operation_id::text) IS TRUE)
);
ALTER TABLE {{schema}}.production_preparation_assignments ADD CONSTRAINT preparation_assignment_create_receipt
 FOREIGN KEY(company_id,create_operation_id,id,location_id,created_by,create_kind)
 REFERENCES {{schema}}.production_preparation_assignment_commands(company_id,operation_id,assignment_id,location_id,actor_id,kind) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE {{schema}}.production_preparation_assignments ADD CONSTRAINT preparation_assignment_terminal_receipt
 FOREIGN KEY(company_id,terminal_operation_id,id,location_id,terminal_actor,terminal_kind)
 REFERENCES {{schema}}.production_preparation_assignment_commands(company_id,operation_id,assignment_id,location_id,actor_id,kind) DEFERRABLE INITIALLY DEFERRED;

CREATE FUNCTION {{schema}}.preparation_assignment_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Assignment evidence retained' USING ERRCODE='23514'; END IF;
 IF TG_OP='INSERT' THEN
  IF NEW.status IS DISTINCT FROM 'assigned' OR NEW.version IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'Assignment must begin assigned' USING ERRCODE='23514'; END IF;
 ELSE
  IF OLD.status IS DISTINCT FROM 'assigned' OR NEW.status NOT IN('started','withdrawn') OR NEW.version IS DISTINCT FROM 2 OR
    (to_jsonb(NEW)-ARRAY['status','version','batch_id','batch_operation_id','started_by','started_at','withdrawn_by','withdrawn_at','withdrawal_reason','terminal_operation_id','terminal_actor','terminal_kind']) IS DISTINCT FROM
    (to_jsonb(OLD)-ARRAY['status','version','batch_id','batch_operation_id','started_by','started_at','withdrawn_by','withdrawn_at','withdrawal_reason','terminal_operation_id','terminal_actor','terminal_kind'])
  THEN RAISE EXCEPTION 'Immutable assignment selection or terminal evidence' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER preparation_assignment_guard BEFORE INSERT OR UPDATE OR DELETE ON {{schema}}.production_preparation_assignments FOR EACH ROW EXECUTE FUNCTION {{schema}}.preparation_assignment_guard();
CREATE TRIGGER preparation_assignment_command_immutable BEFORE UPDATE OR DELETE ON {{schema}}.production_preparation_assignment_commands FOR EACH ROW EXECUTE FUNCTION {{schema}}.preparation_evidence_immutable();

-- Read the final aggregate for deferred checks, including create+start in one Tx.
CREATE FUNCTION {{schema}}.preparation_assignment_integrity() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE a {{schema}}.production_preparation_assignments%ROWTYPE; c {{schema}}.production_preparation_assignment_commands%ROWTYPE;
 b {{schema}}.production_preparation_batches%ROWTYPE; receipt {{schema}}.production_preparation_batch_commands%ROWTYPE; opening jsonb; j jsonb; initial jsonb;
BEGIN
 SELECT * INTO a FROM {{schema}}.production_preparation_assignments WHERE company_id=NEW.company_id AND id=(to_jsonb(NEW)->>CASE WHEN TG_TABLE_NAME='production_preparation_assignments' THEN 'id' ELSE 'assignment_id' END)::uuid;
 -- Build the public evidence with exact camelCase names and UTC instants.
 j:=jsonb_build_object('id',a.id,'companyId',a.company_id,'locationId',a.location_id,'employeeId',a.employee_id,'recipeId',a.recipe_id,'revisionId',a.revision_id,
   'plannedDeclaredBatchCount',a.planned_declared_batch_count,'createdBy',a.created_by,'createdAt',to_char(a.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'createOperationId',a.create_operation_id,'status',a.status,'version',a.version,'batchId',a.batch_id,'batchOperationId',a.batch_operation_id,'startedBy',a.started_by,
   'startedAt',CASE WHEN a.started_at IS NOT NULL THEN to_char(a.started_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END,'withdrawnBy',a.withdrawn_by,
   'withdrawnAt',CASE WHEN a.withdrawn_at IS NOT NULL THEN to_char(a.withdrawn_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END,'withdrawalReason',a.withdrawal_reason,'terminalOperationId',a.terminal_operation_id);
 initial:=j||jsonb_build_object('status','assigned','version',1,'batchId',NULL,'batchOperationId',NULL,'startedBy',NULL,'startedAt',NULL,'withdrawnBy',NULL,'withdrawnAt',NULL,'withdrawalReason',NULL,'terminalOperationId',NULL);
 SELECT * INTO c FROM {{schema}}.production_preparation_assignment_commands WHERE company_id=a.company_id AND operation_id=a.create_operation_id;
 IF NOT FOUND OR c.payload->>'id' IS DISTINCT FROM a.id::text OR c.payload->>'employeeId' IS DISTINCT FROM a.employee_id::text OR
  c.payload->>'recipeId' IS DISTINCT FROM a.recipe_id::text OR c.payload->>'revisionId' IS DISTINCT FROM a.revision_id::text OR
  c.payload->'plannedDeclaredBatchCount' IS DISTINCT FROM to_jsonb(a.planned_declared_batch_count) OR c.result->'assignment' IS DISTINCT FROM initial
 THEN RAISE EXCEPTION 'Invalid assignment creation receipt' USING ERRCODE='23514'; END IF;
 IF a.status<>'assigned' THEN
  SELECT * INTO c FROM {{schema}}.production_preparation_assignment_commands WHERE company_id=a.company_id AND operation_id=a.terminal_operation_id;
  IF NOT FOUND OR c.payload->'expectedVersion' IS DISTINCT FROM '1'::jsonb OR c.result->'assignment' IS DISTINCT FROM j THEN RAISE EXCEPTION 'Invalid assignment terminal receipt' USING ERRCODE='23514'; END IF;
  IF a.status='withdrawn' AND c.payload->>'reason' IS DISTINCT FROM a.withdrawal_reason THEN RAISE EXCEPTION 'Invalid withdrawal receipt' USING ERRCODE='23514'; END IF;
 END IF;
 IF a.status='started' THEN
  SELECT * INTO b FROM {{schema}}.production_preparation_batches WHERE company_id=a.company_id AND id=a.batch_id;
  SELECT * INTO receipt FROM {{schema}}.production_preparation_batch_commands WHERE company_id=a.company_id AND operation_id=a.batch_operation_id;
  opening:=receipt.result->'batch';
  IF b.opened_by IS DISTINCT FROM a.started_by OR b.opened_at IS DISTINCT FROM a.started_at OR b.open_operation_id IS DISTINCT FROM a.batch_operation_id OR
   receipt.payload IS DISTINCT FROM jsonb_build_object('batchId',a.batch_id,'operationId',a.batch_operation_id,'recipeId',a.recipe_id,'revisionId',a.revision_id,'plannedDeclaredBatchCount',a.planned_declared_batch_count) OR
   receipt.result->'replayed' IS DISTINCT FROM 'false'::jsonb OR
   opening IS NULL OR c.result->'batch' IS DISTINCT FROM opening OR opening->>'batchId' IS DISTINCT FROM b.id::text OR opening->>'status' IS DISTINCT FROM 'open' OR
   opening->>'companyId' IS DISTINCT FROM a.company_id::text OR opening->>'locationId' IS DISTINCT FROM a.location_id::text OR opening->>'employeeId' IS DISTINCT FROM a.employee_id::text OR
   opening->>'recipeId' IS DISTINCT FROM a.recipe_id::text OR opening->>'revisionId' IS DISTINCT FROM a.revision_id::text OR opening->>'openedBy' IS DISTINCT FROM a.started_by::text OR
   opening->>'openOperationId' IS DISTINCT FROM a.batch_operation_id::text OR (opening->>'openedAt')::timestamptz IS DISTINCT FROM a.started_at OR opening->'version' IS DISTINCT FROM '1'::jsonb OR
   (SELECT count(*) FROM jsonb_object_keys(opening))<>21 OR
   NOT (opening ?& ARRAY['actualDeclaredBatchCount','completedBy','completedAt','cancelledBy','cancelledAt','cancellationReason','terminalOperationId','terminalKind','completionNote']) OR
   EXISTS(SELECT 1 FROM jsonb_each(opening) e WHERE e.key=ANY(ARRAY['actualDeclaredBatchCount','completedBy','completedAt','cancelledBy','cancelledAt','cancellationReason','terminalOperationId','terminalKind','completionNote']) AND e.value IS DISTINCT FROM 'null'::jsonb) OR
   opening->'plannedDeclaredBatchCount' IS DISTINCT FROM to_jsonb(a.planned_declared_batch_count)
  THEN RAISE EXCEPTION 'Invalid assigned Batch opening evidence' USING ERRCODE='23514'; END IF;
 END IF;
 IF TG_TABLE_NAME='production_preparation_assignment_commands' AND (to_jsonb(NEW)->>'operation_id') IS DISTINCT FROM a.create_operation_id::text AND (to_jsonb(NEW)->>'operation_id') IS DISTINCT FROM a.terminal_operation_id::text THEN
  RAISE EXCEPTION 'Unassociated assignment receipt' USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER preparation_assignment_integrity AFTER INSERT OR UPDATE ON {{schema}}.production_preparation_assignments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.preparation_assignment_integrity();
CREATE CONSTRAINT TRIGGER preparation_assignment_receipt_integrity AFTER INSERT ON {{schema}}.production_preparation_assignment_commands DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.preparation_assignment_integrity();
