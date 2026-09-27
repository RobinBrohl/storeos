-- Keep historical audit correlation unknown. Defaults apply only to new rows.
ALTER TABLE {{schema}}.audit_entries ADD COLUMN correlation_id uuid;
ALTER TABLE {{schema}}.audit_entries ALTER COLUMN correlation_id SET DEFAULT gen_random_uuid();
CREATE INDEX audit_entries_correlation_idx ON {{schema}}.audit_entries (company_id, correlation_id);

ALTER TABLE {{schema}}.accounts DROP CONSTRAINT accounts_role_valid;
ALTER TABLE {{schema}}.accounts ADD CONSTRAINT accounts_role_valid
  CHECK (role IN ('admin', 'auditor', 'viewer', 'employee'));
ALTER TABLE {{schema}}.accounts ADD CONSTRAINT accounts_scope_unique
  UNIQUE (id, company_id, location_id);

-- Owned by people. One fixed, initially open-ended location assignment.
CREATE TABLE {{schema}}.employees (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  display_name text NOT NULL CHECK (
    length(display_name) BETWEEN 1 AND 120 AND display_name = btrim(display_name)
    AND display_name !~ '[[:cntrl:]]'
  ),
  is_active boolean NOT NULL DEFAULT true,
  version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  assigned_from timestamptz NOT NULL DEFAULT clock_timestamp(),
  assigned_until timestamptz,
  CONSTRAINT employees_scope_unique UNIQUE (id, company_id, location_id),
  CONSTRAINT employees_location_fk FOREIGN KEY (location_id, company_id)
    REFERENCES {{schema}}.locations(id, company_id) ON DELETE RESTRICT,
  CONSTRAINT employees_assignment_valid CHECK (
    (is_active AND assigned_until IS NULL) OR
    (NOT is_active AND assigned_until IS NOT NULL AND assigned_until >= assigned_from)
  )
);
CREATE INDEX employees_company_idx ON {{schema}}.employees (company_id, id);

-- Owned by identity; historical links survive revocation.
CREATE TABLE {{schema}}.account_employee_links (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
  linked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_at timestamptz,
  CONSTRAINT employee_links_account_fk FOREIGN KEY (account_id, company_id, location_id)
    REFERENCES {{schema}}.accounts(id, company_id, location_id) ON DELETE RESTRICT,
  CONSTRAINT employee_links_employee_fk FOREIGN KEY (employee_id, company_id, location_id)
    REFERENCES {{schema}}.employees(id, company_id, location_id) ON DELETE RESTRICT,
  CONSTRAINT employee_links_time_valid CHECK (revoked_at IS NULL OR revoked_at >= linked_at)
);
CREATE UNIQUE INDEX employee_links_active_account_idx ON {{schema}}.account_employee_links (account_id)
  WHERE revoked_at IS NULL;
CREATE UNIQUE INDEX employee_links_active_employee_idx ON {{schema}}.account_employee_links (employee_id)
  WHERE revoked_at IS NULL;
