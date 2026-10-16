-- ============================================================================
-- Migration 0008: Read Procedures (Procedure untuk operasi SELECT)
-- Semua operasi baca data kini melalui procedure, bukan query langsung ke view.
-- Backend cukup memanggil CALL pr_* tanpa menulis SQL SELECT sama sekali.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- [1] pr_get_user_profile: Ambil profil user berdasarkan ID.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS pr_get_user_profile(INTEGER);
CREATE PROCEDURE pr_get_user_profile(
    IN  p_user_id   INTEGER,
    OUT id          INTEGER,
    OUT username    VARCHAR,
    OUT mmr_point   INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT u.id, u.username, u.mmr_point
    INTO id, username, mmr_point
    FROM users u
    WHERE u.id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Player tidak ditemukan'
            USING ERRCODE = 'P0002';
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- [2] pr_get_teams: Ambil seluruh daftar tim dari view vw_teams.
-- Menggunakan refcursor agar bisa mengembalikan banyak baris.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS pr_get_teams(REFCURSOR);
CREATE PROCEDURE pr_get_teams(
    IN p_cursor REFCURSOR DEFAULT 'teams_cursor'
)
LANGUAGE plpgsql
AS $$
BEGIN
    OPEN p_cursor FOR
        SELECT id, name, captain_id, captain_username, member_count
        FROM vw_teams
        ORDER BY name, id;
END;
$$;

-- ----------------------------------------------------------------------------
-- [3] pr_get_team_profile: Ambil profil tim + anggota berdasarkan ID.
-- Dua cursor: satu untuk info tim, satu untuk daftar anggota.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS pr_get_team_profile(INTEGER, REFCURSOR, REFCURSOR);
CREATE PROCEDURE pr_get_team_profile(
    IN  p_team_id       INTEGER,
    IN  p_team_cursor   REFCURSOR DEFAULT 'team_cursor',
    IN  p_member_cursor REFCURSOR DEFAULT 'member_cursor'
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM teams WHERE id = p_team_id) THEN
        RAISE EXCEPTION 'Tim tidak ditemukan'
            USING ERRCODE = 'P0002';
    END IF;

    OPEN p_team_cursor FOR
        SELECT team_id AS id, team_name AS name, captain_id
        FROM vw_team_members
        WHERE team_id = p_team_id
        LIMIT 1;

    OPEN p_member_cursor FOR
        SELECT username, status
        FROM vw_team_members
        WHERE team_id = p_team_id AND user_id IS NOT NULL;
END;
$$;

-- ----------------------------------------------------------------------------
-- [4] pr_get_tournaments: Ambil seluruh daftar turnamen.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS pr_get_tournaments(REFCURSOR);
CREATE PROCEDURE pr_get_tournaments(
    IN p_cursor REFCURSOR DEFAULT 'tournaments_cursor'
)
LANGUAGE plpgsql
AS $$
BEGIN
    OPEN p_cursor FOR
        SELECT id, name, status, total_slots, available_slots
        FROM vw_tournaments;
END;
$$;

-- ----------------------------------------------------------------------------
-- [5] pr_get_tournament_teams: Ambil tim yang terdaftar di turnamen tertentu.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS pr_get_tournament_teams(INTEGER, REFCURSOR);
CREATE PROCEDURE pr_get_tournament_teams(
    IN  p_tournament_id INTEGER,
    IN  p_cursor        REFCURSOR DEFAULT 'tournament_teams_cursor'
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM tournaments WHERE id = p_tournament_id) THEN
        RAISE EXCEPTION 'Turnamen tidak ditemukan'
            USING ERRCODE = 'P0002';
    END IF;

    OPEN p_cursor FOR
        SELECT team_id, team_name, captain_id, captain_username,
               registered_at::TEXT AS registered_at
        FROM vw_tournament_teams
        WHERE tournament_id = p_tournament_id
        ORDER BY registered_at, team_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- [6] pr_get_tournament_matches: Ambil jadwal pertandingan di turnamen tertentu.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS pr_get_tournament_matches(INTEGER, REFCURSOR);
CREATE PROCEDURE pr_get_tournament_matches(
    IN  p_tournament_id INTEGER,
    IN  p_cursor        REFCURSOR DEFAULT 'matches_cursor'
)
LANGUAGE plpgsql
AS $$
BEGIN
    OPEN p_cursor FOR
        SELECT id, round_number, team1_name, team2_name,
               schedule_time::TEXT AS schedule_time, status, winner_name
        FROM vw_match_schedule
        WHERE tournament_id = p_tournament_id
        ORDER BY round_number ASC, id ASC;
END;
$$;

-- ----------------------------------------------------------------------------
-- [7] pr_login: Ambil data akun untuk proses login.
-- Verifikasi password hash tetap dilakukan di sisi aplikasi (Argon2).
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS pr_login(TEXT);
CREATE PROCEDURE pr_login(
    IN  p_username  TEXT,
    OUT id          INTEGER,
    OUT username    VARCHAR,
    OUT password    VARCHAR,
    OUT role        VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT u.id, u.username, u.password, u.role
    INTO id, username, password, role
    FROM users u
    WHERE u.username = p_username;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Username atau password salah'
            USING ERRCODE = 'P0002';
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- Berikan EXECUTE pada role aplikasi untuk procedure baru ini.
-- ----------------------------------------------------------------------------
GRANT EXECUTE ON PROCEDURE pr_get_user_profile(INTEGER) TO esport_app;
GRANT EXECUTE ON PROCEDURE pr_get_teams(REFCURSOR) TO esport_app;
GRANT EXECUTE ON PROCEDURE pr_get_team_profile(INTEGER, REFCURSOR, REFCURSOR) TO esport_app;
GRANT EXECUTE ON PROCEDURE pr_get_tournaments(REFCURSOR) TO esport_app;
GRANT EXECUTE ON PROCEDURE pr_get_tournament_teams(INTEGER, REFCURSOR) TO esport_app;
GRANT EXECUTE ON PROCEDURE pr_get_tournament_matches(INTEGER, REFCURSOR) TO esport_app;
GRANT EXECUTE ON PROCEDURE pr_login(TEXT) TO esport_app;
