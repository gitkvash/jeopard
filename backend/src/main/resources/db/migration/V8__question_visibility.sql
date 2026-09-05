-- The clue text used to go to every device the moment a tile was picked, which
-- is right for a host who wants people reading along and wrong for one running
-- a listen-only game: read it off their own screen and a team is racing to
-- read fastest, not to know the answer fastest. A game now remembers whether a
-- participant's own device gets the question text at all. The host is never
-- subject to this -- GameService keeps sending them the text regardless, over
-- a channel a participant's device cannot reach -- so this only ever narrows
-- what a team sees, never what runs the game.
ALTER TABLE game
    ADD COLUMN questions_visible_to_participants BOOLEAN NOT NULL DEFAULT TRUE;
