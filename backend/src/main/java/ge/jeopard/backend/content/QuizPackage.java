package ge.jeopard.backend.content;

import jakarta.persistence.*;
import java.util.ArrayList;
import java.util.List;

/** One authentic moazrovne.net tournament package. Read-only after seeding. */
@Entity
@Table(name = "package")
public class QuizPackage {

    @Id
    private Long id;

    @Column(nullable = false, unique = true)
    private Integer number;

    @Column(nullable = false)
    private String title;

    private String subtitle;

    @Column(name = "source_url")
    private String sourceUrl;

    @OneToMany(mappedBy = "quizPackage", cascade = CascadeType.ALL)
    @OrderBy("idx ASC")
    private List<GameRound> rounds = new ArrayList<>();

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Integer getNumber() { return number; }
    public void setNumber(Integer number) { this.number = number; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public String getSubtitle() { return subtitle; }
    public void setSubtitle(String subtitle) { this.subtitle = subtitle; }
    public String getSourceUrl() { return sourceUrl; }
    public void setSourceUrl(String sourceUrl) { this.sourceUrl = sourceUrl; }
    public List<GameRound> getRounds() { return rounds; }
}
