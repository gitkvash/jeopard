package ge.jeopard.backend.game;

import jakarta.persistence.*;

import java.time.Instant;
import java.util.UUID;

/**
 * One person on one device. Several players can sit on the same {@link Team};
 * any of them may buzz, and the resulting score goes to the team.
 *
 * <p>The bearer token lives here rather than on the team, which is what allows
 * more than one buzzer per team.
 */
@Entity
@Table(name = "player")
public class Player {

    @Id
    private UUID id;

    @Column(name = "game_id", nullable = false)
    private UUID gameId;

    @Column(name = "team_id", nullable = false)
    private UUID teamId;

    @Column(nullable = false)
    private String name;

    /** Opaque bearer for this player's own actions. Never broadcast. */
    @Column(nullable = false)
    private String token;

    /** True for the person running the game. */
    @Column(name = "is_host", nullable = false)
    private boolean host;

    @Column(name = "joined_at", nullable = false)
    private Instant joinedAt = Instant.now();

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public UUID getGameId() { return gameId; }
    public void setGameId(UUID gameId) { this.gameId = gameId; }
    public UUID getTeamId() { return teamId; }
    public void setTeamId(UUID teamId) { this.teamId = teamId; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getToken() { return token; }
    public void setToken(String token) { this.token = token; }
    public boolean isHost() { return host; }
    public void setHost(boolean host) { this.host = host; }
    public Instant getJoinedAt() { return joinedAt; }
    public void setJoinedAt(Instant joinedAt) { this.joinedAt = joinedAt; }
}
