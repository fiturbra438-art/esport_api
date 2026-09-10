-- =====================================================
-- PROCEDURE: register tim ke turnamen
-- =====================================================
CREATE OR REPLACE PROCEDURE pr_register_team_to_tournament(p_tournament_id INTEGER, p_team_id INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO tournament_registrations (tournament_id, team_id)
    VALUES (p_tournament_id, p_team_id);
END;
$$;