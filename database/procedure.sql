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
