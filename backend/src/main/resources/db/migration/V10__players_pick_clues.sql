-- The host chose every tile, which is right when one person runs the room and
-- wrong when the players are the ones who should be driving: they sit and wait
-- for someone to pick for them. A game can now hand the choice of tile to the
-- players in turn -- a team at a time, or a solo player at a time, in seat
-- order -- with the host still free to choose at any moment instead.
--
-- Whose turn it is lives in the existing picking_team_id, which until now only
-- remembered who answered last. With this on it is the team whose turn it is,
-- and it moves on every time a clue is finished.
ALTER TABLE game
    ADD COLUMN players_pick_clues BOOLEAN NOT NULL DEFAULT FALSE;
