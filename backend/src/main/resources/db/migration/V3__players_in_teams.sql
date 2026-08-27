-- A team was effectively one device: it held the bearer token, so two people
-- sitting on the same team could not both have a buzzer. Split the two ideas:
--   team   = the scoring unit (name, score, wager)
--   player = a person on a device, belonging to exactly one team
-- Any member may buzz for their team; the score and the per-clue lockout stay
-- with the team.

CREATE TABLE player (
    id        UUID    PRIMARY KEY,
    game_id   UUID    NOT NULL REFERENCES game (id) ON DELETE CASCADE,
    team_id   UUID    NOT NULL REFERENCES team (id) ON DELETE CASCADE,
    name      TEXT    NOT NULL,
    token     TEXT    NOT NULL,
    is_host   BOOLEAN NOT NULL DEFAULT FALSE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (game_id, name)
);

CREATE INDEX idx_player_game ON player (game_id);
CREATE INDEX idx_player_team ON player (team_id);

-- Carry existing teams over as a single-member team so games created before
-- this change stay coherent rather than losing their credentials.
INSERT INTO player (id, game_id, team_id, name, token, is_host, joined_at)
SELECT gen_random_uuid(), t.game_id, t.id, t.name, t.token, t.is_host, t.joined_at
  FROM team t;

-- Credentials now live on the player, and host-ness is a property of a person.
ALTER TABLE team DROP COLUMN token;
ALTER TABLE team DROP COLUMN is_host;

-- Knowing which team buzzed is enough to score it, but the host also needs to
-- see which member actually hit the button.
ALTER TABLE game ADD COLUMN buzzed_player_id UUID REFERENCES player (id) ON DELETE SET NULL;
