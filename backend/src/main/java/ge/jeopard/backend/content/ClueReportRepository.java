package ge.jeopard.backend.content;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;

public interface ClueReportRepository extends JpaRepository<ClueReport, Long> {

    @Query("select r from ClueReport r "
            + "join fetch r.clue c "
            + "join fetch c.topic t "
            + "join fetch t.round rd "
            + "join fetch rd.quizPackage p "
            + "where (:status is null or r.status = :status) "
            + "order by r.reportedAt desc")
    List<ClueReport> findReportsWithDetails(@Param("status") ClueReport.Status status);

    boolean existsByClueIdAndReporterIpAndStatus(Long clueId, String reporterIp, ClueReport.Status status);

    long countByReporterIpAndReportedAtAfter(String reporterIp, Instant after);
}
