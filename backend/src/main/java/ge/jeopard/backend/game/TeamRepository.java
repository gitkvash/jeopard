package ge.jeopard.backend.game;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface TeamRepository extends JpaRepository<Team, UUID> {

    List<Team> findByGameIdOrderBySeatAsc(UUID gameId);

    boolean existsByGameIdAndName(UUID gameId, String name);

    int countByGameId(UUID gameId);
}
