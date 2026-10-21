package ge.jeopard.backend.content;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "topic_suggestion")
public class TopicSuggestion {

    public enum Status {
        PENDING,
        APPROVED,
        REJECTED
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "topic_name", nullable = false, columnDefinition = "text")
    private String topicName;

    @Column(columnDefinition = "text")
    private String description;

    @Column(name = "author_name", length = 128)
    private String authorName;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    private Status status = Status.PENDING;

    @Column(name = "suggester_ip", nullable = false, length = 64)
    private String suggesterIp;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "review_note", columnDefinition = "text")
    private String reviewNote;

    @Column(name = "reviewed_at")
    private Instant reviewedAt;

    public TopicSuggestion() {
    }

    public TopicSuggestion(String topicName, String description, String authorName, String suggesterIp) {
        this.topicName = topicName;
        this.description = description;
        this.authorName = authorName;
        this.suggesterIp = suggesterIp;
        this.status = Status.PENDING;
        this.createdAt = Instant.now();
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getTopicName() {
        return topicName;
    }

    public void setTopicName(String topicName) {
        this.topicName = topicName;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public String getAuthorName() {
        return authorName;
    }

    public void setAuthorName(String authorName) {
        this.authorName = authorName;
    }

    public Status getStatus() {
        return status;
    }

    public void setStatus(Status status) {
        this.status = status;
    }

    public String getSuggesterIp() {
        return suggesterIp;
    }

    public void setSuggesterIp(String suggesterIp) {
        this.suggesterIp = suggesterIp;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public String getReviewNote() {
        return reviewNote;
    }

    public void setReviewNote(String reviewNote) {
        this.reviewNote = reviewNote;
    }

    public Instant getReviewedAt() {
        return reviewedAt;
    }

    public void setReviewedAt(Instant reviewedAt) {
        this.reviewedAt = reviewedAt;
    }
}
