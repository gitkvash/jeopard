package ge.jeopard.backend.game;

/**
 * Server-authoritative game phases.
 *
 * <p>Board flow:
 * <pre>
 * LOBBY -> BOARD -> CLUE_READING -> BUZZ_OPEN -> BUZZED -> RESOLVED -> BOARD ... -> FINISHED
 *                                       ^                    |
 *                                       +--- judge(wrong) ---+   (next team gets a shot)
 * </pre>
 *
 * <p>Final round has no buzzer, matching the real format:
 * <pre>
 * LOBBY -> FINAL_WAGER -> FINAL_CLUE -> FINAL_RESULT -> FINISHED
 * </pre>
 */
public enum GameState {

    /** Teams are joining with the code; host has not started yet. */
    LOBBY,

    /** Host is choosing a tile. */
    BOARD,

    /** Clue text is out, buzzer deliberately still closed while the host reads it aloud. */
    CLUE_READING,

    /** Buzzer is live; the first message to win the row lock takes it. */
    BUZZ_OPEN,

    /** One team is locked in and the host is judging their spoken answer. */
    BUZZED,

    /** Clue is finished; answer may be revealed. Host advances with `next`. */
    RESOLVED,

    /** Final round: teams are entering wagers. */
    FINAL_WAGER,

    /** Final round: clue is out, teams answer, host judges each team in turn. */
    FINAL_CLUE,

    /** Final round: wagers applied, scores final. */
    FINAL_RESULT,

    /** Board exhausted (or final complete). */
    FINISHED
}
