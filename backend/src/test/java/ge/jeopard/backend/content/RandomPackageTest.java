package ge.jeopard.backend.content;

import ge.jeopard.backend.content.ContentDtos.BoardView;
import ge.jeopard.backend.content.ContentDtos.PackageSummary;
import ge.jeopard.backend.content.ContentDtos.RoundSummary;
import ge.jeopard.backend.content.ContentDtos.TopicSummary;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.web.server.ResponseStatusException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
class RandomPackageTest {

    @Autowired
    private ContentService content;

    @Autowired
    private TopicRepository topicRepository;

    @Autowired
    private ClueRepository clueRepository;

    @Test
    @DisplayName("generates random package with topics and allows rerolling any topic")
    void generateAndRerollTopic() {
        PackageSummary pkg = content.generateRandomPackage();
        assertThat(pkg.synthetic()).isTrue();
        assertThat(pkg.rounds()).hasSize(4);

        // Check playable rounds have 6 topics each
        for (int i = 0; i < 3; i++) {
            RoundSummary round = pkg.rounds().get(i);
            assertThat(round.playable()).isTrue();
            assertThat(round.topics()).hasSize(6);
        }

        // Check final round has topics
        RoundSummary finalRound = pkg.rounds().get(3);
        assertThat(finalRound.finalRound()).isTrue();
        assertThat(finalRound.topics()).isNotEmpty();

        // Reroll first topic of round 1
        TopicSummary topicToChange = pkg.rounds().get(0).topics().get(0);
        String oldName = topicToChange.name();

        TopicSummary rerolled = content.rerollTopic(pkg.id(), topicToChange.id());
        assertThat(rerolled.id()).isEqualTo(topicToChange.id());
        assertThat(rerolled.idx()).isEqualTo(topicToChange.idx());
        // Verify board query works and reflects the update
        BoardView board = content.board(pkg.rounds().get(0).id());
        assertThat(board.topics().get(0).name()).isEqualTo(rerolled.name());
        assertThat(board.topics().get(0).tiles()).hasSize(5);

        // Also test rerolling final round topic
        TopicSummary finalTopic = finalRound.topics().get(0);
        TopicSummary rerolledFinal = content.rerollTopic(pkg.id(), finalTopic.id());
        assertThat(rerolledFinal.id()).isEqualTo(finalTopic.id());
        assertThat(rerolledFinal.name()).isNotBlank();
    }

    @Test
    @DisplayName("rejects reroll on non-synthetic package")
    void rejectsRerollOnCuratedPackage() {
        PackageSummary firstSeeded = content.listPackages().get(0);
        Topic topic = topicRepository.findByRoundIdWithClues(firstSeeded.rounds().get(0).id()).get(0);

        assertThatThrownBy(() -> content.rerollTopic(firstSeeded.id(), topic.getId()))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("only random package categories can be changed");
    }
}
