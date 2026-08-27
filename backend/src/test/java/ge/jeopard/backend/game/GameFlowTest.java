package ge.jeopard.backend.game;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * End-to-end cover for the buzzer rules.
 *
 * <p>Uses the JDK HTTP client rather than a Spring test client: Boot 4 removed
 * TestRestTemplate, and driving real sockets is the only way to get genuinely
 * concurrent buzzes, which is the one thing here that could silently break.
 *
 * <p>Needs the dev Postgres up (docker compose up -d). Content is seeded on
 * first start and the seeder is idempotent, so repeated runs are fine.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class GameFlowTest {

    private static final String HOST_TOKEN = "X-Host-Token";

    @LocalServerPort
    int port;

    @Autowired
    ObjectMapper mapper;

    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    // ------------------------------------------------------------------
    // content
    // ------------------------------------------------------------------

    @Test
    @DisplayName("every seeded package is served with three boards and a final")
    void packagesAreSeeded() throws Exception {
        JsonNode packages = get("/api/packages").body();

        // The six 2008 originals are the floor, not the ceiling: generated
        // packages are appended after them (see src/merge_packets.py), so this
        // pins the shape every package must have rather than how many there are.
        assertThat(packages).hasSizeGreaterThanOrEqualTo(6);
        for (JsonNode pkg : packages) {
            List<JsonNode> rounds = new ArrayList<>();
            pkg.path("rounds").forEach(rounds::add);
            assertThat(rounds).hasSize(4);
            assertThat(rounds.stream().filter(r -> r.path("playable").asBoolean()).count())
                    .isEqualTo(3);
            assertThat(rounds.stream().filter(r -> r.path("finalRound").asBoolean()).count())
                    .isEqualTo(1);
        }
    }

    @Test
    @DisplayName("a board exposes tile values but never the clue text")
    void boardDoesNotLeakClueText() throws Exception {
        Response res = get("/api/rounds/1/board");
        JsonNode board = res.body();

        assertThat(board.path("topics")).hasSize(6);
        for (JsonNode topic : board.path("topics")) {
            assertThat(topic.path("tiles")).hasSize(5);
        }
        // The whole payload, not just the fields we happen to check.
        assertThat(res.raw()).doesNotContain("question").doesNotContain("answer");
    }

    // ------------------------------------------------------------------
    // the rule the game hinges on
    // ------------------------------------------------------------------

    @Test
    @DisplayName("wrong answer deducts, locks that team out, and reopens the buzzer for the rest")
    void wrongAnswerHandsTheBuzzerToTheNextTeam() throws Exception {
        Game game = newGame();
        String teamA = game.join("გუნდი ა");
        String teamB = game.join("გუნდი ბ");

        JsonNode snap = game.host("start", null).body();
        assertThat(snap.path("state").asString()).isEqualTo("BOARD");
        assertThat(snap.path("tilesRemaining").asInt()).isEqualTo(30);

        long clueId = firstTileValued(snap, 30);
        snap = game.host("select-clue", "{\"clueId\":" + clueId + "}").body();
        assertThat(snap.path("state").asString()).isEqualTo("CLUE_READING");
        assertThat(snap.path("currentClue").path("question").asString()).isNotBlank();
        assertThat(snap.path("currentClue").path("answer").isNull()).isTrue();

        // Buzzing before the host opens the buzzer is refused.
        assertThat(game.buzz(teamA).status()).isEqualTo(409);

        game.host("open-buzzer", null);
        assertThat(game.buzz(teamA).status()).isEqualTo(200);

        snap = game.host("judge", "{\"correct\":false}").body();
        assertThat(snap.path("state").asString()).isEqualTo("BUZZ_OPEN");
        assertThat(scoreOf(snap, "გუნდი ა")).isEqualTo(-30);
        assertThat(lockedOut(snap, "გუნდი ა")).isTrue();
        assertThat(lockedOut(snap, "გუნდი ბ")).isFalse();

        // The team that got it wrong may not buzz again on this clue...
        assertThat(game.buzz(teamA).status()).isEqualTo(409);
        // ...but the other one can, which is the whole point.
        assertThat(game.buzz(teamB).status()).isEqualTo(200);

        snap = game.host("judge", "{\"correct\":true}").body();
        assertThat(snap.path("state").asString()).isEqualTo("RESOLVED");
        assertThat(scoreOf(snap, "გუნდი ბ")).isEqualTo(30);
        assertThat(snap.path("currentClue").path("answer").asString()).isNotBlank();

        snap = game.host("next", null).body();
        assertThat(snap.path("state").asString()).isEqualTo("BOARD");
        assertThat(snap.path("tilesRemaining").asInt()).isEqualTo(29);

        // A spent tile cannot come back.
        assertThat(game.hostRaw("select-clue", "{\"clueId\":" + clueId + "}").status())
                .isEqualTo(409);
    }

    @Test
    @DisplayName("simultaneous buzzes produce exactly one winner")
    void concurrentBuzzesYieldOneWinner() throws Exception {
        Game game = newGame();
        List<String> tokens = new ArrayList<>();
        for (int i = 0; i < 6; i++) {
            tokens.add(game.join("გუნდი " + i));
        }
        JsonNode snap = game.host("start", null).body();
        long clueId = firstTileValued(snap, 10);
        game.host("select-clue", "{\"clueId\":" + clueId + "}");
        game.host("open-buzzer", null);

        // Every thread parks on the barrier, so the requests really do overlap.
        int racers = tokens.size() * 3;
        CyclicBarrier barrier = new CyclicBarrier(racers);
        AtomicInteger accepted = new AtomicInteger();
        AtomicInteger rejected = new AtomicInteger();

        try (ExecutorService pool = Executors.newFixedThreadPool(racers)) {
            List<Future<?>> futures = new ArrayList<>();
            for (int i = 0; i < racers; i++) {
                String token = tokens.get(i % tokens.size());
                futures.add(pool.submit(() -> {
                    barrier.await(20, TimeUnit.SECONDS);
                    int status = game.buzz(token).status();
                    if (status == 200) {
                        accepted.incrementAndGet();
                    } else {
                        rejected.incrementAndGet();
                    }
                    return null;
                }));
            }
            for (Future<?> f : futures) {
                f.get(30, TimeUnit.SECONDS);
            }
        }

        assertThat(accepted.get())
                .as("exactly one of %d simultaneous buzzes should win", racers)
                .isEqualTo(1);
        assertThat(rejected.get()).isEqualTo(racers - 1);

        JsonNode after = get("/api/games/" + game.id).body();
        assertThat(after.path("state").asString()).isEqualTo("BUZZED");
        assertThat(after.path("buzzedTeamId").isNull()).isFalse();
    }

    @Test
    @DisplayName("host-only endpoints reject a bad token and never expose the answer publicly")
    void hostTokenGuardsTheAnswer() throws Exception {
        Game game = newGame();
        game.join("გუნდი ა");
        JsonNode snap = game.host("start", null).body();
        long clueId = firstTileValued(snap, 20);
        game.host("select-clue", "{\"clueId\":" + clueId + "}");

        // Wrong token is refused.
        HttpResponse<byte[]> bad = http.send(
                HttpRequest.newBuilder(uri("/api/games/" + game.id + "/open-buzzer"))
                        .header(HOST_TOKEN, "not-the-token")
                        .header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.noBody())
                        .build(),
                HttpResponse.BodyHandlers.ofByteArray());
        assertThat(bad.statusCode()).isEqualTo(403);

        // The host can read the answer...
        Response peek = game.hostRaw("peek", null);
        assertThat(peek.status()).isEqualTo(200);
        assertThat(peek.body().path("answer").asString()).isNotBlank();
        // ...and this game has a non-playing host, so there is no penalty.
        assertThat(peek.body().path("peekPenaltyApplied").asBoolean()).isFalse();

        // ...but the public snapshot still withholds it.
        JsonNode publicSnap = get("/api/games/" + game.id).body();
        assertThat(publicSnap.path("currentClue").path("answer").isNull()).isTrue();
    }

    @Test
    @DisplayName("a playing host who looks at the answer loses the buzzer for that clue")
    void peekingCostsAPlayingHostTheBuzzer() throws Exception {
        Response created = post("/api/games", "{\"roundId\":1,\"hostPlays\":true}", null);
        JsonNode body = created.body();
        Game game = new Game(body.path("gameId").asString(),
                body.path("joinCode").asString(),
                body.path("hostToken").asString());
        String hostPlayerToken = body.path("hostPlayerToken").asString();
        assertThat(hostPlayerToken).isNotBlank();

        game.join("გუნდი ა");
        JsonNode snap = game.host("start", null).body();
        long clueId = firstTileValued(snap, 10);
        game.host("select-clue", "{\"clueId\":" + clueId + "}");
        game.host("open-buzzer", null);

        // Before peeking the playing host may buzz like anyone else.
        assertThat(game.buzz(hostPlayerToken).status()).isEqualTo(200);
        game.host("judge", "{\"correct\":false}");

        Response peek = game.hostRaw("peek", null);
        assertThat(peek.body().path("peekPenaltyApplied").asBoolean()).isTrue();

        JsonNode after = get("/api/games/" + game.id).body();
        assertThat(after.path("answerPeeked").asBoolean()).isTrue();
    }

    // ------------------------------------------------------------------
    // who opens the buzzer
    // ------------------------------------------------------------------

    @Test
    @DisplayName("an instant game puts the clue up with the buzzer already open")
    void instantModeOpensWithTheClue() throws Exception {
        Game game = newGame("{\"roundId\":1,\"hostPlays\":false,\"buzzMode\":\"INSTANT\"}");
        String team = game.join("გუნდი ა");

        JsonNode snap = game.host("start", null).body();
        long clueId = firstTileValued(snap, 10);
        snap = game.host("select-clue", "{\"clueId\":" + clueId + "}").body();

        // No reading state at all: the clue and the buzzer arrive together.
        assertThat(snap.path("state").asString()).isEqualTo("BUZZ_OPEN");
        assertThat(snap.path("buzzMode").asString()).isEqualTo("INSTANT");
        assertThat(snap.path("buzzOpensInMs").isNull()).isTrue();
        assertThat(game.buzz(team).status()).isEqualTo(200);
    }

    @Test
    @DisplayName("a timed game opens its own buzzer when the reading time runs out")
    void timerModeOpensItself() throws Exception {
        Game game = newGame(
                "{\"roundId\":1,\"hostPlays\":false,\"buzzMode\":\"TIMER\",\"buzzDelaySeconds\":1}");
        String team = game.join("გუნდი ა");

        JsonNode snap = game.host("start", null).body();
        long clueId = firstTileValued(snap, 10);
        snap = game.host("select-clue", "{\"clueId\":" + clueId + "}").body();

        // Still closed, and saying how long is left rather than when it is due,
        // so a client with a wrong clock counts the same seconds as the server.
        assertThat(snap.path("state").asString()).isEqualTo("CLUE_READING");
        assertThat(snap.path("buzzDelaySeconds").asInt()).isEqualTo(1);
        assertThat(snap.path("buzzOpensInMs").asLong()).isBetween(1L, 1000L);
        assertThat(game.buzz(team).status()).isEqualTo(409);

        JsonNode opened = awaitState(game, "BUZZ_OPEN");
        assertThat(opened.path("buzzOpensInMs").isNull()).isTrue();
        assertThat(game.buzz(team).status()).isEqualTo(200);
    }

    @Test
    @DisplayName("a timer that has been overtaken does nothing when it goes off")
    void timerDoesNotDisturbAClueThatMovedOn() throws Exception {
        Game game = newGame(
                "{\"roundId\":1,\"hostPlays\":false,\"buzzMode\":\"TIMER\",\"buzzDelaySeconds\":1}");
        String team = game.join("გუნდი ა");

        JsonNode snap = game.host("start", null).body();
        long clueId = firstTileValued(snap, 10);
        game.host("select-clue", "{\"clueId\":" + clueId + "}");

        // The host does not wait for the timer, and a team buzzes straight away.
        snap = game.host("open-buzzer", null).body();
        assertThat(snap.path("buzzOpensInMs").isNull()).isTrue();
        assertThat(game.buzz(team).status()).isEqualTo(200);

        // The timer is still out there and goes off about now. It must not
        // reopen the buzzer under the team already answering.
        Thread.sleep(1500);
        JsonNode after = get("/api/games/" + game.id).body();
        assertThat(after.path("state").asString()).isEqualTo("BUZZED");
    }

    @Test
    @DisplayName("an automatic buzzer with no usable delay is refused outright")
    void timerModeNeedsADelay() throws Exception {
        assertThat(post("/api/games",
                "{\"roundId\":1,\"hostPlays\":false,\"buzzMode\":\"TIMER\"}", null).status())
                .isEqualTo(400);
        assertThat(post("/api/games",
                "{\"roundId\":1,\"hostPlays\":false,\"buzzMode\":\"TIMER\",\"buzzDelaySeconds\":0}",
                null).status())
                .isEqualTo(400);
        assertThat(post("/api/games",
                "{\"roundId\":1,\"hostPlays\":false,\"buzzMode\":\"TIMER\",\"buzzDelaySeconds\":600}",
                null).status())
                .isEqualTo(400);

        // And a game that says nothing about it still waits for its host.
        Game plain = newGame();
        assertThat(get("/api/games/" + plain.id).body().path("buzzMode").asString())
                .isEqualTo("HOST");
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    private Game newGame() throws Exception {
        return newGame("{\"roundId\":1,\"hostPlays\":false}");
    }

    private Game newGame(String json) throws Exception {
        JsonNode body = post("/api/games", json, null).body();
        return new Game(body.path("gameId").asString(),
                body.path("joinCode").asString(),
                body.path("hostToken").asString());
    }

    /** Polls the snapshot until the server has moved the game itself. */
    private JsonNode awaitState(Game game, String state) throws Exception {
        long deadline = System.nanoTime() + Duration.ofSeconds(10).toNanos();
        JsonNode snap;
        do {
            snap = get("/api/games/" + game.id).body();
            if (state.equals(snap.path("state").asString())) {
                return snap;
            }
            Thread.sleep(100);
        } while (System.nanoTime() < deadline);
        throw new AssertionError(
                "game sat in " + snap.path("state").asString() + " instead of reaching " + state);
    }

    /** Handle for one game under test. */
    private final class Game {
        private final String id;
        private final String code;
        private final String hostToken;

        Game(String id, String code, String hostToken) {
            this.id = id;
            this.code = code;
            this.hostToken = hostToken;
        }

        /** Joins a new player who starts their own team of the same name. */
        String join(String name) throws Exception {
            JsonNode body = post("/api/games/" + code + "/players",
                    mapper.writeValueAsString(
                            java.util.Map.of("name", name, "newTeamName", name)), null).body();
            return body.path("playerToken").asString();
        }

        /** Joins a second player onto an existing team. */
        String joinTeammate(String name, String teamId) throws Exception {
            JsonNode body = post("/api/games/" + code + "/players",
                    mapper.writeValueAsString(
                            java.util.Map.of("name", name, "teamId", teamId)), null).body();
            return body.path("playerToken").asString();
        }

        Response host(String action, String json) throws Exception {
            Response res = hostRaw(action, json);
            assertThat(res.status())
                    .as("%s should have succeeded but returned %s: %s",
                            action, res.status(), res.raw())
                    .isEqualTo(200);
            return res;
        }

        Response hostRaw(String action, String json) throws Exception {
            return post("/api/games/" + id + "/" + action, json, hostToken);
        }

        Response buzz(String playerToken) throws Exception {
            return post("/api/games/" + id + "/buzz",
                    mapper.writeValueAsString(
                            java.util.Map.of("playerToken", playerToken)), null);
        }
    }

    private record Response(int status, String raw, JsonNode body) {
    }

    private URI uri(String path) {
        return URI.create("http://localhost:" + port + path);
    }

    private Response get(String path) throws Exception {
        HttpResponse<byte[]> res = http.send(
                HttpRequest.newBuilder(uri(path)).GET().build(),
                HttpResponse.BodyHandlers.ofByteArray());
        return toResponse(res);
    }

    private Response post(String path, String json, String hostToken) throws Exception {
        HttpRequest.Builder req = HttpRequest.newBuilder(uri(path))
                .header("Content-Type", "application/json; charset=utf-8")
                .POST(json == null
                        ? HttpRequest.BodyPublishers.ofString("{}", StandardCharsets.UTF_8)
                        : HttpRequest.BodyPublishers.ofString(json, StandardCharsets.UTF_8));
        if (hostToken != null) {
            req.header(HOST_TOKEN, hostToken);
        }
        return toResponse(http.send(req.build(), HttpResponse.BodyHandlers.ofByteArray()));
    }

    private Response toResponse(HttpResponse<byte[]> res) throws IOException {
        // Decode explicitly: the clue text is Georgian, so a charset slip shows
        // up as mojibake rather than a failure.
        String raw = new String(res.body(), StandardCharsets.UTF_8);
        JsonNode node = raw.isBlank() ? mapper.createObjectNode() : mapper.readTree(raw);
        return new Response(res.statusCode(), raw, node);
    }

    private static long firstTileValued(JsonNode snapshot, int value) {
        for (JsonNode col : snapshot.path("board")) {
            for (JsonNode tile : col.path("tiles")) {
                if (tile.path("value").asInt(-1) == value
                        && "AVAILABLE".equals(tile.path("status").asString())) {
                    return tile.path("clueId").asLong();
                }
            }
        }
        throw new AssertionError("no available tile worth " + value);
    }

    private static int scoreOf(JsonNode snapshot, String teamName) {
        for (JsonNode team : snapshot.path("teams")) {
            if (teamName.equals(team.path("name").asString())) {
                return team.path("score").asInt();
            }
        }
        throw new AssertionError("no team named " + teamName);
    }

    private static boolean lockedOut(JsonNode snapshot, String teamName) {
        for (JsonNode team : snapshot.path("teams")) {
            if (teamName.equals(team.path("name").asString())) {
                return team.path("lockedOutOnCurrentClue").asBoolean();
            }
        }
        throw new AssertionError("no team named " + teamName);
    }
}
