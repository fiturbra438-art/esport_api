-- ============================================================================
-- DCL (Data Control Language) - Hak Akses Role Database TOURNAMEN_ESPORT
-- Jalankan file ini sebagai pemilik database (user postgres).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Pembuatan Role (jika belum dibuat)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'esport_app') THEN
        CREATE ROLE esport_app LOGIN PASSWORD 'esport_app_password';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'admin') THEN
        CREATE ROLE admin LOGIN PASSWORD 'admin_password';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'user') THEN
        EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', 'user', 'user_password');
    END IF;
END
$$;

-- ----------------------------------------------------------------------------
-- 1. Hak Akses Role Aplikasi (esport_app)
-- Digunakan oleh backend API (Axum) untuk runtime database connection.
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- 2. Hak Akses Role Administrator (admin)
-- Hanya diberikan hak eksekusi (GRANT EXECUTE) untuk seluruh prosedur dan fungsi.
-- Tidak diberikan akses langsung (SELECT/INSERT/UPDATE/DELETE) pada tabel.
-- ----------------------------------------------------------------------------
GRANT CONNECT ON DATABASE "TOURNAMEN_ESPORT" TO admin;
GRANT USAGE ON SCHEMA public TO admin;

-- Hak eksekusi seluruh rutin (prosedur & fungsi) di skema public
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO admin;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT EXECUTE ON ROUTINES TO admin;

-- ----------------------------------------------------------------------------
-- 3. Hak Akses Role Pengguna Biasa ("user")
-- Hanya diberikan hak eksekusi (GRANT EXECUTE) pada prosedur dan fungsi
-- operasional pemain (registrasi, manajemen tim, profil, dan pendaftaran turnamen).
-- Tidak memiliki hak eksekusi pada prosedur admin (turnamen & jadwal/hasil match),
-- serta tidak memiliki akses langsung pada tabel.
-- ----------------------------------------------------------------------------
GRANT CONNECT ON DATABASE "TOURNAMEN_ESPORT" TO "user";
GRANT USAGE ON SCHEMA public TO "user";

-- Prosedur Akun & Pengguna
GRANT EXECUTE ON PROCEDURE pr_register_user TO "user";
GRANT EXECUTE ON PROCEDURE pr_update_username TO "user";
GRANT EXECUTE ON PROCEDURE pr_delete_user TO "user";

-- Prosedur Manajemen Tim & Pendaftaran Turnamen
GRANT EXECUTE ON PROCEDURE pr_create_team TO "user";
GRANT EXECUTE ON PROCEDURE pr_add_team_member TO "user";
GRANT EXECUTE ON PROCEDURE pr_remove_team_member TO "user";
GRANT EXECUTE ON PROCEDURE pr_transfer_captain TO "user";
GRANT EXECUTE ON PROCEDURE pr_leave_team TO "user";
GRANT EXECUTE ON PROCEDURE pr_delete_team TO "user";
GRANT EXECUTE ON PROCEDURE pr_register_team_to_tournament TO "user";

-- Prosedur Lookup
GRANT EXECUTE ON PROCEDURE pr_get_user_id_by_username TO "user";
GRANT EXECUTE ON PROCEDURE pr_get_team_id_by_name TO "user";
GRANT EXECUTE ON PROCEDURE pr_get_tournament_id_by_name TO "user";

-- Fungsi Pendukung / Lookup yang dipanggil prosedur di atas
GRANT EXECUTE ON FUNCTION fn_user_id_by_username TO "user";
GRANT EXECUTE ON FUNCTION fn_team_id_by_name TO "user";
GRANT EXECUTE ON FUNCTION fn_tournament_id_by_name TO "user";
GRANT EXECUTE ON FUNCTION fn_register_user TO "user";
GRANT EXECUTE ON FUNCTION fn_create_team TO "user";
GRANT EXECUTE ON FUNCTION fn_add_team_member TO "user";
GRANT EXECUTE ON FUNCTION fn_remove_team_member TO "user";
GRANT EXECUTE ON FUNCTION fn_transfer_captain TO "user";
GRANT EXECUTE ON FUNCTION fn_register_team_to_tournament TO "user";