package ge.jeopard.backend.content;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;

public interface TopicRepository extends JpaRepository<Topic, Long> {

    @Query("select distinct t from Topic t left join fetch t.clues where t.round.id = ?1 order by t.idx")
    List<Topic> findByRoundIdWithClues(Long roundId);

    /** Sampling pool for a random packet's rounds 1-3: every playable topic at that index. */
    @Query("select distinct t from Topic t left join fetch t.clues "
            + "where t.round.idx = ?1 and t.round.playable = true and t.round.quizPackage.synthetic = false")
    List<Topic> findPlayableTopicsForRoundIdx(Integer idx);

    @Query(value = "select nextval('topic_synthetic_id_seq')", nativeQuery = true)
    Long nextSyntheticId();
}
