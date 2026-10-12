-- Keep duplicate registration validation in the business function called by
-- the procedure. The UNIQUE constraint remains the concurrency-safe guard.
DROP TRIGGER IF EXISTS trg_prevent_duplicate_registration
ON tournament_registrations;
DROP FUNCTION IF EXISTS fn_prevent_duplicate_registration();

CREATE OR REPLACE FUNCTION fn_register_team_to_tournament(
    p_tournament_id INTEGER,
    p_team_id INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM tournament_registrations
        WHERE tournament_id = p_tournament_id
          AND team_id = p_team_id
    ) THEN
        RAISE EXCEPTION 'Tim sudah terdaftar pada turnamen ini'
            USING ERRCODE = '23505';
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

CREATE OR REPLACE PROCEDURE pr_register_team_to_tournament(
    IN p_tournament_name TEXT,
    IN p_team_name TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_register_team_to_tournament(
        fn_tournament_id_by_name(p_tournament_name),
        fn_team_id_by_name(p_team_name)
    );
END;
$$;
