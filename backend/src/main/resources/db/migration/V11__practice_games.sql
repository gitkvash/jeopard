-- A game for one person practising alone: they are the host and the only
-- player, they read the clue, look at the answer, and say for themselves
-- whether they had it. Nobody else can join one, so it needs no lobby, no
-- buzzer and no join code anyone will ever read out.
ALTER TABLE game
    ADD COLUMN practice BOOLEAN NOT NULL DEFAULT FALSE;
