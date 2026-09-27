CREATE TABLE {{schema}}.audit_entries (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  actor_kind text NOT NULL CHECK (actor_kind IN ('user', 'plugin', 'system')),
  actor_id text NOT NULL CHECK (length(actor_id) BETWEEN 1 AND 128),
  company_id uuid NOT NULL REFERENCES {{schema}}.companies(id) ON DELETE RESTRICT,
  location_id uuid REFERENCES {{schema}}.locations(id) ON DELETE RESTRICT,
  action text NOT NULL CHECK (length(action) BETWEEN 1 AND 96),
  entity_type text NOT NULL CHECK (length(entity_type) BETWEEN 1 AND 64),
  entity_id text NOT NULL CHECK (length(entity_id) BETWEEN 1 AND 128),
  changes jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT audit_changes_object CHECK (
    jsonb_typeof(changes) = 'object' AND octet_length(changes::text) <= 4096
  )
);

CREATE INDEX audit_entries_company_cursor_idx
  ON {{schema}}.audit_entries (company_id, id DESC);

-- This records the P0 bootstrap account's P1 role migration. It does not
-- pretend that the original P0 account creation was audited retroactively.
INSERT INTO {{schema}}.audit_entries
  (actor_kind, actor_id, company_id, location_id, action,
   entity_type, entity_id, changes)
SELECT 'system', 'migration:0003', a.company_id, a.location_id,
       'identity.bootstrap_admin_migrated', 'user', a.id::text,
       jsonb_build_object('role', 'admin')
FROM {{schema}}.bootstrap_state b
JOIN {{schema}}.accounts a ON a.id = b.account_id
WHERE a.role = 'admin';

CREATE TABLE {{schema}}.platform_node (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO {{schema}}.platform_node (singleton) VALUES (true);

CREATE TABLE {{schema}}.event_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL CHECK (length(type) BETWEEN 1 AND 96),
  schema_version integer NOT NULL DEFAULT 1 CHECK (schema_version = 1),
  aggregate_type text NOT NULL CHECK (aggregate_type IN ('company', 'location')),
  aggregate_id uuid NOT NULL,
  aggregate_version bigint NOT NULL CHECK (aggregate_version > 0),
  company_id uuid NOT NULL REFERENCES {{schema}}.companies(id) ON DELETE RESTRICT,
  location_id uuid REFERENCES {{schema}}.locations(id) ON DELETE RESTRICT,
  origin_node_id uuid NOT NULL REFERENCES {{schema}}.platform_node(id) ON DELETE RESTRICT,
  actor_id text NOT NULL CHECK (length(actor_id) BETWEEN 1 AND 128),
  correlation_id uuid NOT NULL DEFAULT gen_random_uuid(),
  causation_id uuid,
  payload jsonb NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'dispatched', 'dead_letter')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  last_error text,
  dispatched_at timestamptz,
  CONSTRAINT event_payload_object CHECK (
    jsonb_typeof(payload) = 'object' AND octet_length(payload::text) <= 8192
  )
);

CREATE INDEX event_outbox_pending_idx
  ON {{schema}}.event_outbox (next_attempt_at, recorded_at, id)
  WHERE status = 'pending';
CREATE INDEX event_outbox_company_cursor_idx
  ON {{schema}}.event_outbox (company_id, recorded_at DESC, id DESC);

CREATE TABLE {{schema}}.event_receipts (
  event_id uuid NOT NULL REFERENCES {{schema}}.event_outbox(id) ON DELETE RESTRICT,
  consumer text NOT NULL CHECK (consumer = 'plugin_inbox'),
  processed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (event_id, consumer)
);

CREATE TABLE {{schema}}.plugin_registrations (
  id text PRIMARY KEY CHECK (id ~ '^[a-z][a-z0-9._-]{2,63}$'),
  company_id uuid NOT NULL REFERENCES {{schema}}.companies(id) ON DELETE RESTRICT,
  manifest jsonb NOT NULL CHECK (jsonb_typeof(manifest) = 'object'),
  status text NOT NULL DEFAULT 'registered'
    CHECK (status IN ('registered', 'approved', 'disabled')),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  location_id uuid REFERENCES {{schema}}.locations(id) ON DELETE RESTRICT,
  permissions text[] NOT NULL DEFAULT '{}',
  subscriptions text[] NOT NULL DEFAULT '{}',
  approved_at timestamptz,
  disabled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT plugin_approval_scope CHECK (
    status <> 'approved' OR (location_id IS NOT NULL AND approved_at IS NOT NULL)
  )
);

CREATE INDEX plugin_registrations_company_idx
  ON {{schema}}.plugin_registrations (company_id, id);

CREATE TABLE {{schema}}.plugin_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plugin_id text NOT NULL REFERENCES {{schema}}.plugin_registrations(id) ON DELETE RESTRICT,
  token_hash char(64) NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  CONSTRAINT plugin_token_expiry CHECK (expires_at > created_at)
);

CREATE UNIQUE INDEX plugin_tokens_one_unrevoked_idx
  ON {{schema}}.plugin_tokens (plugin_id) WHERE revoked_at IS NULL;

CREATE TABLE {{schema}}.plugin_inbox (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  plugin_id text NOT NULL REFERENCES {{schema}}.plugin_registrations(id) ON DELETE RESTRICT,
  event_id uuid NOT NULL REFERENCES {{schema}}.event_outbox(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'acknowledged', 'revoked')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  acknowledged_at timestamptz,
  UNIQUE (plugin_id, event_id)
);

CREATE INDEX plugin_inbox_plugin_cursor_idx
  ON {{schema}}.plugin_inbox (plugin_id, id) WHERE status = 'pending';
