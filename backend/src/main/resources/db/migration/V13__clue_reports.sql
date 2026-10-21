-- Reports submitted by players when a clue has a factual, typographic,
-- or answer error. Recorded so administrators or developers can review
-- findings and patch the question or answer in the catalogue.

CREATE TABLE clue_report (
    id              BIGSERIAL PRIMARY KEY,
    clue_id         BIGINT NOT NULL REFERENCES clue (id) ON DELETE CASCADE,
    description     TEXT NOT NULL,
    status          VARCHAR(32) NOT NULL DEFAULT 'PENDING',  -- PENDING | RESOLVED | DISMISSED
    reporter_ip     VARCHAR(64) NOT NULL,
    reported_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolution_note TEXT,
    resolved_at     TIMESTAMPTZ
);

CREATE INDEX idx_clue_report_clue ON clue_report (clue_id);
CREATE INDEX idx_clue_report_status ON clue_report (status);
CREATE INDEX idx_clue_report_ip_time ON clue_report (reporter_ip, reported_at);
