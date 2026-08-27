package ge.jeopard.backend.content;

import jakarta.persistence.*;
import java.util.ArrayList;
import java.util.List;

/**
 * One round of a package. Rounds 1-3 are playable 6x5 boards; round 4 is the
 * final (2 topics, 1 clue each, no value).
 */
@Entity
@Table(name = "round")
public class GameRound {

    @Id
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "package_id", nullable = false)
    private QuizPackage quizPackage;

    @Column(nullable = false)
    private Integer idx;

    private String header;

    /** Named "finalRound" rather than "final" so it is a valid bean property. */
    @Column(name = "is_final", nullable = false)
    private boolean finalRound;

    @Column(name = "topic_count", nullable = false)
    private Integer topicCount;

    /** True only for a complete 6 topics x 5 clues board. */
    @Column(nullable = false)
    private boolean playable;

    @OneToMany(mappedBy = "round", cascade = CascadeType.ALL)
    @OrderBy("idx ASC")
    private List<Topic> topics = new ArrayList<>();

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public QuizPackage getQuizPackage() { return quizPackage; }
    public void setQuizPackage(QuizPackage quizPackage) { this.quizPackage = quizPackage; }
    public Integer getIdx() { return idx; }
    public void setIdx(Integer idx) { this.idx = idx; }
    public String getHeader() { return header; }
    public void setHeader(String header) { this.header = header; }
    public boolean isFinalRound() { return finalRound; }
    public void setFinalRound(boolean finalRound) { this.finalRound = finalRound; }
    public Integer getTopicCount() { return topicCount; }
    public void setTopicCount(Integer topicCount) { this.topicCount = topicCount; }
    public boolean isPlayable() { return playable; }
    public void setPlayable(boolean playable) { this.playable = playable; }
    public List<Topic> getTopics() { return topics; }
}
