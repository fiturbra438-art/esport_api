-- Lookup functions
CREATE OR REPLACE FUNCTION fn_user_id_by_username(
    p_username TEXT
)
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

CREATE OR REPLACE FUNCTION fn_team_id_by_name(
    p_team_name TEXT
)
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

CREATE OR REPLACE FUNCTION fn_tournament_id_by_name(
    p_tournament_name TEXT
)
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

-- Team functions
DROP FUNCTION IF EXISTS fn_create_team(TEXT, INTEGER);
DROP FUNCTION IF EXISTS fn_create_team(TEXT, TEXT);

CREATE FUNCTION fn_create_team(
    p_name TEXT,
    p_captain_username TEXT
)
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

-- Returns FALSE when the player is already a member.
CREATE OR REPLACE FUNCTION fn_add_team_member(
    p_team_id INTEGER,
    p_user_id INTEGER
)
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

-- Returns FALSE when the player is not a member.
CREATE OR REPLACE FUNCTION fn_remove_team_member(
    p_team_id INTEGER,
    p_user_id INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM team_members
        WHERE team_id = p_team_id AND user_id = p_user_id
    ) THEN
        RETURN FALSE;
    END IF;

    DELETE FROM team_members
    WHERE team_id = p_team_id AND user_id = p_user_id;

    RETURN TRUE;
END;
$$;

-- The new captain must already be a team member.
CREATE OR REPLACE FUNCTION fn_transfer_captain(
    p_team_id INTEGER,
    p_new_captain_id INTEGER
)
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

    RETURN TRUE;
END;
$$;

-- Tournament functions
DROP FUNCTION IF EXISTS fn_create_tournament(TEXT);

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

-- Match functions
CREATE OR REPLACE FUNCTION fn_create_match(
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

-- Returns FALSE when the match does not exist.
CREATE OR REPLACE FUNCTION fn_update_match_schedule(
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