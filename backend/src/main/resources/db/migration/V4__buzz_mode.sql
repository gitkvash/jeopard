-- The buzzer was the host's to open, which is right when someone is minding the
-- console and wrong when nobody is: the clue goes up and the button is never
-- pressed. A game now records how its buzzer opens -- the host opens it, it
-- opens with the clue, or it opens itself after a set number of seconds -- and
-- when the timer is due, so a client reconnecting mid-clue can finish the
-- countdown rather than guess at it.
ALTER TABLE game
    ADD COLUMN buzz_mode          TEXT        NOT NULL DEFAULT 'HOST',
    ADD COLUMN buzz_delay_seconds INT         NOT NULL DEFAULT 0,
    ADD COLUMN buzz_opens_at      TIMESTAMPTZ;
