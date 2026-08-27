package ge.jeopard.backend.game;

/**
 * How the buzzer goes live once a clue is on the screen.
 *
 * <p>The choice is the host's, made when the game is created, and the server
 * enforces it: a buzz is only ever accepted in {@link GameState#BUZZ_OPEN}, so
 * whichever of these opens it, it opens on the server rather than on a client
 * that decided its own countdown had finished.
 */
public enum BuzzMode {

    /** The host presses the button when they have finished reading aloud. */
    HOST,

    /** Live the moment the clue appears -- fastest finger from the first word. */
    INSTANT,

    /**
     * Live by itself after {@link Game#getBuzzDelaySeconds()} seconds, which is
     * how a game runs with nobody minding the console.
     */
    TIMER
}
