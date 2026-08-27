-- A game was originally scoped to a single round, which meant the final round
-- always began with every team on zero -- and a wager you cannot fund is not a
-- wager. A game now optionally walks a whole package (boards 1-3, then the
-- final) with scores carried across, which is how these tournaments are played.
ALTER TABLE game
    ADD COLUMN package_id      BIGINT  REFERENCES package (id),
    ADD COLUMN progress_rounds BOOLEAN NOT NULL DEFAULT FALSE;

-- Backfill the package for any game created before this change.
UPDATE game g
   SET package_id = r.package_id
  FROM round r
 WHERE r.id = g.round_id
   AND g.package_id IS NULL;

ALTER TABLE game ALTER COLUMN package_id SET NOT NULL;
