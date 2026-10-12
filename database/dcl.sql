-- Hak akses database untuk role aplikasi.
-- Buat role esport_app secara terpisah dengan password acak yang disimpan
-- di secret manager/environment, lalu jalankan file ini sebagai pemilik DB.

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