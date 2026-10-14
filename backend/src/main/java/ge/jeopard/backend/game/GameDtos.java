package ge.jeopard.backend.game;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
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
            Boolean questionsVisibleToParticipants,
            /*
             * True to let the players choose the tile in turn, a team (or a solo
             * player) at a time. Defaults to false: the host chooses. The host
             * may choose at any time either way.
             */
            Boolean playersPickClues) {
    }

    /**
     * A person joining. They name themselves, then either pick an existing team
     * by id, create one by giving {@code newTeamName}, or give neither and play
     * on their own. Supplying both is refused -- several players may share a
     * team, but a request cannot be for two of them.
     */
    public record JoinRequest(
            @NotBlank @Size(min = 1, max = 40) String name,
            UUID teamId,
            @Size(max = 40) String newTeamName) {
    }

    /**
     * A player moving themselves, before the game starts. Same three choices as
     * {@link JoinRequest}: an existing team, a new one, or neither -- which
     * leaves them on their own.
     */
    public record ChangeTeamRequest(
            @NotBlank String playerToken,
            UUID teamId,
            @Size(max = 40) String newTeamName) {
    }

    /** A player voluntarily leaving the game. */
    public record LeaveRequest(
            @NotBlank String playerToken) {
    }

    /** The host moving someone. Same three choices; the host needs no token of the player's. */
    public record MovePlayerRequest(
            UUID teamId,
            @Size(max = 40) String newTeamName) {
    }

    /**
     * The score a team should now have. Set outright rather than adjusted by an
     * amount, so a host who mistyped sees exactly what they typed and fixing it is
     * typing the right number. The bound is only there to refuse a slipped key.
     */
    public record SetScoreRequest(
            @NotNull @Min(-1_000_000) @Max(1_000_000) Integer score) {
    }

    public record SelectClueRequest(@NotNull Long clueId) {
    }

    /** A player choosing the tile on their team's turn. */
    public record PickClueRequest(@NotBlank String playerToken, @NotNull Long clueId) {
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
            int seat,
            /* True when the player chose to play without a team. */
            boolean solo) {
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
            List<PlayerView> players,
            /* A player who chose to play alone; named after them. */
            boolean solo) {
    }

    /**
     * Something the host did that everybody should hear about. Sent once on its
     * own topic rather than carried in the snapshot: a snapshot is state, and
     * replaying this to a phone that reconnects an hour later would announce a
     * score change that nobody remembers. Fields that do not apply are null.
     */
    public record Notice(
            /* SCORE_CHANGED, PLAYER_MOVED, or GAME_TERMINATED. */
            String kind,
            /* The team whose score changed. */
            String teamName,
            Integer scoreBefore,
            Integer scoreAfter,
            /* The player who was moved, and where from / to. A null team name is "on their own". */
            UUID playerId,
            String playerName,
            String fromTeamName,
            String toTeamName) {

        public static Notice gameTerminated() {
            return new Notice("GAME_TERMINATED", null, null, null, null, null, null, null);
        }
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
            /**
             * True when the players choose the tile in turn. Then
             * {@link #pickingTeamId()} is the team whose turn it is, and any
             * member of it may pick; the host may pick regardless.
             */
            boolean playersPickClues,
            long seq,
            String attribution) {
    }
}
