-- Treat total_slots as the registration limit and available_slots as remaining
-- capacity. Legacy tournaments with a zero limit remain unlimited.
UPDATE tournaments AS tournament
SET available_slots = CASE
    WHEN tournament.total_slots > 0 THEN GREATEST(
        tournament.total_slots - (
            SELECT COUNT(*)::INTEGER
            FROM tournament_registrations AS registration
            WHERE registration.tournament_id = tournament.id
        ),
        0
    )
    ELSE 0
END;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'tournaments_total_slots_nonnegative'
          AND conrelid = 'tournaments'::regclass
    ) THEN
        ALTER TABLE tournaments
            ADD CONSTRAINT tournaments_total_slots_nonnegative
                CHECK (total_slots >= 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'tournaments_available_slots_within_capacity'
          AND conrelid = 'tournaments'::regclass
    ) THEN
        ALTER TABLE tournaments
            ADD CONSTRAINT tournaments_available_slots_within_capacity
                CHECK (available_slots >= 0 AND available_slots <= total_slots);
    END IF;
END;
$$;

DROP PROCEDURE IF EXISTS pr_create_tournament(TEXT);
DROP PROCEDURE IF EXISTS pr_create_tournament(TEXT, INTEGER);
DROP FUNCTION IF EXISTS fn_create_tournament(TEXT);
DROP FUNCTION IF EXISTS fn_create_tournament(TEXT, INTEGER);

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

CREATE PROCEDURE pr_create_tournament(
    IN p_name TEXT,
    IN p_max_teams INTEGER,
    OUT id INTEGER,
    OUT name VARCHAR,
    OUT status VARCHAR,
    OUT total_slots INTEGER,
    OUT available_slots INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT
        created_tournament.id,
        created_tournament.name,
        created_tournament.status,
        created_tournament.total_slots,
        created_tournament.available_slots
    INTO id, name, status, total_slots, available_slots
    FROM fn_create_tournament(p_name, p_max_teams) AS created_tournament;
END;
$$;

CREATE OR REPLACE FUNCTION fn_register_team_to_tournament(
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

CREATE OR REPLACE FUNCTION fn_prevent_tournament_overbooking()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_slots INTEGER;
    v_available_slots INTEGER;
BEGIN
    SELECT total_slots, available_slots
    INTO v_total_slots, v_available_slots
    FROM tournaments
    WHERE id = NEW.tournament_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Turnamen dengan ID % tidak ditemukan', NEW.tournament_id
            USING ERRCODE = 'P0002';
    END IF;

    IF v_total_slots > 0 AND v_available_slots <= 0 THEN
        RAISE EXCEPTION 'Kuota tim turnamen sudah penuh'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_prevent_tournament_overbooking
BEFORE INSERT ON tournament_registrations
FOR EACH ROW
EXECUTE FUNCTION fn_prevent_tournament_overbooking();

CREATE OR REPLACE FUNCTION fn_update_tournament_slots_on_register()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE tournaments
    SET available_slots = available_slots - 1
    WHERE id = NEW.tournament_id
      AND total_slots > 0;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_update_tournament_slots_on_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE tournaments
    SET available_slots = LEAST(available_slots + 1, total_slots)
    WHERE id = OLD.tournament_id
      AND total_slots > 0;

    RETURN OLD;
END;
$$;
