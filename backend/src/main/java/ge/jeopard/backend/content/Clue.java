package ge.jeopard.backend.content;

import jakarta.persistence.*;

/**
 * A single question/answer pair. {@code value} is null for final-round clues.
 * The 2008 wording is kept in {@code questionOriginal}/{@code answerOriginal}
 * wherever a correction was applied, so the edit stays auditable.
 */
@Entity
@Table(name = "clue")
public class Clue {

    @Id
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "topic_id", nullable = false)
    private Topic topic;

    private Integer value;

    @Column(nullable = false, columnDefinition = "text")
    private String question;

    @Column(nullable = false, columnDefinition = "text")
    private String answer;

    @Column(name = "question_original", columnDefinition = "text")
    private String questionOriginal;

    @Column(name = "answer_original", columnDefinition = "text")
    private String answerOriginal;

    @Column(name = "correction_note", columnDefinition = "text")
    private String correctionNote;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Topic getTopic() { return topic; }
    public void setTopic(Topic topic) { this.topic = topic; }
    public Integer getValue() { return value; }
    public void setValue(Integer value) { this.value = value; }
    public String getQuestion() { return question; }
    public void setQuestion(String question) { this.question = question; }
    public String getAnswer() { return answer; }
    public void setAnswer(String answer) { this.answer = answer; }
    public String getQuestionOriginal() { return questionOriginal; }
    public void setQuestionOriginal(String questionOriginal) { this.questionOriginal = questionOriginal; }
    public String getAnswerOriginal() { return answerOriginal; }
    public void setAnswerOriginal(String answerOriginal) { this.answerOriginal = answerOriginal; }
    public String getCorrectionNote() { return correctionNote; }
    public void setCorrectionNote(String correctionNote) { this.correctionNote = correctionNote; }
}
