-- Upgrade cleanup: remove old overloads and implementations before recreating
-- the function -> procedure API. These DROP statements do not create routines.
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

DROP FUNCTION IF EXISTS fn_create_team(TEXT, INTEGER);
DROP FUNCTION IF EXISTS fn_create_team(TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_add_team_member(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS fn_remove_team_member(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS fn_transfer_captain(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS fn_create_tournament(TEXT);
DROP FUNCTION IF EXISTS fn_create_match(INTEGER, INTEGER, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS fn_update_match_schedule(INTEGER, TIMESTAMP);
DROP FUNCTION IF EXISTS fn_register_team_to_tournament(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS fn_delete_tournament(INTEGER);
DROP FUNCTION IF EXISTS fn_register_user(TEXT, TEXT, INTEGER);
DROP FUNCTION IF EXISTS fn_user_id_by_username(TEXT);
DROP FUNCTION IF EXISTS fn_team_id_by_name(TEXT);
DROP FUNCTION IF EXISTS fn_tournament_id_by_name(TEXT);

-- Lookup functions
CREATE OR REPLACE FUNCTION fn_user_id_by_username(p_username TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_user_id INTEGER;
BEGIN
    SELECT id
    INTO v_user_id
    FROM users
    WHERE username = p_username;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Player dengan username "%" tidak ditemukan', p_username;
    END IF;

    RETURN v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_team_id_by_name(p_team_name TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_team_id INTEGER;
BEGIN
    SELECT id
    INTO v_team_id
    FROM teams
    WHERE name = p_team_name;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tim dengan nama "%" tidak ditemukan', p_team_name;
    END IF;

    RETURN v_team_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_tournament_id_by_name(p_tournament_name TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tournament_id INTEGER;
BEGIN
    BEGIN
        SELECT id
        INTO STRICT v_tournament_id
        FROM tournaments
        WHERE name = p_tournament_name;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE EXCEPTION 'Turnamen dengan nama "%" tidak ditemukan', p_tournament_name;
        WHEN TOO_MANY_ROWS THEN
            RAISE EXCEPTION 'Nama turnamen "%" tidak unik', p_tournament_name;
    END;

    RETURN v_tournament_id;
END;
$$;

-- User functions
CREATE FUNCTION fn_register_user(
    p_username TEXT,
    p_password TEXT,
    p_mmr_point INTEGER
)
RETURNS TABLE(id INTEGER, username VARCHAR, password VARCHAR, mmr_point INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    INSERT INTO users (username, password, mmr_point)
    VALUES (p_username, p_password, p_mmr_point)
    RETURNING users.id, users.username, users.password, users.mmr_point;
END;
$$;

-- Team functions
CREATE FUNCTION fn_create_team(p_name TEXT, p_captain_username TEXT)
RETURNS TABLE(id INTEGER, name VARCHAR, captain_id INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    INSERT INTO teams (name, captain_id)
    VALUES (p_name, fn_user_id_by_username(p_captain_username))
    RETURNING teams.id, teams.name, teams.captain_id;
END;
$$;

CREATE FUNCTION fn_add_team_member(p_team_id INTEGER, p_user_id INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM team_members
        WHERE team_id = p_team_id AND user_id = p_user_id
    ) THEN
        RETURN FALSE;
    END IF;

    INSERT INTO team_members (team_id, user_id, status)
    VALUES (p_team_id, p_user_id, 'active');

    RETURN TRUE;
END;
$$;

CREATE FUNCTION fn_remove_team_member(p_team_id INTEGER, p_user_id INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM team_members
    WHERE team_id = p_team_id AND user_id = p_user_id;

    RETURN FOUND;
END;
$$;

CREATE FUNCTION fn_transfer_captain(p_team_id INTEGER, p_new_captain_id INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM team_members
        WHERE team_id = p_team_id AND user_id = p_new_captain_id
    ) THEN
        RETURN FALSE;
    END IF;

    UPDATE teams
    SET captain_id = p_new_captain_id
    WHERE id = p_team_id;

    RETURN FOUND;
END;
$$;

-- Tournament functions
CREATE FUNCTION fn_create_tournament(p_name TEXT)
RETURNS TABLE(id INTEGER, name VARCHAR, status VARCHAR)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    INSERT INTO tournaments (name, total_slots, available_slots, status)
    VALUES (p_name, 0, 0, 'open')
    RETURNING tournaments.id, tournaments.name, tournaments.status;
END;
$$;

CREATE FUNCTION fn_register_team_to_tournament(
    p_tournament_id INTEGER,
    p_team_id INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO tournament_registrations (tournament_id, team_id)
    VALUES (p_tournament_id, p_team_id);
END;
$$;

CREATE FUNCTION fn_delete_tournament(p_tournament_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM tournaments
    WHERE id = p_tournament_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Turnamen dengan ID % tidak ditemukan', p_tournament_id;
    END IF;
END;
$$;

-- Match functions
CREATE FUNCTION fn_create_match(
    p_tournament_id INTEGER,
    p_team_a_id INTEGER,
    p_team_b_id INTEGER,
    p_round_number INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO matches (tournament_id, team_a_id, team_b_id, round_number)
    VALUES (p_tournament_id, p_team_a_id, p_team_b_id, p_round_number);
END;
$$;

CREATE FUNCTION fn_update_match_schedule(
    p_match_id INTEGER,
    p_schedule_time TIMESTAMP
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE matches
    SET schedule_time = p_schedule_time
    WHERE id = p_match_id;
    RETURN FOUND;
END;
$$;

-- Lookup procedure wrappers
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

-- User procedure wrapper
CREATE PROCEDURE pr_register_user(
    IN p_username TEXT,
    IN p_password TEXT,
    IN p_mmr_point INTEGER,
    OUT id INTEGER,
    OUT username VARCHAR,
    OUT password VARCHAR,
    OUT mmr_point INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT
        u.id,
        u.username,
        u.password,
        u.mmr_point
    INTO id, username, password, mmr_point
    FROM fn_register_user(p_username, p_password, p_mmr_point) AS u;
END;
$$;

-- Team procedure wrappers
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
    SELECT
        t.id,
        t.name,
        t.captain_id
    INTO id, name, captain_id
    FROM fn_create_team(p_name, p_captain_username) AS t;
END;
$$;

CREATE PROCEDURE pr_add_team_member(
    IN p_team_name TEXT,
    IN p_username TEXT
)
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

CREATE PROCEDURE pr_remove_team_member(
    IN p_team_name TEXT,
    IN p_username TEXT
)
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
        RAISE EXCEPTION 'Player "%" belum menjadi anggota tim "%"',
            p_new_captain_username, p_team_name;
    END IF;
END;
$$;

-- Tournament procedure wrappers
CREATE PROCEDURE pr_create_tournament(
    IN p_name TEXT,
    OUT id INTEGER,
    OUT name VARCHAR,
    OUT status VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT
        t.id,
        t.name,
        t.status
    INTO id, name, status
    FROM fn_create_tournament(p_name) AS t;
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

-- Remaining tournament procedure wrapper
CREATE PROCEDURE pr_delete_tournament(IN p_tournament_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_delete_tournament(fn_tournament_id_by_name(p_tournament_name));
END;
$$;

-- Match procedure wrappers
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
