-- ============================================================================
-- DCL (Data Control Language) - Hak Akses Role Database TOURNAMEN_ESPORT
-- Model: Hierarki Role Berjenjang (Role Inheritance) & Least Privilege
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
        CREATE ROLE admin LOGIN PASSWORD 'admin_password' INHERIT;
    ELSE
        ALTER ROLE admin INHERIT;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'user') THEN
        EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L INHERIT', 'user', 'user_password');
    ELSE
        ALTER ROLE "user" INHERIT;
    END IF;
END
$$;

-- ----------------------------------------------------------------------------
-- 1. Hak Akses Role Aplikasi (esport_app)
-- Digunakan oleh backend API (Axum) untuk runtime database connection pool.
-- Prinsip Zero-Trust: esport_app hanya boleh membaca tabel/view secara langsung
-- dan mengeksekusi routines. Seluruh mutasi data (INSERT/UPDATE/DELETE) WAJIB
-- melalui Stored Procedure, bukan query langsung ke tabel fisik.
-- ----------------------------------------------------------------------------
GRANT CONNECT ON DATABASE "TOURNAMEN_ESPORT" TO esport_app;
GRANT USAGE ON SCHEMA public TO esport_app;

-- Hak baca langsung pada tabel & view (untuk VIEW queries dari backend)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO esport_app;

GRANT USAGE, SELECT
ON ALL SEQUENCES IN SCHEMA public
TO esport_app;

-- Hak eksekusi seluruh prosedur & fungsi
GRANT EXECUTE
ON ALL ROUTINES IN SCHEMA public
TO esport_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO esport_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE, SELECT ON SEQUENCES TO esport_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT EXECUTE ON ROUTINES TO esport_app;

-- ----------------------------------------------------------------------------
-- 2. Hak Akses Role Pengguna Biasa ("user") - Tingkat Dasar
-- Pengguna biasa dapat membaca VIEW publik dan mengeksekusi prosedur operasional
-- pemain (registrasi, manajemen tim, profil, pendaftaran turnamen).
-- Tidak memiliki akses langsung ke tabel fisik.
-- ----------------------------------------------------------------------------
GRANT CONNECT ON DATABASE "TOURNAMEN_ESPORT" TO "user";
GRANT USAGE ON SCHEMA public TO "user";

-- Hak Baca View (Read-Only)
GRANT SELECT ON vw_tournaments TO "user";
GRANT SELECT ON vw_team_members TO "user";
GRANT SELECT ON vw_teams TO "user";
GRANT SELECT ON vw_tournament_teams TO "user";
GRANT SELECT ON vw_match_schedule TO "user";

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

-- Fungsi Pendukung yang dipanggil prosedur pemain
GRANT EXECUTE ON FUNCTION fn_user_id_by_username TO "user";
GRANT EXECUTE ON FUNCTION fn_team_id_by_name TO "user";
GRANT EXECUTE ON FUNCTION fn_tournament_id_by_name TO "user";
GRANT EXECUTE ON FUNCTION fn_register_user TO "user";
GRANT EXECUTE ON FUNCTION fn_create_team TO "user";
GRANT EXECUTE ON FUNCTION fn_add_team_member TO "user";
GRANT EXECUTE ON FUNCTION fn_remove_team_member TO "user";
GRANT EXECUTE ON FUNCTION fn_transfer_captain TO "user";
GRANT EXECUTE ON FUNCTION fn_register_team_to_tournament TO "user";

-- ----------------------------------------------------------------------------
-- 3. Hak Akses Role Administrator (admin) - Tingkat Lanjutan
-- Menerapkan hierarki (Role Inheritance):
-- Role "admin" mewarisi role "user", sehingga otomatis memperoleh seluruh hak
-- baca VIEW dan prosedur operasional pemain tanpa perlu didefinisikan ulang.
-- Ditambahkan hak eksekusi prosedur & fungsi khusus manajemen turnamen & match.
-- ----------------------------------------------------------------------------
GRANT CONNECT ON DATABASE "TOURNAMEN_ESPORT" TO admin;
GRANT USAGE ON SCHEMA public TO admin;

-- Pewarisan Role: admin mewarisi seluruh hak akses "user"
GRANT "user" TO admin;

-- Prosedur Khusus Administrator (Manajemen Turnamen & Pertandingan)
GRANT EXECUTE ON PROCEDURE pr_create_tournament TO admin;
GRANT EXECUTE ON PROCEDURE pr_delete_tournament TO admin;
GRANT EXECUTE ON PROCEDURE pr_create_match TO admin;
GRANT EXECUTE ON PROCEDURE pr_update_match_schedule TO admin;
GRANT EXECUTE ON PROCEDURE pr_get_match_id_by_tournament_and_team TO admin;
GRANT EXECUTE ON PROCEDURE pr_set_match_result TO admin;

-- Fungsi Pendukung Khusus Administrator
GRANT EXECUTE ON FUNCTION fn_create_tournament TO admin;
GRANT EXECUTE ON FUNCTION fn_delete_tournament TO admin;
GRANT EXECUTE ON FUNCTION fn_create_match TO admin;
GRANT EXECUTE ON FUNCTION fn_update_match_schedule TO admin;

-- ----------------------------------------------------------------------------
-- 4. Hak Akses Procedure READ (baca data) — berlaku untuk semua role
-- Procedure ini menggantikan query SELECT langsung dari backend.
-- ----------------------------------------------------------------------------

-- Procedure baca yang bisa diakses user biasa
GRANT EXECUTE ON PROCEDURE pr_login(TEXT) TO "user";
GRANT EXECUTE ON PROCEDURE pr_get_user_profile(INTEGER) TO "user";
GRANT EXECUTE ON PROCEDURE pr_get_teams(REFCURSOR) TO "user";
GRANT EXECUTE ON PROCEDURE pr_get_team_profile(INTEGER, REFCURSOR, REFCURSOR) TO "user";
GRANT EXECUTE ON PROCEDURE pr_get_tournaments(REFCURSOR) TO "user";
GRANT EXECUTE ON PROCEDURE pr_get_tournament_teams(INTEGER, REFCURSOR) TO "user";
GRANT EXECUTE ON PROCEDURE pr_get_tournament_matches(INTEGER, REFCURSOR) TO "user";

-- admin mewarisi semua hak "user" di atas melalui: GRANT "user" TO admin;