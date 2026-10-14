-- Lookup functions
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

-- User functions
DROP FUNCTION IF EXISTS fn_register_user(TEXT, TEXT, INTEGER);
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

-- Tournament functions
DROP FUNCTION IF EXISTS fn_create_tournament(TEXT);
CREATE FUNCTION fn_create_tournament(p_name TEXT, p_max_teams INTEGER)
RETURNS TABLE(
    id INTEGER,
    name VARCHAR,
    status VARCHAR,
    total_slots INTEGER,
    available_slots INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_max_teams IS NULL OR p_max_teams <= 0 THEN
        RAISE EXCEPTION 'Jumlah maksimal tim harus lebih dari 0'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    INSERT INTO tournaments (name, total_slots, available_slots, status)
    VALUES (p_name, p_max_teams, p_max_teams, 'open')
    RETURNING
        tournaments.id,
        tournaments.name,
        tournaments.status,
        tournaments.total_slots,
        tournaments.available_slots;
END;
$$;

DROP FUNCTION IF EXISTS fn_register_team_to_tournament(INTEGER, INTEGER);
CREATE FUNCTION fn_register_team_to_tournament(
    p_tournament_id INTEGER,
    p_team_id INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_slots INTEGER;
    v_available_slots INTEGER;
BEGIN
    SELECT total_slots, available_slots
    INTO v_total_slots, v_available_slots
    FROM tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Turnamen dengan ID % tidak ditemukan', p_tournament_id
            USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM tournament_registrations
        WHERE tournament_id = p_tournament_id
          AND team_id = p_team_id
    ) THEN
        RAISE EXCEPTION 'Tim sudah terdaftar pada turnamen ini'
            USING ERRCODE = '23505';
    END IF;

    IF v_total_slots > 0 AND v_available_slots <= 0 THEN
        RAISE EXCEPTION 'Kuota tim turnamen sudah penuh'
            USING ERRCODE = '23514';
    END IF;

    INSERT INTO tournament_registrations (tournament_id, team_id)
    VALUES (p_tournament_id, p_team_id)
    ON CONFLICT (tournament_id, team_id) DO NOTHING;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tim sudah terdaftar pada turnamen ini'
            USING ERRCODE = '23505';
    END IF;
END;
$$;

DROP FUNCTION IF EXISTS fn_delete_tournament(INTEGER);
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
DROP FUNCTION IF EXISTS fn_create_match(INTEGER, INTEGER, INTEGER, INTEGER);
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
    -- Validasi tim A wajib terdaftar di turnamen ini.
    IF p_team_a_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM tournament_registrations
        WHERE tournament_id = p_tournament_id AND team_id = p_team_a_id
    ) THEN
        RAISE EXCEPTION 'Tim A belum terdaftar pada turnamen ini'
            USING ERRCODE = '23503';
    END IF;

    -- Validasi tim B wajib terdaftar di turnamen ini.
    IF p_team_b_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM tournament_registrations
        WHERE tournament_id = p_tournament_id AND team_id = p_team_b_id
    ) THEN
        RAISE EXCEPTION 'Tim B belum terdaftar pada turnamen ini'
            USING ERRCODE = '23503';
    END IF;

    INSERT INTO matches (tournament_id, team_a_id, team_b_id, round_number)
    VALUES (p_tournament_id, p_team_a_id, p_team_b_id, p_round_number);
END;
$$;

DROP FUNCTION IF EXISTS fn_update_match_schedule(INTEGER, TIMESTAMP);
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
