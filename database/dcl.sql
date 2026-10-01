-- Hak akses database untuk role aplikasi.
-- Jalankan sebagai user postgres atau pemilik database.

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'esport_app') THEN
        CREATE ROLE esport_app LOGIN PASSWORD 'esport_app_password';
    END IF;
END
$$;

GRANT CONNECT ON DATABASE "TOURNAMEN_ESPORT" TO esport_app;
GRANT USAGE ON SCHEMA public TO esport_app;

GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA public
TO esport_app;

GRANT USAGE, SELECT, UPDATE
ON ALL SEQUENCES IN SCHEMA public
TO esport_app;

GRANT EXECUTE
ON ALL ROUTINES IN SCHEMA public
TO esport_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO esport_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO esport_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT EXECUTE ON ROUTINES TO esport_app;