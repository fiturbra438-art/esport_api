-- Procedures used by the API write endpoints.
CREATE OR REPLACE PROCEDURE pr_register_team_to_tournament(p_tournament_id INTEGER, p_team_id INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO tournament_registrations (tournament_id, team_id)
    VALUES (p_tournament_id, p_team_id);
END;
$$;

CREATE OR REPLACE PROCEDURE pr_create_team(p_name TEXT, p_captain_id INTEGER)
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
END;
$$;

CREATE OR REPLACE PROCEDURE pr_add_team_member(p_team_id INTEGER, p_user_id INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM team_members
        WHERE team_id = p_team_id AND user_id = p_user_id
    ) THEN
        RAISE EXCEPTION 'User % sudah menjadi anggota team %', p_user_id, p_team_id;
    END IF;

    INSERT INTO team_members (team_id, user_id, status)
    VALUES (p_team_id, p_user_id, 'active');
END;
$$;

CREATE OR REPLACE PROCEDURE pr_remove_team_member(p_team_id INTEGER, p_user_id INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM team_members
    WHERE team_id = p_team_id AND user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % bukan anggota team %', p_user_id, p_team_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE pr_transfer_captain(p_team_id INTEGER, p_new_captain_id INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM team_members
        WHERE team_id = p_team_id AND user_id = p_new_captain_id
    ) THEN
        RAISE EXCEPTION 'User % belum menjadi anggota team %', p_new_captain_id, p_team_id;
    END IF;

    UPDATE teams
    SET captain_id = p_new_captain_id
    WHERE id = p_team_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Team % tidak ditemukan', p_team_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE pr_create_tournament(p_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO tournaments (name, total_slots, available_slots, status)
    VALUES (p_name, 0, 0, 'open');
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
END;
$$;

CREATE OR REPLACE PROCEDURE pr_update_match_schedule(
    p_match_id INTEGER,
    p_schedule_time TIMESTAMP
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE matches
    SET schedule_time = p_schedule_time
    WHERE id = p_match_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Match % tidak ditemukan', p_match_id;
    END IF;
END;
$$;

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

-- Views used by the API read endpoints.
CREATE OR REPLACE VIEW vw_tournaments AS
SELECT id, name, status, total_slots, available_slots, created_at
FROM tournaments;

CREATE OR REPLACE VIEW vw_team_members AS
SELECT
    teams.id AS team_id,
    teams.name AS team_name,
    teams.captain_id,
    users.id AS user_id,
    users.username,
    team_members.status,
    team_members.joined_at
FROM teams
LEFT JOIN team_members ON team_members.team_id = teams.id
LEFT JOIN users ON users.id = team_members.user_id;

CREATE OR REPLACE VIEW vw_match_schedule AS
SELECT
    matches.id,
    matches.tournament_id,
    matches.round_number,
    matches.schedule_time,
    matches.status,
    t1.name AS team1_name,
    t2.name AS team2_name,
    winner.name AS winner_name
FROM matches
LEFT JOIN teams t1 ON t1.id = matches.team_a_id
LEFT JOIN teams t2 ON t2.id = matches.team_b_id
LEFT JOIN teams winner ON winner.id = matches.winner_id;
