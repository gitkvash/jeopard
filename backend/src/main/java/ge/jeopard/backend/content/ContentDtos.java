package ge.jeopard.backend.content;

import java.util.List;

/**
 * Wire shapes for the content API.
 *
 * <p>Note what is absent: no clue {@code question} or {@code answer} text
 * appears in any board payload. Clue text only reaches a client through the
 * game API, once the host has put that specific clue into play -- or as a
 * random practice card ({@link PracticeController}), which cannot be aimed at
 * a particular clue.
 */
public final class ContentDtos {

    private ContentDtos() {
    }

    public record PackageSummary(
            Long id,
            Integer number,
            String title,
            String subtitle,
            String sourceUrl,
            boolean synthetic,
            List<RoundSummary> rounds) {
    }

    public record RoundSummary(
            Long id,
            Integer idx,
            String header,
            boolean finalRound,
            boolean playable,
            Integer topicCount,
            List<TopicSummary> topics) {
    }

    public record TopicSummary(
            Long id,
            Integer idx,
            String name) {
    }

    /** The 6x5 grid the host sees: topic names and tile values, nothing more. */
    public record BoardView(
            Long roundId,
            Integer roundIdx,
            boolean finalRound,
            Integer packageNumber,
            String packageTitle,
            List<BoardTopic> topics) {
    }

    public record BoardTopic(
            Long id,
            Integer idx,
            String name,
            List<BoardTile> tiles) {
    }

    public record BoardTile(
            Long clueId,
            Integer value) {
    }
}
