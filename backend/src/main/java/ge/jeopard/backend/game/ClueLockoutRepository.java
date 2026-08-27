package ge.jeopard.backend.game;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;
import java.util.UUID;

public interface ClueLockoutRepository extends JpaRepository<ClueLockout, ClueLockout.Key> {

    List<ClueLockout> findByGameIdAndClueId(UUID gameId, Long clueId);

    boolean existsByGameIdAndClueIdAndTeamId(UUID gameId, Long clueId, UUID teamId);

    @Query("select l.teamId from ClueLockout l where l.gameId = ?1 and l.clueId = ?2")
    List<UUID> findTeamIds(UUID gameId, Long clueId);
}
