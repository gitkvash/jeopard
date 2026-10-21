package ge.jeopard.backend.content;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;

public interface TopicSuggestionRepository extends JpaRepository<TopicSuggestion, Long> {

    @Query("select s from TopicSuggestion s "
            + "where (:status is null or s.status = :status) "
            + "order by s.createdAt desc")
    List<TopicSuggestion> findSuggestions(@Param("status") TopicSuggestion.Status status);

    boolean existsByTopicNameIgnoreCaseAndStatus(String topicName, TopicSuggestion.Status status);

    long countBySuggesterIpAndCreatedAtAfter(String suggesterIp, Instant after);
}
