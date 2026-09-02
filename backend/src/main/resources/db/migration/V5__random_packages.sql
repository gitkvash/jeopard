-- Packets assembled at runtime by randomly remixing existing content (see
-- ContentService.generateRandomPackage). Marked synthetic so they never show
-- up in the browsable /api/packages list, but they are otherwise ordinary
-- rows a game can be created against.
ALTER TABLE package ADD COLUMN synthetic BOOLEAN NOT NULL DEFAULT FALSE;

-- package/round/topic/clue ids are hand-assigned by PilotSeeder with no
-- sequence backing them (see V1's comment). These sequences give runtime-
-- generated rows their own id space, started well above anything the seeder
-- could ever produce.
CREATE SEQUENCE package_synthetic_id_seq START WITH 1000000;
CREATE SEQUENCE round_synthetic_id_seq   START WITH 1000000;
CREATE SEQUENCE topic_synthetic_id_seq   START WITH 1000000;
CREATE SEQUENCE clue_synthetic_id_seq    START WITH 1000000;
