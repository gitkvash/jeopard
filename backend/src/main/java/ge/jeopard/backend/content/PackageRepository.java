package ge.jeopard.backend.content;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;

public interface PackageRepository extends JpaRepository<QuizPackage, Long> {

    @Query("select distinct p from QuizPackage p join fetch p.rounds where p.synthetic = false order by p.number")
    List<QuizPackage> findAllWithRounds();

    /** What the seeder already has, so it can add only what is missing. */
    @Query("select p.id from QuizPackage p")
    List<Long> findAllIds();

    @Query(value = "select nextval('package_synthetic_id_seq')", nativeQuery = true)
    Long nextSyntheticId();
}
