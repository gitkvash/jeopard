package ge.jeopard.backend.game;

import jakarta.persistence.*;

import java.io.Serializable;
import java.util.Objects;
import java.util.UUID;

/**
 * A team that already answered this clue wrong. They may not buzz on it again,
 * which is what lets the buzzer reopen fairly for the remaining teams.
 */
@Entity
@Table(name = "clue_lockout")
@IdClass(ClueLockout.Key.class)
public class ClueLockout {

    @Id
    @Column(name = "game_id")
    private UUID gameId;

    @Id
    @Column(name = "clue_id")
    private Long clueId;

    @Id
    @Column(name = "team_id")
    private UUID teamId;

    public ClueLockout() {
    }

    public ClueLockout(UUID gameId, Long clueId, UUID teamId) {
        this.gameId = gameId;
        this.clueId = clueId;
        this.teamId = teamId;
    }

    public UUID getGameId() { return gameId; }
    public void setGameId(UUID gameId) { this.gameId = gameId; }
    public Long getClueId() { return clueId; }
    public void setClueId(Long clueId) { this.clueId = clueId; }
    public UUID getTeamId() { return teamId; }
    public void setTeamId(UUID teamId) { this.teamId = teamId; }

    /** Composite primary key (game, clue, team). */
    public static class Key implements Serializable {

        private UUID gameId;
        private Long clueId;
        private UUID teamId;

        public Key() {
        }

        public Key(UUID gameId, Long clueId, UUID teamId) {
            this.gameId = gameId;
            this.clueId = clueId;
            this.teamId = teamId;
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) {
                return true;
            }
            if (!(o instanceof Key other)) {
                return false;
            }
            return Objects.equals(gameId, other.gameId)
                    && Objects.equals(clueId, other.clueId)
                    && Objects.equals(teamId, other.teamId);
        }

        @Override
        public int hashCode() {
            return Objects.hash(gameId, clueId, teamId);
        }
    }
}
