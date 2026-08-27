package ge.jeopard.backend.content;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;

public interface PackageRepository extends JpaRepository<QuizPackage, Long> {

    @Query("select distinct p from QuizPackage p join fetch p.rounds order by p.number")
    List<QuizPackage> findAllWithRounds();
}
