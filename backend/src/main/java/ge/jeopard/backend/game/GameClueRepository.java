package ge.jeopard.backend.game;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface GameClueRepository extends JpaRepository<GameClue, GameClue.Key> {

    List<GameClue> findByGameId(UUID gameId);

    Optional<GameClue> findByGameIdAndClueId(UUID gameId, Long clueId);

    int countByGameIdAndStatus(UUID gameId, ClueStatus status);
}
