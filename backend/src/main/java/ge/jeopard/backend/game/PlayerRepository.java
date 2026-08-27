package ge.jeopard.backend.game;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface PlayerRepository extends JpaRepository<Player, UUID> {

    Optional<Player> findByGameIdAndToken(UUID gameId, String token);

    List<Player> findByGameIdOrderByJoinedAtAsc(UUID gameId);

    List<Player> findByTeamIdOrderByJoinedAtAsc(UUID teamId);

    boolean existsByGameIdAndName(UUID gameId, String name);

    /** The host's own team, when the host is playing. */
    Optional<Player> findFirstByGameIdAndHostIsTrue(UUID gameId);
}
