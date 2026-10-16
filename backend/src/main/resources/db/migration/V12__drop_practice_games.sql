-- Practice is no longer a game: it hands out random questions instead (see
-- PracticeController), so the flag V11 added has nothing left to mark.
ALTER TABLE game
    DROP COLUMN practice;
