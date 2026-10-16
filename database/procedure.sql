-- Lookup wrappers
-- Mutating procedures commit explicitly and must be called outside an explicit
-- transaction block. PostgreSQL rolls back the CALL if an error occurs first.
CREATE PROCEDURE pr_get_user_id_by_username(
    IN p_username TEXT,
    OUT user_id INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    user_id := fn_user_id_by_username(p_username);
END;
$$;

CREATE PROCEDURE pr_get_team_id_by_name(
    IN p_team_name TEXT,
    OUT team_id INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    team_id := fn_team_id_by_name(p_team_name);
END;
$$;

CREATE PROCEDURE pr_get_tournament_id_by_name(
    IN p_tournament_name TEXT,
    OUT tournament_id INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    tournament_id := fn_tournament_id_by_name(p_tournament_name);
END;
$$;

-- Prosedur pengguna membungkus function registrasi pengguna.
CREATE PROCEDURE pr_register_user(
    IN p_username TEXT,
    IN p_password TEXT,
    IN p_mmr_point INTEGER,
    OUT id INTEGER,
    OUT username VARCHAR,
    OUT mmr_point INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT created_user.id, created_user.username, created_user.mmr_point
    INTO id, username, mmr_point
    FROM fn_register_user(p_username, p_password, p_mmr_point) AS created_user;
    COMMIT;
END;
$$;

-- Prosedur tim membungkus function operasi tim.
CREATE PROCEDURE pr_create_team(
    IN p_actor_id INTEGER,
    IN p_name TEXT,
    IN p_captain_username TEXT,
    OUT id INTEGER,
    OUT name VARCHAR,
    OUT captain_id INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_captain_id INTEGER;
BEGIN
    SELECT users.id
    INTO v_captain_id
    FROM users
    WHERE users.id = p_actor_id
      AND users.username = p_captain_username;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kapten tim harus merupakan pengguna yang sedang login'
            USING ERRCODE = '42501';
    END IF;

    SELECT created_team.id, created_team.name, created_team.captain_id
    INTO id, name, captain_id
    FROM fn_create_team(p_name, p_captain_username) AS created_team;
    COMMIT;
END;
$$;

DROP PROCEDURE IF EXISTS pr_add_team_member(INTEGER, TEXT, TEXT);
CREATE PROCEDURE pr_add_team_member(
    IN p_actor_id INTEGER,
    IN p_team_name TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_actor_id) THEN
        RAISE EXCEPTION 'Pengguna pada token tidak ditemukan'
            USING ERRCODE = '42501';
    END IF;

    IF NOT fn_add_team_member(
        fn_team_id_by_name(p_team_name),
        p_actor_id
    ) THEN
        RAISE EXCEPTION 'Pengguna sudah menjadi anggota tim "%"', p_team_name
            USING ERRCODE = '23505';
    END IF;
    COMMIT;
END;
$$;

CREATE PROCEDURE pr_remove_team_member(
    IN p_actor_id INTEGER,
    IN p_team_name TEXT,
    IN p_username TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_team_id INTEGER;
    v_captain_id INTEGER;
BEGIN
    SELECT teams.id, teams.captain_id
    INTO v_team_id, v_captain_id
    FROM teams
    WHERE teams.name = p_team_name
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tim "%" tidak ditemukan', p_team_name
            USING ERRCODE = 'P0002';
    END IF;

    IF v_captain_id IS DISTINCT FROM p_actor_id THEN
        RAISE EXCEPTION 'Hanya kapten tim yang dapat menghapus anggota'
            USING ERRCODE = '42501';
    END IF;

    IF NOT fn_remove_team_member(
        v_team_id,
        fn_user_id_by_username(p_username)
    ) THEN
        RAISE EXCEPTION 'Player "%" bukan anggota tim "%"', p_username, p_team_name;
    END IF;
    COMMIT;
END;
$$;

CREATE PROCEDURE pr_transfer_captain(
    IN p_actor_id INTEGER,
    IN p_team_name TEXT,
    IN p_new_captain_username TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_team_id INTEGER;
    v_captain_id INTEGER;
BEGIN
    SELECT teams.id, teams.captain_id
    INTO v_team_id, v_captain_id
    FROM teams
    WHERE teams.name = p_team_name
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tim "%" tidak ditemukan', p_team_name
            USING ERRCODE = 'P0002';
    END IF;

    IF v_captain_id IS DISTINCT FROM p_actor_id THEN
        RAISE EXCEPTION 'Hanya kapten tim yang dapat memindahkan jabatan kapten'
            USING ERRCODE = '42501';
    END IF;

    IF NOT fn_transfer_captain(
        v_team_id,
        fn_user_id_by_username(p_new_captain_username)
    ) THEN
        RAISE EXCEPTION
            'Player "%" belum menjadi anggota tim "%"',
            p_new_captain_username,
            p_team_name;
    END IF;
    COMMIT;
END;
$$;

-- Prosedur turnamen membungkus function operasi turnamen.
CREATE PROCEDURE pr_create_tournament(
    IN p_actor_id INTEGER,
    IN p_name TEXT,
    IN p_max_teams INTEGER,
    OUT id INTEGER,
    OUT name VARCHAR,
    OUT status VARCHAR,
    OUT total_slots INTEGER,
    OUT available_slots INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM users WHERE users.id = p_actor_id AND users.role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Hanya admin yang dapat mengelola turnamen'
            USING ERRCODE = '42501';
    END IF;

    SELECT
        created_tournament.id,
        created_tournament.name,
        created_tournament.status,
        created_tournament.total_slots,
        created_tournament.available_slots
    INTO id, name, status, total_slots, available_slots
    FROM fn_create_tournament(p_name, p_max_teams) AS created_tournament;
    COMMIT;
END;
$$;

CREATE PROCEDURE pr_register_team_to_tournament(
    IN p_actor_id INTEGER,
    IN p_tournament_name TEXT,
    IN p_team_name TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_team_id INTEGER;
    v_captain_id INTEGER;
BEGIN
    SELECT teams.id, teams.captain_id
    INTO v_team_id, v_captain_id
    FROM teams
    WHERE teams.name = p_team_name
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tim "%" tidak ditemukan', p_team_name
            USING ERRCODE = 'P0002';
    END IF;

    IF v_captain_id IS DISTINCT FROM p_actor_id THEN
        RAISE EXCEPTION 'Hanya kapten tim yang dapat mendaftarkan tim ini'
            USING ERRCODE = '42501';
    END IF;

    PERFORM fn_register_team_to_tournament(
        fn_tournament_id_by_name(p_tournament_name),
        v_team_id
    );
    COMMIT;
END;
$$;

CREATE PROCEDURE pr_delete_tournament(
    IN p_actor_id INTEGER,
    IN p_tournament_name TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM users WHERE users.id = p_actor_id AND users.role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Hanya admin yang dapat mengelola turnamen'
            USING ERRCODE = '42501';
    END IF;

    PERFORM fn_delete_tournament(fn_tournament_id_by_name(p_tournament_name));
    COMMIT;
END;
$$;

-- Prosedur pertandingan membungkus function operasi pertandingan.
CREATE PROCEDURE pr_create_match(
    IN p_actor_id INTEGER,
    IN p_tournament_name TEXT,
    IN p_team_a_name TEXT,
    IN p_team_b_name TEXT,
    IN p_round_number INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM users WHERE users.id = p_actor_id AND users.role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Hanya admin yang dapat mengelola pertandingan'
            USING ERRCODE = '42501';
    END IF;

    PERFORM fn_create_match(
        fn_tournament_id_by_name(p_tournament_name),
        CASE
            WHEN p_team_a_name IS NULL THEN NULL
            ELSE fn_team_id_by_name(p_team_a_name)
        END,
        CASE
            WHEN p_team_b_name IS NULL THEN NULL
            ELSE fn_team_id_by_name(p_team_b_name)
        END,
        p_round_number
    );
    COMMIT;
END;
$$;

CREATE PROCEDURE pr_update_match_schedule(
    IN p_actor_id INTEGER,
    IN p_match_id INTEGER,
    IN p_schedule_time TIMESTAMP
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM users WHERE users.id = p_actor_id AND users.role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Hanya admin yang dapat mengelola pertandingan'
            USING ERRCODE = '42501';
    END IF;

    IF NOT fn_update_match_schedule(p_match_id, p_schedule_time) THEN
        RAISE EXCEPTION 'Match % tidak ditemukan', p_match_id;
    END IF;
    COMMIT;
END;
$$;

CREATE PROCEDURE pr_get_match_id_by_tournament_and_team(
    IN p_actor_id INTEGER,
    IN p_tournament_name TEXT,
    IN p_team_name TEXT,
    OUT match_id INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_tournament_id INTEGER;
    v_team_id INTEGER;
    v_match_count BIGINT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM users WHERE users.id = p_actor_id AND users.role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Hanya admin yang dapat mengelola pertandingan'
            USING ERRCODE = '42501';
    END IF;

    v_tournament_id := fn_tournament_id_by_name(p_tournament_name);
    v_team_id := fn_team_id_by_name(p_team_name);

    SELECT COUNT(*), MIN(matches.id)
    INTO v_match_count, match_id
    FROM matches
    WHERE matches.tournament_id = v_tournament_id
      AND (matches.team_a_id = v_team_id OR matches.team_b_id = v_team_id);

    IF v_match_count = 0 THEN
        RAISE EXCEPTION 'Tidak ada pertandingan tim "%" di turnamen "%"', p_team_name, p_tournament_name
            USING ERRCODE = 'P0002';
    ELSIF v_match_count > 1 THEN
        RAISE EXCEPTION 'Tim "%" memiliki lebih dari satu pertandingan di turnamen "%"', p_team_name, p_tournament_name
            USING ERRCODE = 'P0003';
    END IF;
END;
$$;

-- Profile, team lifecycle, account deletion, and match result procedures.
CREATE PROCEDURE pr_update_username(
    IN p_actor_id INTEGER,
    IN p_username TEXT,
    OUT id INTEGER,
    OUT username VARCHAR,
    OUT mmr_point INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_username IS NULL OR p_username !~ '^[A-Za-z0-9_-]{3,32}$' THEN
        RAISE EXCEPTION 'Username harus 3-32 karakter dan hanya berisi huruf, angka, _ atau -'
            USING ERRCODE = '22023';
    END IF;

    UPDATE users
    SET username = p_username
    WHERE users.id = p_actor_id
    RETURNING users.id, users.username, users.mmr_point
    INTO id, username, mmr_point;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Player tidak ditemukan'
            USING ERRCODE = 'P0002';
    END IF;
    COMMIT;
END;
$$;

CREATE PROCEDURE pr_leave_team(
    IN p_actor_id INTEGER,
    IN p_team_name TEXT,
    IN p_new_captain_username TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_team_id INTEGER;
    v_captain_id INTEGER;
    v_new_captain_id INTEGER;
BEGIN
    SELECT teams.id, teams.captain_id
    INTO v_team_id, v_captain_id
    FROM teams
    WHERE teams.name = p_team_name
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tim "%" tidak ditemukan', p_team_name
            USING ERRCODE = 'P0002';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM team_members
        WHERE team_id = v_team_id AND user_id = p_actor_id
    ) THEN
        RAISE EXCEPTION 'Player bukan anggota tim "%"', p_team_name
            USING ERRCODE = 'P0001';
    END IF;

    IF v_captain_id = p_actor_id THEN
        IF p_new_captain_username IS NULL THEN
            RAISE EXCEPTION 'Kapten harus memilih pengganti sebelum keluar dari tim'
                USING ERRCODE = '23514';
        END IF;

        SELECT id INTO v_new_captain_id
        FROM users
        WHERE username = p_new_captain_username;

        IF v_new_captain_id IS NULL
           OR v_new_captain_id = p_actor_id
           OR NOT EXISTS (
            SELECT 1
            FROM team_members
            WHERE team_id = v_team_id AND user_id = v_new_captain_id
        ) THEN
            RAISE EXCEPTION 'Kapten pengganti harus anggota lain dari tim'
                USING ERRCODE = '23514';
        END IF;

        UPDATE teams
        SET captain_id = v_new_captain_id
        WHERE id = v_team_id;
    END IF;

    DELETE FROM team_members
    WHERE team_id = v_team_id AND user_id = p_actor_id;
    COMMIT;
END;
$$;

CREATE PROCEDURE pr_delete_team(
    IN p_actor_id INTEGER,
    IN p_team_name TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_team_id INTEGER;
    v_captain_id INTEGER;
BEGIN
    SELECT teams.id, teams.captain_id
    INTO v_team_id, v_captain_id
    FROM teams
    WHERE teams.name = p_team_name
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tim "%" tidak ditemukan', p_team_name
            USING ERRCODE = 'P0002';
    END IF;

    IF v_captain_id IS DISTINCT FROM p_actor_id THEN
        RAISE EXCEPTION 'Hanya kapten tim yang dapat menghapus tim'
            USING ERRCODE = '42501';
    END IF;

    -- Pertahankan histori pertandingan, hanya hapus referensi tim yang bubar.
    -- Tim lawan tidak kehilangan catatan pertandingannya di turnamen.
    UPDATE matches
    SET
        team_a_id = CASE WHEN team_a_id = v_team_id THEN NULL ELSE team_a_id END,
        team_b_id = CASE WHEN team_b_id = v_team_id THEN NULL ELSE team_b_id END,
        winner_id = CASE WHEN winner_id = v_team_id THEN NULL ELSE winner_id END
    WHERE team_a_id = v_team_id
       OR team_b_id = v_team_id
       OR winner_id = v_team_id;

    DELETE FROM teams
    WHERE id = v_team_id;
    COMMIT;
END;
$$;

CREATE PROCEDURE pr_delete_user(
    IN p_actor_id INTEGER,
    IN p_captain_replacements JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_team RECORD;
    v_new_captain_username TEXT;
    v_new_captain_id INTEGER;
    v_replacement_count INTEGER;
    v_captain_team_count INTEGER;
BEGIN
    PERFORM 1 FROM users WHERE id = p_actor_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Player tidak ditemukan'
            USING ERRCODE = 'P0002';
    END IF;

    IF p_captain_replacements IS NULL
       OR jsonb_typeof(p_captain_replacements) <> 'array' THEN
        RAISE EXCEPTION 'Daftar kapten pengganti harus berupa array JSON'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_to_recordset(p_captain_replacements)
            AS replacements(team_id INTEGER, new_captain_username TEXT)
        WHERE replacements.team_id IS NULL
           OR replacements.new_captain_username IS NULL
           OR BTRIM(replacements.new_captain_username) = ''
           OR CHAR_LENGTH(BTRIM(replacements.new_captain_username)) > 100
    ) THEN
        RAISE EXCEPTION 'Data kapten pengganti tidak lengkap'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT replacements.team_id
        FROM jsonb_to_recordset(p_captain_replacements)
            AS replacements(team_id INTEGER, new_captain_username TEXT)
        GROUP BY replacements.team_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION 'Setiap tim hanya boleh memiliki satu kapten pengganti'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_to_recordset(p_captain_replacements)
            AS replacements(team_id INTEGER, new_captain_username TEXT)
        LEFT JOIN teams
            ON teams.id = replacements.team_id
           AND teams.captain_id = p_actor_id
        WHERE teams.id IS NULL
    ) THEN
        RAISE EXCEPTION 'Pengganti hanya boleh ditentukan untuk tim yang dipimpin player'
            USING ERRCODE = '22023';
    END IF;

    SELECT COUNT(*) INTO v_replacement_count
    FROM jsonb_to_recordset(p_captain_replacements)
        AS replacements(team_id INTEGER, new_captain_username TEXT);

    SELECT COUNT(*) INTO v_captain_team_count
    FROM teams
    WHERE captain_id = p_actor_id;

    IF v_replacement_count <> v_captain_team_count THEN
        RAISE EXCEPTION 'Pilih satu kapten pengganti untuk setiap tim yang dipimpin'
            USING ERRCODE = '23514';
    END IF;

    FOR v_team IN
        SELECT teams.id
        FROM teams
        WHERE teams.captain_id = p_actor_id
        ORDER BY teams.id
        FOR UPDATE
    LOOP
        SELECT replacements.new_captain_username
        INTO v_new_captain_username
        FROM jsonb_to_recordset(p_captain_replacements)
            AS replacements(team_id INTEGER, new_captain_username TEXT)
        WHERE replacements.team_id = v_team.id;

        SELECT id INTO v_new_captain_id
        FROM users
        WHERE username = v_new_captain_username;

        IF v_new_captain_id IS NULL
           OR v_new_captain_id = p_actor_id
           OR NOT EXISTS (
            SELECT 1
            FROM team_members
            WHERE team_id = v_team.id AND user_id = v_new_captain_id
        ) THEN
            RAISE EXCEPTION 'Kapten pengganti harus anggota lain dari tim'
                USING ERRCODE = '23514';
        END IF;

        UPDATE teams
        SET captain_id = v_new_captain_id
        WHERE id = v_team.id;
    END LOOP;

    DELETE FROM users
    WHERE id = p_actor_id;
    COMMIT;
END;
$$;

CREATE PROCEDURE pr_set_match_result(
    IN p_actor_id INTEGER,
    IN p_match_id INTEGER,
    IN p_winner_team_name TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_team_a_id INTEGER;
    v_team_b_id INTEGER;
    v_winner_id INTEGER;
    v_match_status VARCHAR(50);
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM users WHERE id = p_actor_id AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Hanya admin yang dapat mengelola pertandingan'
            USING ERRCODE = '42501';
    END IF;

    SELECT matches.team_a_id, matches.team_b_id, matches.status
    INTO v_team_a_id, v_team_b_id, v_match_status
    FROM matches
    WHERE matches.id = p_match_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pertandingan tidak ditemukan'
            USING ERRCODE = 'P0002';
    END IF;

    -- Guard: cegah perubahan hasil pertandingan yang sudah final.
    IF v_match_status = 'completed' THEN
        RAISE EXCEPTION 'Pertandingan ini sudah selesai dan hasilnya tidak dapat diubah'
            USING ERRCODE = '22023';
    END IF;

    v_winner_id := fn_team_id_by_name(p_winner_team_name);
    IF v_winner_id IS DISTINCT FROM v_team_a_id
       AND v_winner_id IS DISTINCT FROM v_team_b_id THEN
        RAISE EXCEPTION 'Pemenang harus merupakan salah satu tim yang bertanding'
            USING ERRCODE = '22023';
    END IF;

    UPDATE matches
    SET winner_id = v_winner_id, status = 'completed'
    WHERE id = p_match_id;
    COMMIT;
END;
$$;

-- ============================================================================
-- Procedure READ (SELECT) — backend cukup CALL, tidak perlu tulis SQL langsung.
-- Procedure ini membungkus view agar semua akses data terpusat di database layer.
-- ============================================================================

-- pr_login: Ambil data akun untuk proses login (verifikasi password di backend).
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

-- pr_get_user_profile: Ambil profil user berdasarkan ID.
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

-- pr_get_teams: Ambil seluruh daftar tim (gunakan refcursor untuk multi-row).
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

-- pr_get_team_profile: Ambil profil tim + daftar anggota (dua cursor).
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

-- pr_get_tournaments: Ambil seluruh daftar turnamen.
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

-- pr_get_tournament_teams: Ambil tim terdaftar di sebuah turnamen.
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

-- pr_get_tournament_matches: Ambil jadwal pertandingan di sebuah turnamen.
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
