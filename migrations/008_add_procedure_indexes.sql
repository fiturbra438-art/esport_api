-- Indeks untuk filter jadwal dan kolom foreign key yang belum tercakup
-- oleh indeks primary key atau constraint UNIQUE.
CREATE INDEX idx_teams_captain_id
    ON teams (captain_id);

CREATE INDEX idx_team_members_user_id
    ON team_members (user_id);

CREATE INDEX idx_tournament_registrations_team_id
    ON tournament_registrations (team_id);

CREATE INDEX idx_matches_tournament_round
    ON matches (tournament_id, round_number, id);

CREATE INDEX idx_matches_team_a_id
    ON matches (team_a_id);

CREATE INDEX idx_matches_team_b_id
    ON matches (team_b_id);

CREATE INDEX idx_matches_winner_id
    ON matches (winner_id);
