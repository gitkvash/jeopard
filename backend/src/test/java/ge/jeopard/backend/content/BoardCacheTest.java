package ge.jeopard.backend.content;

import ge.jeopard.backend.content.ContentDtos.BoardTopic;
import ge.jeopard.backend.content.ContentDtos.BoardView;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The board cache is bounded, and a board that falls out of it comes back the
 * same.
 *
 * <p>The bound is set to three here because the real one is larger than the
 * number of rounds a test database holds, so nothing would ever be evicted at
 * its default and the eviction path would go unexercised.
 */
@SpringBootTest
@TestPropertySource(properties = "jeopard.board-cache.size=3")
class BoardCacheTest {

    @Autowired
    ContentService content;

    @Test
    @DisplayName("a board evicted from the cache is rebuilt identically")
    void evictedBoardsComeBackTheSame() {
        List<Long> roundIds = firstPlayableRounds(8);
        assertThat(roundIds).as("needs several rounds to overflow a cache of 3").hasSize(8);

        BoardView first = content.board(roundIds.get(0));

        // Walk past the bound, so the first board is certainly gone.
        for (Long id : roundIds) {
            content.board(id);
        }

        BoardView rebuilt = content.board(roundIds.get(0));
        assertThat(rebuilt).isNotSameAs(first);
        assertThat(describe(rebuilt))
                .as("a cache miss must not change what a board is")
                .isEqualTo(describe(first));
    }

    @Test
    @DisplayName("boards stay correct when rooms ask for them at the same moment")
    void concurrentReadersGetTheirOwnBoard() throws Exception {
        List<Long> roundIds = firstPlayableRounds(6);
        List<BoardView> expected = roundIds.stream().map(content::board).toList();

        // More racers than the cache holds, so they evict each other's entries
        // while reading -- which is what a house full of rooms does to it.
        int racers = roundIds.size() * 4;
        CyclicBarrier barrier = new CyclicBarrier(racers);
        try (ExecutorService pool = Executors.newFixedThreadPool(racers)) {
            List<Future<Boolean>> futures = new ArrayList<>();
            for (int i = 0; i < racers; i++) {
                int which = i % roundIds.size();
                futures.add(pool.submit(() -> {
                    barrier.await(20, TimeUnit.SECONDS);
                    BoardView got = content.board(roundIds.get(which));
                    return describe(got).equals(describe(expected.get(which)));
                }));
            }
            for (Future<Boolean> f : futures) {
                assertThat(f.get(30, TimeUnit.SECONDS))
                        .as("every reader should get the board it asked for")
                        .isTrue();
            }
        }
    }

    /** Round ids of the first playable boards in the catalogue. */
    private List<Long> firstPlayableRounds(int count) {
        return content.listPackages().stream()
                .flatMap(p -> p.rounds().stream())
                .filter(ContentDtos.RoundSummary::playable)
                .limit(count)
                .map(ContentDtos.RoundSummary::id)
                .toList();
    }

    /** Everything a board is, flattened, so two of them can be compared. */
    private static String describe(BoardView board) {
        StringBuilder sb = new StringBuilder()
                .append(board.roundId()).append('/')
                .append(board.roundIdx()).append('/')
                .append(board.finalRound()).append('/')
                .append(board.packageNumber()).append('/')
                .append(board.packageTitle());
        for (BoardTopic topic : board.topics()) {
            sb.append('|').append(topic.id()).append(':').append(topic.name());
            topic.tiles().forEach(t -> sb.append(',').append(t.clueId()).append('=').append(t.value()));
        }
        return sb.toString();
    }
}
