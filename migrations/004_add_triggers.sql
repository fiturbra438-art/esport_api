-- Trigger: captain otomatis masuk ke team_members
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
            WHERE team_id = NEW.id AND user_id = NEW.captain_id
        );
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_sync_captain_membership
AFTER INSERT OR UPDATE OF captain_id ON teams
FOR EACH ROW
EXECUTE FUNCTION fn_sync_captain_membership();

-- Trigger: mencegah duplikasi pendaftaran turnamen
CREATE OR REPLACE FUNCTION fn_prevent_duplicate_registration()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM tournament_registrations
        WHERE tournament_id = NEW.tournament_id AND team_id = NEW.team_id
    ) THEN
        RAISE EXCEPTION 'Tim sudah terdaftar pada turnamen ini';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_prevent_duplicate_registration
BEFORE INSERT ON tournament_registrations
FOR EACH ROW
EXECUTE FUNCTION fn_prevent_duplicate_registration();

-- Trigger: update available_slots otomatis saat pendaftaran
CREATE OR REPLACE FUNCTION fn_update_tournament_slots_on_register()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE tournaments
    SET available_slots = available_slots + 1
    WHERE id = NEW.tournament_id;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_update_tournament_slots_on_register
AFTER INSERT ON tournament_registrations
FOR EACH ROW
EXECUTE FUNCTION fn_update_tournament_slots_on_register();

-- Trigger: update available_slots otomatis saat batal register
CREATE OR REPLACE FUNCTION fn_update_tournament_slots_on_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE tournaments
    SET available_slots = GREATEST(available_slots - 1, 0)
    WHERE id = OLD.tournament_id;

    RETURN OLD;
END;
$$;

CREATE OR REPLACE TRIGGER trg_update_tournament_slots_on_delete
AFTER DELETE ON tournament_registrations
FOR EACH ROW
EXECUTE FUNCTION fn_update_tournament_slots_on_delete();
