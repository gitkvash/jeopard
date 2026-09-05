package ge.jeopard.backend.content;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.Collection;
import java.util.List;

public interface TopicRepository extends JpaRepository<Topic, Long> {

    @Query("select distinct t from Topic t left join fetch t.clues where t.round.id = ?1 order by t.idx")
    List<Topic> findByRoundIdWithClues(Long roundId);

    /**
     * Sampling pool for a random packet's rounds 1-3: id and name only, for
     * every playable topic up to {@code maxRoundIdx}.
     *
     * <p>Deliberately not the entities. Choosing six topics per round used to
     * fetch every candidate topic <em>with its clues</em> -- some four thousand
     * rows hydrated into the persistence context, and then dirty-checked at
     * flush -- to end up copying thirty of them. Names are all the choice needs;
     * the six that win are loaded whole afterwards.
     */
    @Query("select t.round.idx as roundIdx, t.id as id, t.name as name from Topic t "
            + "where t.round.idx <= ?1 and t.round.playable = true "
            + "and t.round.quizPackage.synthetic = false")
    List<TopicRef> findPlayableTopicRefs(Integer maxRoundIdx);

    /** The topics of one round, id only -- the final round's sampling step. */
    @Query("select t.id from Topic t where t.round.id = ?1 order by t.idx")
    List<Long> findIdsByRoundId(Long roundId);

    /** The chosen topics, clues included: one query for a whole random packet. */
    @Query("select distinct t from Topic t left join fetch t.clues where t.id in ?1")
    List<Topic> findAllWithCluesByIdIn(Collection<Long> ids);

    @Query(value = "select nextval('topic_synthetic_id_seq') from generate_series(1, ?1)",
            nativeQuery = true)
    List<Long> nextSyntheticIds(int count);

    /** A candidate topic as the sampler sees it: which board, which id, what name. */
    interface TopicRef {
        Integer getRoundIdx();

        Long getId();

        String getName();
    }
}
