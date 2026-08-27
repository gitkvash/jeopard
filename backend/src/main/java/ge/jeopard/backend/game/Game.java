package ge.jeopard.backend.game;

import ge.jeopard.backend.content.Clue;
import ge.jeopard.backend.content.GameRound;
import ge.jeopard.backend.content.QuizPackage;
import jakarta.persistence.*;

import java.time.Instant;
import java.util.UUID;

/**
 * One live game over a single round (one board, or one final).
 *
 * <p>Team references are stored as raw UUIDs rather than associations: the
 * game/team relationship is circular, and keeping it loose avoids ordering
 * problems on insert.
 */
@Entity
@Table(name = "game")
public class Game {

    @Id
    private UUID id;

    @Column(name = "join_code", nullable = false, unique = true, length = 6)
    private String joinCode;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "package_id", nullable = false)
    private QuizPackage quizPackage;

    /** The round currently being played; advances when progressRounds is set. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "round_id", nullable = false)
    private GameRound round;

    /**
     * True when the game walks the whole package (boards 1-3 then the final)
     * carrying scores forward, rather than playing a single round.
     */
    @Column(name = "progress_rounds", nullable = false)
    private boolean progressRounds;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private GameState state = GameState.LOBBY;

    @Column(name = "host_plays", nullable = false)
    private boolean hostPlays;

    /** Who or what opens the buzzer once a clue is up. */
    @Enumerated(EnumType.STRING)
    @Column(name = "buzz_mode", nullable = false)
    private BuzzMode buzzMode = BuzzMode.HOST;

    /** Seconds of reading time before the buzzer opens itself. TIMER only. */
    @Column(name = "buzz_delay_seconds", nullable = false)
    private int buzzDelaySeconds;

    /**
     * When the timer will open the buzzer for the clue in play, so a client
     * that joins or reconnects mid-clue can show the rest of the countdown.
     * Null in every other mode and between clues.
     */
    @Column(name = "buzz_opens_at")
    private Instant buzzOpensAt;

    @Column(name = "host_token", nullable = false)
    private String hostToken;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "current_clue_id")
    private Clue currentClue;

    @Column(name = "buzzed_team_id")
    private UUID buzzedTeamId;

    /** Which member of that team actually hit the button. */
    @Column(name = "buzzed_player_id")
    private UUID buzzedPlayerId;

    @Column(name = "answer_revealed", nullable = false)
    private boolean answerRevealed;

    /**
     * Set when a playing host looked at the answer. Costs them the buzzer for
     * that clue, which is what keeps host-plays mode honest.
     */
    @Column(name = "answer_peeked", nullable = false)
    private boolean answerPeeked;

    @Column(name = "picking_team_id")
    private UUID pickingTeamId;

    /** Monotonic per-game counter so clients can discard stale broadcasts. */
    @Column(name = "event_seq", nullable = false)
    private long eventSeq;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public String getJoinCode() { return joinCode; }
    public void setJoinCode(String joinCode) { this.joinCode = joinCode; }
    public QuizPackage getQuizPackage() { return quizPackage; }
    public void setQuizPackage(QuizPackage quizPackage) { this.quizPackage = quizPackage; }
    public boolean isProgressRounds() { return progressRounds; }
    public void setProgressRounds(boolean progressRounds) { this.progressRounds = progressRounds; }
    public GameRound getRound() { return round; }
    public void setRound(GameRound round) { this.round = round; }
    public GameState getState() { return state; }
    public void setState(GameState state) { this.state = state; }
    public boolean isHostPlays() { return hostPlays; }
    public void setHostPlays(boolean hostPlays) { this.hostPlays = hostPlays; }
    public BuzzMode getBuzzMode() { return buzzMode; }
    public void setBuzzMode(BuzzMode buzzMode) { this.buzzMode = buzzMode; }
    public int getBuzzDelaySeconds() { return buzzDelaySeconds; }
    public void setBuzzDelaySeconds(int buzzDelaySeconds) { this.buzzDelaySeconds = buzzDelaySeconds; }
    public Instant getBuzzOpensAt() { return buzzOpensAt; }
    public void setBuzzOpensAt(Instant buzzOpensAt) { this.buzzOpensAt = buzzOpensAt; }
    public String getHostToken() { return hostToken; }
    public void setHostToken(String hostToken) { this.hostToken = hostToken; }
    public Clue getCurrentClue() { return currentClue; }
    public void setCurrentClue(Clue currentClue) { this.currentClue = currentClue; }
    public UUID getBuzzedTeamId() { return buzzedTeamId; }
    public void setBuzzedTeamId(UUID buzzedTeamId) { this.buzzedTeamId = buzzedTeamId; }
    public UUID getBuzzedPlayerId() { return buzzedPlayerId; }
    public void setBuzzedPlayerId(UUID buzzedPlayerId) { this.buzzedPlayerId = buzzedPlayerId; }
    public boolean isAnswerRevealed() { return answerRevealed; }
    public void setAnswerRevealed(boolean answerRevealed) { this.answerRevealed = answerRevealed; }
    public boolean isAnswerPeeked() { return answerPeeked; }
    public void setAnswerPeeked(boolean answerPeeked) { this.answerPeeked = answerPeeked; }
    public UUID getPickingTeamId() { return pickingTeamId; }
    public void setPickingTeamId(UUID pickingTeamId) { this.pickingTeamId = pickingTeamId; }
    public long getEventSeq() { return eventSeq; }
    public void setEventSeq(long eventSeq) { this.eventSeq = eventSeq; }
    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
}
