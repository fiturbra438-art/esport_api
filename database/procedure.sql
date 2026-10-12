-- Hapus signature lama yang menerima ID secara langsung.
DROP PROCEDURE IF EXISTS pr_create_team(TEXT, INTEGER);
DROP PROCEDURE IF EXISTS pr_create_team(TEXT, TEXT);
DROP PROCEDURE IF EXISTS pr_create_tournament(TEXT);
DROP PROCEDURE IF EXISTS pr_register_team_to_tournament(INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS pr_register_team_to_tournament(TEXT, TEXT);
DROP PROCEDURE IF EXISTS pr_add_team_member(INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS pr_add_team_member(TEXT, TEXT);
DROP PROCEDURE IF EXISTS pr_remove_team_member(INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS pr_remove_team_member(TEXT, TEXT);
DROP PROCEDURE IF EXISTS pr_transfer_captain(INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS pr_transfer_captain(TEXT, TEXT);
DROP PROCEDURE IF EXISTS pr_create_match(INTEGER, INTEGER, INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS pr_create_match(TEXT, TEXT, TEXT, INTEGER);
DROP PROCEDURE IF EXISTS pr_delete_tournament(INTEGER);
DROP PROCEDURE IF EXISTS pr_delete_tournament(TEXT);
DROP PROCEDURE IF EXISTS pr_update_match_schedule(INTEGER, TIMESTAMP);
DROP PROCEDURE IF EXISTS pr_register_user(TEXT, TEXT, INTEGER);
DROP PROCEDURE IF EXISTS pr_get_user_id_by_username(TEXT);
DROP PROCEDURE IF EXISTS pr_get_team_id_by_name(TEXT);
DROP PROCEDURE IF EXISTS pr_get_tournament_id_by_name(TEXT);

-- Lookup wrappers
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
END;
$$;

-- Prosedur tim membungkus function operasi tim.
CREATE PROCEDURE pr_create_team(
    IN p_name TEXT,
    IN p_captain_username TEXT,
    OUT id INTEGER,
    OUT name VARCHAR,
    OUT captain_id INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT created_team.id, created_team.name, created_team.captain_id
    INTO id, name, captain_id
    FROM fn_create_team(p_name, p_captain_username) AS created_team;
END;
$$;

CREATE PROCEDURE pr_add_team_member(IN p_team_name TEXT, IN p_username TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT fn_add_team_member(
        fn_team_id_by_name(p_team_name),
        fn_user_id_by_username(p_username)
    ) THEN
        RAISE EXCEPTION 'Player "%" sudah menjadi anggota tim "%"', p_username, p_team_name;
    END IF;
END;
$$;

CREATE PROCEDURE pr_remove_team_member(IN p_team_name TEXT, IN p_username TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT fn_remove_team_member(
        fn_team_id_by_name(p_team_name),
        fn_user_id_by_username(p_username)
    ) THEN
        RAISE EXCEPTION 'Player "%" bukan anggota tim "%"', p_username, p_team_name;
    END IF;
END;
$$;

CREATE PROCEDURE pr_transfer_captain(
    IN p_team_name TEXT,
    IN p_new_captain_username TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT fn_transfer_captain(
        fn_team_id_by_name(p_team_name),
        fn_user_id_by_username(p_new_captain_username)
    ) THEN
        RAISE EXCEPTION
            'Player "%" belum menjadi anggota tim "%"',
            p_new_captain_username,
            p_team_name;
    END IF;
END;
$$;

-- Prosedur turnamen membungkus function operasi turnamen.
CREATE PROCEDURE pr_create_tournament(
    IN p_name TEXT,
    OUT id INTEGER,
    OUT name VARCHAR,
    OUT status VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT created_tournament.id, created_tournament.name, created_tournament.status
    INTO id, name, status
    FROM fn_create_tournament(p_name) AS created_tournament;
END;
$$;

CREATE PROCEDURE pr_register_team_to_tournament(
    IN p_tournament_name TEXT,
    IN p_team_name TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_register_team_to_tournament(
        fn_tournament_id_by_name(p_tournament_name),
        fn_team_id_by_name(p_team_name)
    );
END;
$$;

CREATE PROCEDURE pr_delete_tournament(IN p_tournament_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_delete_tournament(fn_tournament_id_by_name(p_tournament_name));
END;
$$;

-- Prosedur pertandingan membungkus function operasi pertandingan.
CREATE PROCEDURE pr_create_match(
    IN p_tournament_name TEXT,
    IN p_team_a_name TEXT,
    IN p_team_b_name TEXT,
    IN p_round_number INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
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
END;
$$;

CREATE PROCEDURE pr_update_match_schedule(
    IN p_match_id INTEGER,
    IN p_schedule_time TIMESTAMP
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT fn_update_match_schedule(p_match_id, p_schedule_time) THEN
        RAISE EXCEPTION 'Match % tidak ditemukan', p_match_id;
    END IF;
END;
$$;
