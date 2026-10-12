-- Hapus signature lama yang masih menggunakan ID.
DROP PROCEDURE IF EXISTS pr_create_team(TEXT, INTEGER);
DROP PROCEDURE IF EXISTS pr_create_team(TEXT, TEXT);
DROP PROCEDURE IF EXISTS pr_create_tournament(TEXT);
DROP PROCEDURE IF EXISTS pr_register_team_to_tournament(INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS pr_add_team_member(INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS pr_remove_team_member(INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS pr_transfer_captain(INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS pr_create_match(INTEGER, INTEGER, INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS pr_delete_tournament(INTEGER);

-- Prosedur tim
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
        created_team.id,
        created_team.name,
        created_team.captain_id
    INTO id, name, captain_id
    FROM fn_create_team(p_name, p_captain_username) AS created_team;

    COMMIT;
END;
$$;

CREATE OR REPLACE PROCEDURE pr_add_team_member(
    p_team_name TEXT,
    p_username TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT fn_add_team_member(
        fn_team_id_by_name(p_team_name),
        fn_user_id_by_username(p_username)
    ) THEN
        RAISE EXCEPTION
            'Player "%" sudah menjadi anggota tim "%"',
            p_username,
            p_team_name;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE pr_remove_team_member(
    p_team_name TEXT,
    p_username TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT fn_remove_team_member(
        fn_team_id_by_name(p_team_name),
        fn_user_id_by_username(p_username)
    ) THEN
        RAISE EXCEPTION
            'Player "%" bukan anggota tim "%"',
            p_username,
            p_team_name;
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
        RAISE EXCEPTION
            'Player "%" belum menjadi anggota tim "%"',
            p_new_captain_username,
            p_team_name;
    END IF;
END;
$$;

-- Prosedur turnamen
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
    RETURNING
        tournaments.id,
        tournaments.name,
        tournaments.status
    INTO id, name, status;

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

CREATE OR REPLACE PROCEDURE pr_delete_tournament(
    p_tournament_name TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM tournaments
    WHERE id = fn_tournament_id_by_name(p_tournament_name);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Turnamen "%" tidak ditemukan', p_tournament_name;
    END IF;
END;
$$;

-- Prosedur pertandingan
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
