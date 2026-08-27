package ge.jeopard.backend.game;

/** Per-game lifecycle of a single tile. */
public enum ClueStatus {

    /** Still on the board, selectable by the host. */
    AVAILABLE,

    /** Currently being played. */
    IN_PLAY,

    /** Finished -- tile is spent and cannot be chosen again. */
    DONE
}
