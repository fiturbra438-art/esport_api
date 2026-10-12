-- Team triggers
CREATE OR REPLACE FUNCTION fn_sync_captain_membership()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.captain_id IS NOT NULL THEN
        INSERT INTO team_members (team_id, user_id, status)
        SELECT NEW.id, NEW.captain_id, 'active'
        WHERE NOT EXISTS (
            SELECT 1
            FROM team_members
            WHERE team_id = NEW.id
              AND user_id = NEW.captain_id
        );
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_sync_captain_membership
AFTER INSERT OR UPDATE OF captain_id
ON teams
FOR EACH ROW
EXECUTE FUNCTION fn_sync_captain_membership();

-- Prevent direct inserts from bypassing the tournament capacity limit.
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
BEFORE INSERT
ON tournament_registrations
FOR EACH ROW
EXECUTE FUNCTION fn_prevent_tournament_overbooking();

-- Keep remaining capacity in sync.
CREATE OR REPLACE FUNCTION fn_update_tournament_slots_on_register()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE tournaments
    SET available_slots = available_slots - 1
    WHERE id = NEW.tournament_id AND total_slots > 0;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_update_tournament_slots_on_register
AFTER INSERT
ON tournament_registrations
FOR EACH ROW
EXECUTE FUNCTION fn_update_tournament_slots_on_register();

CREATE OR REPLACE FUNCTION fn_update_tournament_slots_on_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE tournaments
    SET available_slots = LEAST(available_slots + 1, total_slots)
    WHERE id = OLD.tournament_id;

    RETURN OLD;
END;
$$;

CREATE OR REPLACE TRIGGER trg_update_tournament_slots_on_delete
AFTER DELETE
ON tournament_registrations
FOR EACH ROW
EXECUTE FUNCTION fn_update_tournament_slots_on_delete();