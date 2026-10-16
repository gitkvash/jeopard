package ge.jeopard.backend.content;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;

public interface ClueRepository extends JpaRepository<Clue, Long> {

    @Query("select c from Clue c where c.topic.round.id = ?1")
    List<Clue> findByRoundId(Long roundId);

    @org.springframework.data.jpa.repository.Modifying
    @Query("delete from Clue c where c.topic.id = ?1")
    void deleteByTopicId(Long topicId);

    @Query("select count(c) from Clue c")
    long countAll();

    /**
     * Every clue as the seeder needs to see it to decide whether the file has
     * changed: id, the value that proves ids still line up, and the two fields
     * a correction actually touches. A projection rather than the entities --
     * the answer is normally "nothing changed", and hydrating four thousand
     * rows to learn that is the wrong price for a startup check.
     */
    @Query("select c.id as id, c.value as value, c.question as question, c.answer as answer from Clue c")
    List<ClueText> findAllText();

    interface ClueText {
        Long getId();

        Integer getValue();

        String getQuestion();

        String getAnswer();
    }

    /**
     * Ids of up to {@code count} clues drawn at random from the catalogue, for
     * practice. Random packages are left out: their clues are copies of these,
     * and drawing from both would favour whatever was remixed most. So are
     * rounds that are neither a board nor a final, which no game plays either.
     * Six thousand rows sort in no time, so {@code order by random()} is enough.
     */
    @Query(value = "select c.id from clue c "
            + "join topic t on t.id = c.topic_id "
            + "join round r on r.id = t.round_id "
            + "join package p on p.id = r.package_id "
            + "where not p.synthetic and (r.playable or r.is_final) "
            + "order by random() limit ?1",
            nativeQuery = true)
    List<Long> randomCatalogueIds(int count);

    /** The clues behind {@link #randomCatalogueIds}, with what a card shows about each. */
    @Query("select c from Clue c join fetch c.topic t join fetch t.round r join fetch r.quizPackage "
            + "where c.id in ?1")
    List<Clue> findWithContextByIdIn(List<Long> ids);

    @Query(value = "select nextval('clue_synthetic_id_seq') from generate_series(1, ?1)",
            nativeQuery = true)
    List<Long> nextSyntheticIds(int count);
}
