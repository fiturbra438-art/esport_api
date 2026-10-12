-- Lookup helpers keep name-based procedure calls explicit and fail clearly
-- when the requested user, team, or tournament does not exist.
CREATE INDEX IF NOT EXISTS idx_tournaments_name
    ON tournaments (name);

CREATE OR REPLACE FUNCTION fn_user_id_by_username(p_username TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_user_id INTEGER;
BEGIN
    SELECT id INTO v_user_id
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
    SELECT id INTO v_team_id
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
        SELECT id INTO STRICT v_tournament_id
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

DROP PROCEDURE IF EXISTS pr_create_team(TEXT, INTEGER);
DROP PROCEDURE IF EXISTS pr_register_team_to_tournament(INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS pr_add_team_member(INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS pr_remove_team_member(INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS pr_transfer_captain(INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS pr_create_match(INTEGER, INTEGER, INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS pr_delete_tournament(INTEGER);

DROP FUNCTION IF EXISTS fn_create_team(TEXT, INTEGER);
DROP FUNCTION IF EXISTS fn_create_team(TEXT, TEXT);

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

DROP FUNCTION IF EXISTS fn_add_team_member(INTEGER, INTEGER);
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

DROP FUNCTION IF EXISTS fn_remove_team_member(INTEGER, INTEGER);
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

DROP FUNCTION IF EXISTS fn_transfer_captain(INTEGER, INTEGER);
CREATE FUNCTION fn_transfer_captain(p_team_id INTEGER, p_new_captain_id INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM team_members
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

    COMMIT;
END;
$$;

CREATE OR REPLACE PROCEDURE pr_register_team_to_tournament(
    p_tournament_name TEXT,
    p_team_name TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO tournament_registrations (tournament_id, team_id)
    VALUES (
        fn_tournament_id_by_name(p_tournament_name),
        fn_team_id_by_name(p_team_name)
    );
END;
$$;

CREATE OR REPLACE PROCEDURE pr_add_team_member(p_team_name TEXT, p_username TEXT)
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

CREATE OR REPLACE PROCEDURE pr_remove_team_member(p_team_name TEXT, p_username TEXT)
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

CREATE OR REPLACE PROCEDURE pr_transfer_captain(
    p_team_name TEXT,
    p_new_captain_username TEXT
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

CREATE OR REPLACE PROCEDURE pr_create_match(
    p_tournament_name TEXT,
    p_team_a_name TEXT,
    p_team_b_name TEXT,
    p_round_number INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_create_match(
        fn_tournament_id_by_name(p_tournament_name),
        CASE WHEN p_team_a_name IS NULL THEN NULL ELSE fn_team_id_by_name(p_team_a_name) END,
        CASE WHEN p_team_b_name IS NULL THEN NULL ELSE fn_team_id_by_name(p_team_b_name) END,
        p_round_number
    );

    COMMIT;
END;
$$;

CREATE OR REPLACE PROCEDURE pr_delete_tournament(p_tournament_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM tournaments
    WHERE id = fn_tournament_id_by_name(p_tournament_name);
END;
$$;
