#!/bin/bash
# 首次初始化 Postgres 数据目录时创建 company_auth 并导入主 schema
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" <<-'EOSQL'
  SELECT 'CREATE DATABASE company_auth'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'company_auth')\gexec
EOSQL

psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname company_auth \
  -f /schema/schema-company-auth.sql

if [ -f /schema/schema-company-manage-security.sql ]; then
  psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname company_auth \
    -f /schema/schema-company-manage-security.sql
fi

echo "company_auth schema initialized"
