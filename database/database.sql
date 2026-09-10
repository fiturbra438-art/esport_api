-- 1. Tabel Users
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    mmr_point INTEGER DEFAULT 1000,
    password VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Tabel Tournaments
CREATE TABLE tournaments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    total_slots INTEGER NOT NULL DEFAULT 0,
    available_slots INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(50) DEFAULT 'open',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Tabel Teams
CREATE TABLE teams (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    captain_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4. Tabel Team Members
CREATE TABLE team_members (
    id SERIAL PRIMARY KEY,
    team_id INTEGER REFERENCES teams(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(50) DEFAULT 'active',
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 5. Tabel Tournament Registrations
CREATE TABLE tournament_registrations (
    id SERIAL PRIMARY KEY,
    tournament_id INTEGER REFERENCES tournaments(id) ON DELETE CASCADE,
    team_id INTEGER REFERENCES teams(id) ON DELETE CASCADE,
    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (tournament_id, team_id)
);

-- 6. Tabel Matches (Jadwal & Skor Pertandingan)
CREATE TABLE matches (
    id SERIAL PRIMARY KEY,
    tournament_id INTEGER REFERENCES tournaments(id) ON DELETE CASCADE,
    team_a_id INTEGER REFERENCES teams(id) ON DELETE SET NULL,
    team_b_id INTEGER REFERENCES teams(id) ON DELETE SET NULL,
    winner_id INTEGER REFERENCES teams(id) ON DELETE SET NULL,
    status VARCHAR(50) DEFAULT 'scheduled',
    round_number INTEGER,
    schedule_time TIMESTAMP
);

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

-- =====================================================
-- Trigger: captain otomatis masuk ke team_members
-- =====================================================
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

-- =====================================================
-- Trigger: mencegah duplikasi pendaftaran turnamen
-- =====================================================
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

-- =====================================================
-- Trigger: update available_slots otomatis saat pendaftaran
-- =====================================================
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

-- =====================================================
-- Trigger: update available_slots otomatis saat batal register
-- =====================================================
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