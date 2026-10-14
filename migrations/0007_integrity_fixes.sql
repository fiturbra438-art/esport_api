-- ============================================================================
-- Migration 0007: Integrity Fixes (Perbaikan Celah Integritas Basis Data)
-- Jalankan file ini pada database yang sudah berjalan (existing database).
-- File database.sql, function.sql, trigger.sql, procedure.sql, dan dcl.sql
-- sudah mencerminkan perubahan ini; migration ini hanya untuk database existing.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- [FIX 1] Constraint: Tim tidak boleh bertanding melawan dirinya sendiri.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.constraint_column_usage
        WHERE constraint_name = 'chk_matches_distinct_teams'
    ) THEN
        ALTER TABLE matches
        ADD CONSTRAINT chk_matches_distinct_teams
            CHECK (team_a_id IS NULL OR team_b_id IS NULL OR team_a_id <> team_b_id);
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- [FIX 2] Constraint: Nomor ronde harus positif (> 0).
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.constraint_column_usage
        WHERE constraint_name = 'chk_matches_round_positive'
    ) THEN
        ALTER TABLE matches
        ADD CONSTRAINT chk_matches_round_positive
            CHECK (round_number IS NULL OR round_number > 0);
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- [FIX 3] Constraint: Status kolom matches hanya terima nilai yang valid.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.constraint_column_usage
        WHERE constraint_name = 'chk_matches_status'
    ) THEN
        ALTER TABLE matches
        ADD CONSTRAINT chk_matches_status
            CHECK (status IN ('scheduled', 'ongoing', 'completed', 'cancelled'));
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- [FIX 4] Constraint: Status kolom tournaments hanya terima nilai yang valid.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.constraint_column_usage
        WHERE constraint_name = 'chk_tournaments_status'
    ) THEN
        ALTER TABLE tournaments
        ADD CONSTRAINT chk_tournaments_status
            CHECK (status IN ('open', 'ongoing', 'completed', 'cancelled'));
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- [FIX 5] FK Constraint: Ubah captain_id dari ON DELETE SET NULL
--         menjadi ON DELETE RESTRICT agar mencegah tim orphan.
-- PERHATIAN: Jalankan HANYA jika tidak ada captain_id yang bernilai NULL
--            di tabel teams. Jika ada, perbaiki data terlebih dahulu.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_orphan_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_orphan_count FROM teams WHERE captain_id IS NULL;

    IF v_orphan_count > 0 THEN
        RAISE NOTICE 'SKIP FIX 5: Ditemukan % tim dengan captain_id NULL. Perbaiki data terlebih dahulu.', v_orphan_count;
    ELSE
        ALTER TABLE teams DROP CONSTRAINT IF EXISTS teams_captain_id_fkey;
        ALTER TABLE teams
        ADD CONSTRAINT fk_teams_captain
            FOREIGN KEY (captain_id) REFERENCES users(id) ON DELETE RESTRICT;
        RAISE NOTICE 'FIX 5 berhasil: FK captain_id diubah ke ON DELETE RESTRICT.';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- [FIX 6] Trigger: Sinkronisasi slot turnamen saat terjadi UPDATE tournament_id.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_update_tournament_slots_on_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.tournament_id <> NEW.tournament_id THEN
        UPDATE tournaments
        SET available_slots = LEAST(available_slots + 1, total_slots)
        WHERE id = OLD.tournament_id;

        UPDATE tournaments
        SET available_slots = available_slots - 1
        WHERE id = NEW.tournament_id AND total_slots > 0;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_tournament_slots_on_update ON tournament_registrations;
CREATE TRIGGER trg_update_tournament_slots_on_update
AFTER UPDATE OF tournament_id
ON tournament_registrations
FOR EACH ROW
EXECUTE FUNCTION fn_update_tournament_slots_on_update();

-- ----------------------------------------------------------------------------
-- [FIX 7] fn_create_match: Validasi tim A & B terdaftar di turnamen.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_create_match(INTEGER, INTEGER, INTEGER, INTEGER);
CREATE FUNCTION fn_create_match(
    p_tournament_id INTEGER,
    p_team_a_id INTEGER,
    p_team_b_id INTEGER,
    p_round_number INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_team_a_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM tournament_registrations
        WHERE tournament_id = p_tournament_id AND team_id = p_team_a_id
    ) THEN
        RAISE EXCEPTION 'Tim A belum terdaftar pada turnamen ini' USING ERRCODE = '23503';
    END IF;

    IF p_team_b_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM tournament_registrations
        WHERE tournament_id = p_tournament_id AND team_id = p_team_b_id
    ) THEN
        RAISE EXCEPTION 'Tim B belum terdaftar pada turnamen ini' USING ERRCODE = '23503';
    END IF;

    INSERT INTO matches (tournament_id, team_a_id, team_b_id, round_number)
    VALUES (p_tournament_id, p_team_a_id, p_team_b_id, p_round_number);
END;
$$;

-- ----------------------------------------------------------------------------
-- [FIX 8] pr_delete_team: Ganti DELETE matches menjadi UPDATE (preserve history).
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS pr_delete_team(INTEGER, TEXT);
CREATE PROCEDURE pr_delete_team(
    IN p_actor_id INTEGER,
    IN p_team_name TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_team_id INTEGER;
    v_captain_id INTEGER;
BEGIN
    SELECT teams.id, teams.captain_id
    INTO v_team_id, v_captain_id
    FROM teams
    WHERE teams.name = p_team_name
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tim "%" tidak ditemukan', p_team_name
            USING ERRCODE = 'P0002';
    END IF;

    IF v_captain_id IS DISTINCT FROM p_actor_id THEN
        RAISE EXCEPTION 'Hanya kapten tim yang dapat menghapus tim'
            USING ERRCODE = '42501';
    END IF;

    UPDATE matches
    SET
        team_a_id = CASE WHEN team_a_id = v_team_id THEN NULL ELSE team_a_id END,
        team_b_id = CASE WHEN team_b_id = v_team_id THEN NULL ELSE team_b_id END,
        winner_id = CASE WHEN winner_id = v_team_id THEN NULL ELSE winner_id END
    WHERE team_a_id = v_team_id
       OR team_b_id = v_team_id
       OR winner_id = v_team_id;

    DELETE FROM teams WHERE id = v_team_id;
    COMMIT;
END;
$$;

-- ----------------------------------------------------------------------------
-- [FIX 9] pr_set_match_result: Guard cegah ubah hasil pertandingan yang final.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS pr_set_match_result(INTEGER, INTEGER, TEXT);
CREATE PROCEDURE pr_set_match_result(
    IN p_actor_id INTEGER,
    IN p_match_id INTEGER,
    IN p_winner_team_name TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_team_a_id INTEGER;
    v_team_b_id INTEGER;
    v_winner_id INTEGER;
    v_match_status VARCHAR(50);
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM users WHERE id = p_actor_id AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Hanya admin yang dapat mengelola pertandingan'
            USING ERRCODE = '42501';
    END IF;

    SELECT matches.team_a_id, matches.team_b_id, matches.status
    INTO v_team_a_id, v_team_b_id, v_match_status
    FROM matches
    WHERE matches.id = p_match_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pertandingan tidak ditemukan'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_match_status = 'completed' THEN
        RAISE EXCEPTION 'Pertandingan ini sudah selesai dan hasilnya tidak dapat diubah'
            USING ERRCODE = '22023';
    END IF;

    v_winner_id := fn_team_id_by_name(p_winner_team_name);
    IF v_winner_id IS DISTINCT FROM v_team_a_id
       AND v_winner_id IS DISTINCT FROM v_team_b_id THEN
        RAISE EXCEPTION 'Pemenang harus merupakan salah satu tim yang bertanding'
            USING ERRCODE = '22023';
    END IF;

    UPDATE matches
    SET winner_id = v_winner_id, status = 'completed'
    WHERE id = p_match_id;
    COMMIT;
END;
$$;

-- ----------------------------------------------------------------------------
-- [FIX 10] DCL Zero-Trust: Cabut INSERT/UPDATE/DELETE langsung dari esport_app.
-- Mutasi data wajib melalui Stored Procedure.
-- ----------------------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM esport_app;
