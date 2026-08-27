package ge.jeopard.backend.content;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;

public interface ClueRepository extends JpaRepository<Clue, Long> {

    @Query("select c from Clue c where c.topic.round.id = ?1")
    List<Clue> findByRoundId(Long roundId);

    @Query("select count(c) from Clue c")
    long countAll();
}
