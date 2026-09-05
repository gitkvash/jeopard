package ge.jeopard.backend.game;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.List;
import java.util.UUID;

/**
 * Wire shapes for the game API.
 *
 * <p>{@link Snapshot} is what gets broadcast to every client on every state
 * change, and it is deliberately answer-free: {@link CurrentClue#answer()} is
 * only populated once the host has revealed it. A host that needs the answer in
 * order to judge fetches it separately over REST with its host token, so the
 * answer never travels on the shared topic.
 *
 * <p>{@link CurrentClue#question()} gets the same treatment when a game turns
 * off {@link Snapshot#questionsVisibleToParticipants()}: the shared payload
 * omits it, and the host's own screen fetches it separately with its token
 * (the plain snapshot GET, not a dedicated endpoint -- unlike the answer,
 * there is no reveal moment or peek penalty to model, so no need for one).
 */
public final class GameDtos {

    private GameDtos() {
    }

    // ---------- requests ----------

    /**
     * Supply {@code packageId} to play a whole package (boards 1-3 then the
     * final, scores carried across), or {@code roundId} for a single round.
     * Exactly one is required.
     */
    public record CreateGameRequest(
            Long packageId,
            Long roundId,
            boolean hostPlays,
            /* Only used when hostPlays is true. */
            @Size(max = 40) String hostTeamName,
            /* Defaults to INSTANT when absent. */
            BuzzMode buzzMode,
            /* Required for BuzzMode.TIMER, ignored otherwise. */
            Integer buzzDelaySeconds,
            /*
             * Whether a participant's own device shows the clue text at all.
             * Defaults to true (visible) when absent. The host sees the clue
             * text regardless of this -- it only ever narrows what a team sees.
             */
            Boolean questionsVisibleToParticipants) {
    }

    /**
     * A person joining. They name themselves, then either pick an existing team
     * by id or create one by giving {@code newTeamName}. Exactly one of the two
     * is required -- several players may share a team.
     */
    public record JoinRequest(
            @NotBlank @Size(min = 1, max = 40) String name,
            UUID teamId,
            @Size(max = 40) String newTeamName) {
    }

    public record SelectClueRequest(@NotNull Long clueId) {
    }

    public record JudgeRequest(boolean correct) {
    }

    public record BuzzRequest(@NotBlank String playerToken) {
    }

    public record WagerRequest(@NotBlank String playerToken, @NotNull Integer wager) {
    }

    public record FinalJudgeRequest(@NotNull UUID teamId, boolean correct) {
    }

    // ---------- responses ----------

    public record CreatedGame(
            UUID gameId,
            String joinCode,
            String hostToken,
            /* These three are present only when hostPlays is true. */
            UUID hostTeamId,
            UUID hostPlayerId,
            String hostPlayerToken) {
    }

    public record JoinedPlayer(
            UUID gameId,
            UUID playerId,
            String playerToken,
            String playerName,
            UUID teamId,
            String teamName,
            int seat) {
    }

    /** A team as offered on the join screen, so a player can pick one. */
    public record TeamOption(
            UUID id,
            String name,
            int seat,
            int score,
            List<String> memberNames) {
    }

    public record LobbyView(
            UUID gameId,
            String joinCode,
            GameState state,
            List<TeamOption> teams) {
    }

    /** Host-only payload, fetched over REST with the host token. */
    public record RevealedAnswer(
            Long clueId,
            String answer,
            String correctionNote,
            /* True when looking at this cost the playing host their buzzer. */
            boolean peekPenaltyApplied) {
    }

    public record PlayerView(
            UUID id,
            String name,
            boolean host) {
    }

    public record TeamView(
            UUID id,
            String name,
            int score,
            boolean host,
            int seat,
            Integer wager,
            boolean lockedOutOnCurrentClue,
            List<PlayerView> players) {
    }

    public record TileView(
            Long clueId,
            Integer value,
            ClueStatus status,
            UUID wonByTeamId) {
    }

    public record BoardColumn(
            Long topicId,
            Integer idx,
            String name,
            List<TileView> tiles) {
    }

    /** The clue in play. {@code answer} stays null until the host reveals it. */
    public record CurrentClue(
            Long clueId,
            String topicName,
            Integer value,
            String question,
            String answer,
            String correctionNote,
            List<UUID> lockedOutTeamIds) {
    }

    public record Snapshot(
            UUID gameId,
            String joinCode,
            GameState state,
            boolean hostPlays,
            Long roundId,
            Integer roundIdx,
            boolean finalRound,
            boolean progressRounds,
            Integer packageNumber,
            String packageTitle,
            List<TeamView> teams,
            List<BoardColumn> board,
            CurrentClue currentClue,
            UUID buzzedTeamId,
            UUID buzzedPlayerId,
            UUID pickingTeamId,
            boolean answerRevealed,
            boolean answerPeeked,
            int tilesRemaining,
            /* How this game's buzzer opens, and after how long when on a timer. */
            BuzzMode buzzMode,
            Integer buzzDelaySeconds,
            /**
             * Milliseconds left before the timer opens the buzzer, or null when
             * nothing is counting. Sent as a remaining duration rather than an
             * instant so a client with a wrong clock still counts down right.
             */
            Long buzzOpensInMs,
            /**
             * Whether a participant's own device is shown the clue text at all.
             * False only ever narrows {@link CurrentClue#question()} on this
             * shared payload -- the host still gets the text, fetched
             * separately with the host token (see {@code GameService.snapshot}).
             */
            boolean questionsVisibleToParticipants,
            long seq,
            String attribution) {
    }
}
