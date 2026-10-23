ALTER TABLE team ADD COLUMN final_answer text;
ALTER TABLE game ADD COLUMN final_answers_locked boolean NOT NULL DEFAULT false;
