package ge.jeopard.backend.game;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface PlayerRepository extends JpaRepository<Player, UUID> {

    Optional<Player> findByGameIdAndToken(UUID gameId, String token);

    List<Player> findByGameIdOrderByJoinedAtAsc(UUID gameId);

    List<Player> findByTeamIdOrderByJoinedAtAsc(UUID teamId);

    Optional<Player> findByIdAndGameId(UUID id, UUID gameId);

    int countByTeamId(UUID teamId);

    boolean existsByGameIdAndName(UUID gameId, String name);

    /** The host's own team, when the host is playing. */
    Optional<Player> findFirstByGameIdAndHostIsTrue(UUID gameId);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from Player p where p.gameId = ?1")
    void deleteByGameId(UUID gameId);
}
