-- Users
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    mmr_point INTEGER DEFAULT 1000,
    password VARCHAR(255),
    role VARCHAR(20) NOT NULL DEFAULT 'user'
        CHECK (role IN ('user', 'admin')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tournaments
CREATE TABLE tournaments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    total_slots INTEGER NOT NULL DEFAULT 0,
    available_slots INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(50) DEFAULT 'open',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (total_slots >= 0),
    CHECK (available_slots >= 0 AND available_slots <= total_slots),
    CONSTRAINT chk_tournaments_status CHECK (status IN ('open', 'ongoing', 'completed', 'cancelled'))
);

CREATE UNIQUE INDEX uq_tournaments_name_normalized
    ON tournaments (LOWER(BTRIM(name)));

CREATE INDEX idx_tournaments_name
    ON tournaments (name);

-- Teams
CREATE TABLE teams (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    -- ON DELETE RESTRICT: kapten aktif wajib serahkan jabatan sebelum akun dihapus,
    -- mencegah tim orphan (captain_id NULL) yang tidak bisa dikelola siapapun.
    captain_id INTEGER REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Team members
CREATE TABLE team_members (
    id SERIAL PRIMARY KEY,
    team_id INTEGER REFERENCES teams(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(50) DEFAULT 'active',
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (team_id, user_id)
);

-- Tournament registrations
CREATE TABLE tournament_registrations (
    id SERIAL PRIMARY KEY,
    tournament_id INTEGER REFERENCES tournaments(id) ON DELETE CASCADE,
    team_id INTEGER REFERENCES teams(id) ON DELETE CASCADE,
    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (tournament_id, team_id)
);

-- Matches
CREATE TABLE matches (
    id SERIAL PRIMARY KEY,
    tournament_id INTEGER REFERENCES tournaments(id) ON DELETE CASCADE,
    team_a_id INTEGER REFERENCES teams(id) ON DELETE SET NULL,
    team_b_id INTEGER REFERENCES teams(id) ON DELETE SET NULL,
    winner_id INTEGER REFERENCES teams(id) ON DELETE SET NULL,
    status VARCHAR(50) DEFAULT 'scheduled',
    round_number INTEGER,
    schedule_time TIMESTAMP,
    -- Mencegah tim bertanding melawan dirinya sendiri.
    CONSTRAINT chk_matches_distinct_teams
        CHECK (team_a_id IS NULL OR team_b_id IS NULL OR team_a_id <> team_b_id),
    -- Nomor ronde harus positif.
    CONSTRAINT chk_matches_round_positive
        CHECK (round_number IS NULL OR round_number > 0),
    -- Status hanya menerima nilai yang sudah ditentukan.
    CONSTRAINT chk_matches_status
        CHECK (status IN ('scheduled', 'ongoing', 'completed', 'cancelled'))
);

-- Indeks untuk pencarian prosedur, jadwal, dan aksi foreign key.
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
