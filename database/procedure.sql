-- PROCEDURE: register tim ke turnamen
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

-- PROCEDURE: register tim ke turnamen
CREATE OR REPLACE PROCEDURE pr_register_team_to_tournament(p_tournament_id INTEGER, p_team_id INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO tournament_registrations (tournament_id, team_id)
    VALUES (p_tournament_id, p_team_id);
END;
$$;

CREATE OR REPLACE PROCEDURE pr_add_team_member(p_team_id INTEGER, p_user_id INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT fn_add_team_member(p_team_id, p_user_id) THEN
        RAISE EXCEPTION 'User % sudah menjadi anggota team %', p_user_id, p_team_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE pr_remove_team_member(p_team_id INTEGER, p_user_id INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT fn_remove_team_member(p_team_id, p_user_id) THEN
        RAISE EXCEPTION 'User % bukan anggota team %', p_user_id, p_team_id;
    END IF;
END;
$$;

-- PROCEDURE: memindahkan kapten tim
CREATE OR REPLACE PROCEDURE pr_transfer_captain(p_team_id INTEGER, p_new_captain_id INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT fn_transfer_captain(p_team_id, p_new_captain_id) THEN
        RAISE EXCEPTION 'User % belum menjadi anggota team %', p_new_captain_id, p_team_id;
    END IF;
END;
$$;

-- PROCEDURE: mengatur jadwal match
CREATE OR REPLACE PROCEDURE pr_update_match_schedule(
    p_match_id INTEGER,
    p_schedule_time TIMESTAMP
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT fn_update_match_schedule(p_match_id, p_schedule_time) THEN
        RAISE EXCEPTION 'Match % tidak ditemukan', p_match_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE pr_create_match(
    p_tournament_id INTEGER,
    p_team_a_id INTEGER,
    p_team_b_id INTEGER,
    p_round_number INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO matches (tournament_id, team_a_id, team_b_id, round_number)
    VALUES (p_tournament_id, p_team_a_id, p_team_b_id, p_round_number);

    COMMIT;
END;
$$;

-- PROCEDURE: menghapus turnamen
CREATE OR REPLACE PROCEDURE pr_delete_tournament(p_tournament_id INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM tournaments
    WHERE id = p_tournament_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tournament % tidak ditemukan', p_tournament_id;
    END IF;
END;
$$;
