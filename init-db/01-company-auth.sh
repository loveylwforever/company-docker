#!/bin/bash
# 首次初始化 Postgres 数据目录时创建 company_auth 并导入完整 schema
set -euo pipefail

INIT_SQL="/schema/schema-company-auth-init-all.sql"

psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" <<-'EOSQL'
  SELECT 'CREATE DATABASE company_auth'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'company_auth')\gexec
EOSQL

if [ ! -f "${INIT_SQL}" ]; then
  echo "ERROR: missing ${INIT_SQL}" >&2
  exit 1
fi

psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname company_auth \
  -f "${INIT_SQL}"

echo "company_auth schema initialized (schema-company-auth-init-all.sql)"
