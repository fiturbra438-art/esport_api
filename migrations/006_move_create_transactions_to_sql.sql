DROP PROCEDURE IF EXISTS pr_create_team(TEXT, INTEGER);
DROP FUNCTION IF EXISTS fn_create_team(TEXT, INTEGER);

CREATE FUNCTION fn_create_team(p_name TEXT, p_captain_id INTEGER)
RETURNS TABLE(id INTEGER, name VARCHAR, captain_id INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    INSERT INTO teams (name, captain_id)
    VALUES (p_name, p_captain_id)
    RETURNING teams.id, teams.name, teams.captain_id;
END;
$$;

CREATE PROCEDURE pr_create_team(p_name TEXT, p_captain_id INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_create_team(p_name, p_captain_id);
END;
$$;

DROP PROCEDURE IF EXISTS pr_create_tournament(TEXT);
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

CREATE PROCEDURE pr_create_tournament(p_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_create_tournament(p_name);
END;
$$;