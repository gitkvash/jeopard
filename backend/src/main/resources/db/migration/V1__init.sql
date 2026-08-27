-- ---------------------------------------------------------------------------
-- Content: mirrors data/pilot.db as built by src/build_pilot_db.py.
-- IDs are assigned by the seeder (same numbering as pilot.db), so no sequences.
-- ---------------------------------------------------------------------------
CREATE TABLE package (
    id         BIGINT PRIMARY KEY,
    number     INT    NOT NULL UNIQUE,
    title      TEXT   NOT NULL,
    subtitle   TEXT,
    source_url TEXT
);

CREATE TABLE round (
    id          BIGINT  PRIMARY KEY,
    package_id  BIGINT  NOT NULL REFERENCES package (id),
    idx         INT     NOT NULL,
    header      TEXT,
    is_final    BOOLEAN NOT NULL DEFAULT FALSE,
    topic_count INT     NOT NULL,
    playable    BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (package_id, idx)
);

CREATE TABLE topic (
    id       BIGINT PRIMARY KEY,
    round_id BIGINT NOT NULL REFERENCES round (id),
    idx      INT    NOT NULL,
    name     TEXT   NOT NULL,
    UNIQUE (round_id, idx)
);

CREATE TABLE clue (
    id                BIGINT PRIMARY KEY,
    topic_id          BIGINT NOT NULL REFERENCES topic (id),
    value             INT,             -- NULL for final-round clues
    question          TEXT   NOT NULL,
    answer            TEXT   NOT NULL,
    question_original TEXT,            -- set only where 2008 wording was corrected
    answer_original   TEXT,
    correction_note   TEXT
);

CREATE INDEX idx_round_pkg   ON round (package_id);
CREATE INDEX idx_topic_round ON topic (round_id);
CREATE INDEX idx_clue_topic  ON clue (topic_id);

-- ---------------------------------------------------------------------------
-- Live game state. The server is authoritative: clue answers are never sent
-- to clients until the host reveals them.
-- ---------------------------------------------------------------------------
CREATE TABLE game (
    id              UUID    PRIMARY KEY,
    join_code       VARCHAR(6) NOT NULL UNIQUE,
    round_id        BIGINT  NOT NULL REFERENCES round (id),
    state           TEXT    NOT NULL,
    host_plays      BOOLEAN NOT NULL DEFAULT FALSE,
    host_token      TEXT    NOT NULL,
    current_clue_id BIGINT  REFERENCES clue (id),
    buzzed_team_id  UUID,               -- FK added after `team` exists
    answer_revealed BOOLEAN NOT NULL DEFAULT FALSE,
    answer_peeked   BOOLEAN NOT NULL DEFAULT FALSE,
    picking_team_id UUID,
    event_seq       BIGINT  NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE team (
    id        UUID    PRIMARY KEY,
    game_id   UUID    NOT NULL REFERENCES game (id) ON DELETE CASCADE,
    name      TEXT    NOT NULL,
    score     INT     NOT NULL DEFAULT 0,
    token     TEXT    NOT NULL,
    is_host   BOOLEAN NOT NULL DEFAULT FALSE,
    seat      INT     NOT NULL,
    wager     INT,                      -- final round
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (game_id, name)
);

CREATE INDEX idx_team_game ON team (game_id);

ALTER TABLE game
    ADD CONSTRAINT fk_game_buzzed_team  FOREIGN KEY (buzzed_team_id)  REFERENCES team (id) ON DELETE SET NULL,
    ADD CONSTRAINT fk_game_picking_team FOREIGN KEY (picking_team_id) REFERENCES team (id) ON DELETE SET NULL;

-- Which tiles are still on the board for this game.
CREATE TABLE game_clue (
    game_id        UUID   NOT NULL REFERENCES game (id) ON DELETE CASCADE,
    clue_id        BIGINT NOT NULL REFERENCES clue (id),
    status         TEXT   NOT NULL DEFAULT 'AVAILABLE',   -- AVAILABLE | IN_PLAY | DONE
    won_by_team_id UUID   REFERENCES team (id) ON DELETE SET NULL,
    PRIMARY KEY (game_id, clue_id)
);

-- Teams that already answered this clue wrong and may not buzz again on it.
CREATE TABLE clue_lockout (
    game_id UUID   NOT NULL REFERENCES game (id) ON DELETE CASCADE,
    clue_id BIGINT NOT NULL REFERENCES clue (id),
    team_id UUID   NOT NULL REFERENCES team (id) ON DELETE CASCADE,
    PRIMARY KEY (game_id, clue_id, team_id)
);

-- Append-only log: audit trail and catch-up for reconnecting clients.
CREATE TABLE game_event (
    id         BIGSERIAL PRIMARY KEY,
    game_id    UUID   NOT NULL REFERENCES game (id) ON DELETE CASCADE,
    seq        BIGINT NOT NULL,
    type       TEXT   NOT NULL,
    payload    JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (game_id, seq)
);
