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

    COMMIT;
END;
$$;
