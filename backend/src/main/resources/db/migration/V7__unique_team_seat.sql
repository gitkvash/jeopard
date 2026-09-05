-- A team's seat was handed out as "how many teams are there, plus one", read
-- and then written without holding anything. That is fine one join at a time
-- and wrong in exactly the case this game is built for: a roomful of people
-- scanning the host's code together. Twelve simultaneous joins produced ten
-- teams all claiming seat 1, which is the order the scoreboard, the join list
-- and final-round judging are all built from.
--
-- GameService.join now locks the game row for the read-then-write, so seats
-- come out distinct. This is the backstop underneath that: if the lock is ever
-- lost in a refactor, the second team gets a constraint violation (answered as
-- a conflict by ApiErrorHandler) instead of silently sharing a seat.

-- Renumber first: existing games may already hold duplicates, and the
-- constraint would refuse to be created over them. Ordering by joined_at keeps
-- the seats in the order the teams actually arrived, which is what a seat means.
WITH renumbered AS (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY game_id ORDER BY seat, joined_at, id) AS new_seat
      FROM team
)
UPDATE team t
   SET seat = r.new_seat
  FROM renumbered r
 WHERE r.id = t.id
   AND t.seat <> r.new_seat;

ALTER TABLE team ADD CONSTRAINT uq_team_game_seat UNIQUE (game_id, seat);
