package ge.jeopard.backend.game;

import jakarta.persistence.*;

import java.time.Instant;
import java.util.UUID;

/**
 * The scoring unit. One or more {@link Player}s belong to a team; the team
 * carries the score, the final-round wager, and the per-clue lockout.
 */
@Entity
@Table(name = "team")
public class Team {

    @Id
    private UUID id;

    @Column(name = "game_id", nullable = false)
    private UUID gameId;

    @Column(nullable = false)
    private String name;

    @Column(nullable = false)
    private int score;

    /** Join order; used for stable display and final-round judging order. */
    @Column(nullable = false)
    private int seat;

    /** Final round only. */
    private Integer wager;

    /**
     * A team of one, made for a player who chose not to sit with anyone. It is
     * named after the player, is never offered on the join list, and goes away
     * when the player leaves it.
     */
    @Column(nullable = false)
    private boolean solo;

    @Column(name = "joined_at", nullable = false)
    private Instant joinedAt = Instant.now();

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public UUID getGameId() { return gameId; }
    public void setGameId(UUID gameId) { this.gameId = gameId; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public int getScore() { return score; }
    public void setScore(int score) { this.score = score; }
    public int getSeat() { return seat; }
    public void setSeat(int seat) { this.seat = seat; }
    public boolean isSolo() { return solo; }
    public void setSolo(boolean solo) { this.solo = solo; }
    public Integer getWager() { return wager; }
    public void setWager(Integer wager) { this.wager = wager; }
    public Instant getJoinedAt() { return joinedAt; }
    public void setJoinedAt(Instant joinedAt) { this.joinedAt = joinedAt; }
}
