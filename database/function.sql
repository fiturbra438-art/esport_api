-- =====================================================
-- FUNCTION: membuat tim sekaligus mendaftarkan kapten
-- =====================================================
CREATE OR REPLACE FUNCTION fn_create_team_with_captain(p_name TEXT, p_captain_id INTEGER)
RETURNS TABLE (id INTEGER, name TEXT, captain_id INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_team_id INTEGER;
BEGIN
    INSERT INTO teams (name, captain_id)
    VALUES (p_name, p_captain_id)
    RETURNING id INTO v_team_id;

    INSERT INTO team_members (team_id, user_id, status)
    VALUES (v_team_id, p_captain_id, 'active')
    ON CONFLICT DO NOTHING;

    RETURN QUERY
    SELECT t.id, t.name, t.captain_id
    FROM teams t
    WHERE t.id = v_team_id;
END;
$$;

-- =====================================================
-- FUNCTION: join team
-- =====================================================
CREATE OR REPLACE FUNCTION fn_add_team_member(p_team_id INTEGER, p_user_id INTEGER)
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

-- =====================================================
-- FUNCTION: remove member dari team
-- =====================================================
CREATE OR REPLACE FUNCTION fn_remove_team_member(p_team_id INTEGER, p_user_id INTEGER)
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

-- =====================================================
-- FUNCTION: pindah kapten
-- =====================================================
CREATE OR REPLACE FUNCTION fn_transfer_captain(p_team_id INTEGER, p_new_captain_id INTEGER)
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

-- =====================================================
-- FUNCTION: buat turnamen
-- =====================================================
CREATE OR REPLACE FUNCTION fn_create_tournament(p_name TEXT)
RETURNS TABLE (id INTEGER, name TEXT, status TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    INSERT INTO tournaments (name, total_slots, available_slots, status)
    VALUES (p_name, 0, 0, 'open')
    RETURNING tournaments.id, tournaments.name, tournaments.status;
END;
$$;

-- =====================================================
-- FUNCTION: buat match
-- =====================================================
CREATE OR REPLACE FUNCTION fn_create_match(
    p_tournament_id INTEGER,
    p_team_a_id INTEGER,
    p_team_b_id INTEGER,
    p_round_number INTEGER
)
RETURNS TABLE (id INTEGER, tournament_id INTEGER, team_a_id INTEGER, team_b_id INTEGER, round_number INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    INSERT INTO matches (tournament_id, team_a_id, team_b_id, round_number)
    VALUES (p_tournament_id, p_team_a_id, p_team_b_id, p_round_number)
    RETURNING matches.id, matches.tournament_id, matches.team_a_id, matches.team_b_id, matches.round_number;
END;
$$;

-- =====================================================
-- FUNCTION: update jadwal match
-- =====================================================
CREATE OR REPLACE FUNCTION fn_update_match_schedule(p_match_id INTEGER, p_schedule_time TIMESTAMP)
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