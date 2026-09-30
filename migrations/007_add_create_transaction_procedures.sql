DROP PROCEDURE IF EXISTS pr_create_team(TEXT, INTEGER);

CREATE PROCEDURE pr_create_team(
    IN p_name TEXT,
    IN p_captain_id INTEGER,
    OUT id INTEGER,
    OUT name VARCHAR,
    OUT captain_id INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO teams (name, captain_id)
    VALUES (p_name, p_captain_id)
    RETURNING teams.id, teams.name, teams.captain_id
    INTO id, name, captain_id;

    COMMIT;
END;
$$;

DROP PROCEDURE IF EXISTS pr_create_tournament(TEXT);

CREATE PROCEDURE pr_create_tournament(
    IN p_name TEXT,
    OUT id INTEGER,
    OUT name VARCHAR,
    OUT status VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO tournaments (name, total_slots, available_slots, status)
    VALUES (p_name, 0, 0, 'open')
    RETURNING tournaments.id, tournaments.name, tournaments.status
    INTO id, name, status;

    COMMIT;
END;
$$;