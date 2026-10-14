-- A person no longer has to sit on a team. A player with no team is a solo
-- player, and the scoring unit stays the team: a solo player gets a team of one,
-- flagged here so the join list and the "team name is taken" check can tell it
-- from a team somebody made on purpose. Everything that already hangs off a
-- team -- score, wager, per-clue lockout, the buzz itself -- therefore works for
-- a solo player without a second code path.
ALTER TABLE team ADD COLUMN solo BOOLEAN NOT NULL DEFAULT FALSE;

-- A solo team is named after its player, and player names are only unique among
-- players. Someone called "ანა" and a team called "ანა" are different things, so
-- name uniqueness now applies to the teams people chose, not to solo ones.
ALTER TABLE team DROP CONSTRAINT team_game_id_name_key;
CREATE UNIQUE INDEX uq_team_game_name ON team (game_id, name) WHERE NOT solo;
