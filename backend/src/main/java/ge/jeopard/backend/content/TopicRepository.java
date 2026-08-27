package ge.jeopard.backend.content;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;

public interface TopicRepository extends JpaRepository<Topic, Long> {

    @Query("select distinct t from Topic t left join fetch t.clues where t.round.id = ?1 order by t.idx")
    List<Topic> findByRoundIdWithClues(Long roundId);
}
