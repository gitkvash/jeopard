package ge.jeopard.backend.content;

import java.time.Instant;

public class TopicSuggestionDtos {

    public record SubmitTopicSuggestionRequest(
            String topicName,
            String description,
            String authorName) {
    }

    public record SubmitTopicSuggestionResponse(
            String status,
            String message) {
    }

    public record TopicSuggestionView(
            Long id,
            String topicName,
            String description,
            String authorName,
            String status,
            String suggesterIp,
            Instant createdAt,
            String reviewNote,
            Instant reviewedAt) {

        public static TopicSuggestionView fromEntity(TopicSuggestion entity) {
            return new TopicSuggestionView(
                    entity.getId(),
                    entity.getTopicName(),
                    entity.getDescription(),
                    entity.getAuthorName(),
                    entity.getStatus().name(),
                    entity.getSuggesterIp(),
                    entity.getCreatedAt(),
                    entity.getReviewNote(),
                    entity.getReviewedAt()
            );
        }
    }

    public record ReviewTopicSuggestionRequest(String reviewNote) {
    }
}
