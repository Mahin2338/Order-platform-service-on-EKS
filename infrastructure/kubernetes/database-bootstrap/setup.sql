-- The apps currently share tables and run CREATE TABLE/INDEX at startup.
-- This role can manage application objects, but cannot administer PostgreSQL.
\set ON_ERROR_STOP on
\set ECHO none
\set VERBOSITY terse
\getenv app_password APP_PASSWORD
BEGIN;
SELECT pg_advisory_xact_lock(91827461);
SELECT 'CREATE ROLE ordersapp LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'ordersapp')
\gexec
ALTER ROLE ordersapp LOGIN NOCREATEDB NOCREATEROLE PASSWORD :'app_password';
GRANT CONNECT ON DATABASE orders TO ordersapp;
GRANT USAGE, CREATE ON SCHEMA public TO ordersapp;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ordersapp;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ordersapp;
-- Covers objects subsequently created by the administrator as well.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ordersapp;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO ordersapp;
COMMIT;
