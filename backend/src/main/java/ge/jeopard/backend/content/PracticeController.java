package ge.jeopard.backend.content;

import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Practice: random questions, answers included, for one person on their own.
 *
 * <p>This is the one place clue text leaves the server outside a game, and it
 * is safe only because it is random and nothing else. There is no way to ask
 * for a particular clue, round or package, so it cannot be used to look up the
 * answer to a clue a game has on screen -- a player would have to draw the very
 * clue at random out of thousands.
 */
@RestController
@RequestMapping("/api/practice")
public class PracticeController {

    /** A card's worth of clue: what was asked, under which topic, and the answer. */
    public record PracticeQuestion(
            Long id,
            String topicName,
            /* Null for a final-round clue. */
            Integer value,
            boolean finalRound,
            String question,
            String answer,
            String correctionNote,
            String packageTitle) {
    }

    public record PracticeBatch(List<PracticeQuestion> questions, String attribution) {
    }

    static final int DEFAULT_COUNT = 20;
    static final int MAX_COUNT = 50;

    private final ClueRepository clues;
    private final Attribution attribution;

    PracticeController(ClueRepository clues, Attribution attribution) {
        this.clues = clues;
        this.attribution = attribution;
    }

    /**
     * A fresh random batch on every call, so never cached: a browser that kept
     * one would deal the same cards again.
     */
    @GetMapping("/questions")
    public ResponseEntity<PracticeBatch> questions(
            @RequestParam(defaultValue = "" + DEFAULT_COUNT) int count) {
        List<Long> ids = clues.randomCatalogueIds(Math.clamp(count, 1, MAX_COUNT));
        // The fetch comes back in id order; put the draw's own order back.
        Map<Long, Integer> order = new HashMap<>();
        for (int i = 0; i < ids.size(); i++) {
            order.put(ids.get(i), i);
        }
        List<PracticeQuestion> questions = clues.findWithContextByIdIn(ids).stream()
                .sorted(Comparator.comparing(c -> order.get(c.getId())))
                .map(c -> new PracticeQuestion(
                        c.getId(),
                        c.getTopic().getName(),
                        c.getValue(),
                        c.getTopic().getRound().isFinalRound(),
                        c.getQuestion(),
                        c.getAnswer(),
                        c.getCorrectionNote(),
                        c.getTopic().getRound().getQuizPackage().getTitle()))
                .toList();
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(new PracticeBatch(questions, attribution.text()));
    }
}
