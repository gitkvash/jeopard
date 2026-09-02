package ge.jeopard.backend.content;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;
import java.util.Optional;

public interface RoundRepository extends JpaRepository<GameRound, Long> {

    Optional<GameRound> findByQuizPackageNumberAndIdx(Integer number, Integer idx);

    Optional<GameRound> findFirstByQuizPackageIdOrderByIdxAsc(Long packageId);

    /** The next round of a package after the given index, if there is one. */
    Optional<GameRound> findFirstByQuizPackageIdAndIdxGreaterThanOrderByIdxAsc(
            Long packageId, Integer idx);

    List<GameRound> findByQuizPackageIdOrderByIdxAsc(Long packageId);

    /** Source pool for a random packet's final round: cloned whole, not remixed topic by topic. */
    @Query("select r from GameRound r where r.finalRound = true and r.quizPackage.synthetic = false")
    List<GameRound> findFinalRounds();

    @Query(value = "select nextval('round_synthetic_id_seq')", nativeQuery = true)
    Long nextSyntheticId();
}
