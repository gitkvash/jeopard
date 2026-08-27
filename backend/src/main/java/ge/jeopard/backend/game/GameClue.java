package ge.jeopard.backend.game;

import jakarta.persistence.*;

import java.io.Serializable;
import java.util.Objects;
import java.util.UUID;

/** Per-game state of one tile: whether it is still on the board. */
@Entity
@Table(name = "game_clue")
@IdClass(GameClue.Key.class)
public class GameClue {

    @Id
    @Column(name = "game_id")
    private UUID gameId;

    @Id
    @Column(name = "clue_id")
    private Long clueId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private ClueStatus status = ClueStatus.AVAILABLE;

    @Column(name = "won_by_team_id")
    private UUID wonByTeamId;

    public GameClue() {
    }

    public GameClue(UUID gameId, Long clueId) {
        this.gameId = gameId;
        this.clueId = clueId;
    }

    public UUID getGameId() { return gameId; }
    public void setGameId(UUID gameId) { this.gameId = gameId; }
    public Long getClueId() { return clueId; }
    public void setClueId(Long clueId) { this.clueId = clueId; }
    public ClueStatus getStatus() { return status; }
    public void setStatus(ClueStatus status) { this.status = status; }
    public UUID getWonByTeamId() { return wonByTeamId; }
    public void setWonByTeamId(UUID wonByTeamId) { this.wonByTeamId = wonByTeamId; }

    /** Composite primary key (game, clue). */
    public static class Key implements Serializable {

        private UUID gameId;
        private Long clueId;

        public Key() {
        }

        public Key(UUID gameId, Long clueId) {
            this.gameId = gameId;
            this.clueId = clueId;
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) {
                return true;
            }
            if (!(o instanceof Key other)) {
                return false;
            }
            return Objects.equals(gameId, other.gameId) && Objects.equals(clueId, other.clueId);
        }

        @Override
        public int hashCode() {
            return Objects.hash(gameId, clueId);
        }
    }
}
