-- Topic suggestions submitted by players or hosts proposing new categories
-- to be added to future packages.

CREATE TABLE topic_suggestion (
    id              BIGSERIAL PRIMARY KEY,
    topic_name      TEXT NOT NULL,
    description     TEXT,
    author_name     VARCHAR(128),
    status          VARCHAR(32) NOT NULL DEFAULT 'PENDING',  -- PENDING | APPROVED | REJECTED
    suggester_ip    VARCHAR(64) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    review_note     TEXT,
    reviewed_at     TIMESTAMPTZ
);

CREATE INDEX idx_topic_suggestion_status ON topic_suggestion (status);
CREATE INDEX idx_topic_suggestion_ip_time ON topic_suggestion (suggester_ip, created_at);
