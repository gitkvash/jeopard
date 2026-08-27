package ge.jeopard.backend.content;

import jakarta.persistence.*;
import java.util.ArrayList;
import java.util.List;

/** A board column: one category with its clues. */
@Entity
@Table(name = "topic")
public class Topic {

    @Id
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "round_id", nullable = false)
    private GameRound round;

    @Column(nullable = false)
    private Integer idx;

    @Column(nullable = false)
    private String name;

    @OneToMany(mappedBy = "topic", cascade = CascadeType.ALL)
    @OrderBy("value ASC")
    private List<Clue> clues = new ArrayList<>();

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public GameRound getRound() { return round; }
    public void setRound(GameRound round) { this.round = round; }
    public Integer getIdx() { return idx; }
    public void setIdx(Integer idx) { this.idx = idx; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public List<Clue> getClues() { return clues; }
}
