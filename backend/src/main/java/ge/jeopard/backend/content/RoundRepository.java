package ge.jeopard.backend.content;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface RoundRepository extends JpaRepository<GameRound, Long> {

    Optional<GameRound> findByQuizPackageNumberAndIdx(Integer number, Integer idx);

    Optional<GameRound> findFirstByQuizPackageIdOrderByIdxAsc(Long packageId);

    /** The next round of a package after the given index, if there is one. */
    Optional<GameRound> findFirstByQuizPackageIdAndIdxGreaterThanOrderByIdxAsc(
            Long packageId, Integer idx);

    List<GameRound> findByQuizPackageIdOrderByIdxAsc(Long packageId);
}
