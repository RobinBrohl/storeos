CREATE TABLE {{schema}}.accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  username text NOT NULL,
  username_key text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT accounts_username_length CHECK (length(username) BETWEEN 3 AND 64)
);

CREATE TABLE {{schema}}.auth_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  token_hash char(64) NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  CONSTRAINT auth_sessions_expiry CHECK (expires_at > created_at)
);

CREATE INDEX auth_sessions_account_active_idx
  ON {{schema}}.auth_sessions (account_id, expires_at)
  WHERE revoked_at IS NULL;

CREATE TABLE {{schema}}.bootstrap_state (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  account_id uuid NOT NULL REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  completed_at timestamptz NOT NULL DEFAULT now()
);
