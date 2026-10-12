-- Tournament views
CREATE OR REPLACE VIEW vw_tournaments AS
SELECT
    t.id,
    t.name,
    t.status,
    t.total_slots,
    t.available_slots,
    t.created_at
FROM tournaments AS t;

-- Team roster, including teams without members.
CREATE OR REPLACE VIEW vw_team_members AS
SELECT
    t.id AS team_id,
    t.name AS team_name,
    t.captain_id,
    u.id AS user_id,
    u.username,
    tm.status,
    tm.joined_at
FROM teams AS t
LEFT JOIN team_members AS tm
    ON tm.team_id = t.id
LEFT JOIN users AS u
    ON u.id = tm.user_id;

-- Team directory with captain and roster count.
CREATE OR REPLACE VIEW vw_teams AS
SELECT
    t.id,
    t.name,
    t.captain_id,
    captain.username AS captain_username,
    COUNT(tm.user_id)::INTEGER AS member_count
FROM teams AS t
LEFT JOIN users AS captain
    ON captain.id = t.captain_id
LEFT JOIN team_members AS tm
    ON tm.team_id = t.id
GROUP BY t.id, t.name, t.captain_id, captain.username;

-- Teams registered for each tournament.
CREATE OR REPLACE VIEW vw_tournament_teams AS
SELECT
    tr.tournament_id,
    tr.team_id,
    t.name AS team_name,
    t.captain_id,
    captain.username AS captain_username,
    tr.registered_at
FROM tournament_registrations AS tr
JOIN teams AS t
    ON t.id = tr.team_id
LEFT JOIN users AS captain
    ON captain.id = t.captain_id;

-- Match schedule with participating teams and winner.
CREATE OR REPLACE VIEW vw_match_schedule AS
SELECT
    m.id,
    m.tournament_id,
    m.round_number,
    m.schedule_time,
    m.status,
    t1.name AS team1_name,
    t2.name AS team2_name,
    winner.name AS winner_name
FROM matches AS m
LEFT JOIN teams AS t1
    ON t1.id = m.team_a_id
LEFT JOIN teams AS t2
    ON t2.id = m.team_b_id
LEFT JOIN teams AS winner
    ON winner.id = m.winner_id;