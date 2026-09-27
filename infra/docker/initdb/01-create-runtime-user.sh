#!/bin/sh
set -eu

# This runs only when PostgreSQL initializes an empty data volume. The
# PostgreSQL image creates POSTGRES_USER as owner before invoking this script.
runtime_password="$(cat /run/secrets/db_password)"
if [ -z "$runtime_password" ]; then
  echo 'Runtime database password is empty.' >&2
  exit 1
fi

# psql's :'variable' quotes the value as an SQL literal. The password reaches
# psql via stdin rather than a command-line argument or an interpolated SQL
# string. Setup generates an ASCII Base64 password without whitespace.
{
  printf '\\set runtime_password %s\n' "$runtime_password"
  printf '\\set database_name %s\n' "$POSTGRES_DB"
  cat <<'SQL'
CREATE ROLE storeos LOGIN PASSWORD :'runtime_password';
GRANT CONNECT ON DATABASE :"database_name" TO storeos;
SQL
} | psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -v ON_ERROR_STOP=1

unset runtime_password
