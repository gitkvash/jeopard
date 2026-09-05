package ge.jeopard.backend.content;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;

public interface ClueRepository extends JpaRepository<Clue, Long> {

    @Query("select c from Clue c where c.topic.round.id = ?1")
    List<Clue> findByRoundId(Long roundId);

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

    @Query(value = "select nextval('clue_synthetic_id_seq') from generate_series(1, ?1)",
            nativeQuery = true)
    List<Long> nextSyntheticIds(int count);
}
