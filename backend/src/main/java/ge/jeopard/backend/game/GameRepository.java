package ge.jeopard.backend.game;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

import java.util.Optional;
import java.util.UUID;

public interface GameRepository extends JpaRepository<Game, UUID> {

    Optional<Game> findByJoinCode(String joinCode);

    boolean existsByJoinCode(String joinCode);

    /**
     * SELECT ... FOR UPDATE. This is what serialises simultaneous buzzes: the
     * losers block here until the winner commits, then observe that
     * buzzedTeamId is already set and get rejected. Correctness does not depend
     * on JVM-local locking, so it survives running more than one instance.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select g from Game g where g.id = ?1")
    Optional<Game> findByIdForUpdate(UUID id);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update Game g set g.buzzedTeamId = :teamId, g.buzzedPlayerId = :playerId, g.state = :newState, g.eventSeq = g.eventSeq + 1 where g.id = :gameId and g.state = :oldState and g.buzzedTeamId is null")
    int claimBuzz(UUID gameId, UUID teamId, UUID playerId, GameState oldState, GameState newState);
}
