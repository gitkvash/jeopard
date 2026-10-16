package ge.jeopard.backend.game;

import ge.jeopard.backend.content.ContentDtos.PackageSummary;
import ge.jeopard.backend.content.ContentService;
import ge.jeopard.backend.game.GameDtos.BoardColumn;
import ge.jeopard.backend.game.GameDtos.CreateGameRequest;
import ge.jeopard.backend.game.GameDtos.CreatedGame;
import ge.jeopard.backend.game.GameDtos.Snapshot;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.web.server.ResponseStatusException;


import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Changing a category of a random package while the game is under way. */
@SpringBootTest
class RerollInGameTest {

    @Autowired
    GameService games;

    @Autowired
    ContentService content;

    private CreatedGame created;

    @AfterEach
    void cleanUp() {
        if (created != null) {
            try {
                games.deleteGame(created.gameId(), created.hostToken());
            } catch (RuntimeException ignored) {
                // already gone
            }
        }
    }

    private Snapshot startRandomGame() {
        PackageSummary pkg = content.generateRandomPackage();
        created = games.createGame(new CreateGameRequest(
                pkg.id(), null, true, null, BuzzMode.HOST, null, true, null, null));
        return games.start(created.gameId(), created.hostToken());
    }

    @Test
    @DisplayName("an untouched category is swapped, and the rest of the board keeps its state")
    void swapsAnUntouchedCategory() {
        Snapshot board = startRandomGame();
        BoardColumn played = board.board().get(0);
        BoardColumn untouched = board.board().get(1);

        // Spend a tile in the first column.
        games.selectClue(created.gameId(), created.hostToken(), played.tiles().get(0).clueId());
        games.passClue(created.gameId(), created.hostToken());
        Snapshot next = games.next(created.gameId(), created.hostToken());

        Snapshot after = games.rerollTopic(created.gameId(), created.hostToken(), untouched.topicId());

        BoardColumn swapped = after.board().get(1);
        assertThat(swapped.topicId()).isEqualTo(untouched.topicId());
        assertThat(swapped.tiles()).hasSize(5);
        assertThat(swapped.tiles()).allMatch(t -> t.status() == ClueStatus.AVAILABLE);
        // The new tiles are real clues of this game: one can be picked and played.
        assertThat(swapped.tiles().get(0).clueId()).isNotEqualTo(untouched.tiles().get(0).clueId());

        // The column that had been played from is exactly as it was.
        assertThat(after.board().get(0).tiles().get(0).status()).isEqualTo(ClueStatus.DONE);
        assertThat(after.tilesRemaining()).isEqualTo(next.tilesRemaining());

        Snapshot picked = games.selectClue(created.gameId(), created.hostToken(),
                swapped.tiles().get(0).clueId());
        assertThat(picked.currentClue()).isNotNull();
    }

    @Test
    @DisplayName("a category that has been played from cannot be changed")
    void refusesAPlayedCategory() {
        Snapshot board = startRandomGame();
        BoardColumn played = board.board().get(0);
        games.selectClue(created.gameId(), created.hostToken(), played.tiles().get(0).clueId());
        games.passClue(created.gameId(), created.hostToken());
        games.next(created.gameId(), created.hostToken());

        assertThatThrownBy(() -> games.rerollTopic(
                created.gameId(), created.hostToken(), played.topicId()))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("already been played");
    }

    @Test
    @DisplayName("only the host may change a category, and only one on this board")
    void guardsTheRequest() {
        Snapshot board = startRandomGame();
        Long topicId = board.board().get(0).topicId();

        assertThatThrownBy(() -> games.rerollTopic(created.gameId(), "not-the-token", topicId))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("host token");
        assertThatThrownBy(() -> games.rerollTopic(created.gameId(), created.hostToken(), -42L))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("not on this board");
    }

    @Test
    @DisplayName("a curated package's categories cannot be changed")
    void refusesACuratedPackage() {
        PackageSummary curated = content.listPackages().get(0);
        created = games.createGame(new CreateGameRequest(
                curated.id(), null, true, null, BuzzMode.HOST, null, true, null, null));
        Snapshot board = games.start(created.gameId(), created.hostToken());

        assertThatThrownBy(() -> games.rerollTopic(
                created.gameId(), created.hostToken(), board.board().get(0).topicId()))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("only random package categories");
    }
}
