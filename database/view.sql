-- =====================================================
-- VIEW: daftar turnamen
-- =====================================================
CREATE OR REPLACE VIEW vw_tournaments AS
SELECT id, name, status, total_slots, available_slots, created_at
FROM tournaments;

-- =====================================================
-- VIEW: profil tim dan anggotanya
-- =====================================================
CREATE OR REPLACE VIEW vw_team_members AS
SELECT
    teams.id AS team_id,
    teams.name AS team_name,
    teams.captain_id,
    users.id AS user_id,
    users.username,
    team_members.status,
    team_members.joined_at
FROM teams
LEFT JOIN team_members ON team_members.team_id = teams.id
LEFT JOIN users ON users.id = team_members.user_id;

-- =====================================================
-- VIEW: jadwal pertandingan dengan nama tim
-- =====================================================
CREATE OR REPLACE VIEW vw_match_schedule AS
SELECT
    matches.id,
    matches.tournament_id,
    matches.round_number,
    matches.schedule_time,
    matches.status,
    t1.name AS team1_name,
    t2.name AS team2_name,
    winner.name AS winner_name
FROM matches
LEFT JOIN teams t1 ON t1.id = matches.team_a_id
LEFT JOIN teams t2 ON t2.id = matches.team_b_id
LEFT JOIN teams winner ON winner.id = matches.winner_id;