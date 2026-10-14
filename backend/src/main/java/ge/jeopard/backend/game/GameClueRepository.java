package ge.jeopard.backend.game;

import org.springframework.data.jpa.repository.JpaRepository;

import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface GameClueRepository extends JpaRepository<GameClue, GameClue.Key> {

    List<GameClue> findByGameId(UUID gameId);

    Optional<GameClue> findByGameIdAndClueId(UUID gameId, Long clueId);

    int countByGameIdAndStatus(UUID gameId, ClueStatus status);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from GameClue gc where gc.gameId = ?1")
    void deleteByGameId(UUID gameId);
}
