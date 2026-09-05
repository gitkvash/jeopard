package ge.jeopard.backend.game;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.TestPropertySource;
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
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * What happens when more than one person acts at the same instant.
 *
 * <p>{@link GameFlowTest} already covers the buzz race. This covers the rest of
 * the concurrency surface: a roomful of people joining at once, several rooms
 * running side by side, and a host whose finger lands twice on the same button.
 *
 * <p>The creation ceiling is off here -- these tests open several games in a
 * few seconds, which is exactly the shape the limiter exists to refuse.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestPropertySource(properties = "jeopard.limits.games-per-hour-per-ip=0")
class ConcurrencyTest {

    private static final String HOST_TOKEN = "X-Host-Token";

    @LocalServerPort
    int port;

    @Autowired
    ObjectMapper mapper;

    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    // ------------------------------------------------------------------
    // one room, everybody joining at once
    // ------------------------------------------------------------------

    @Test
    @DisplayName("a roomful joining at once all get in, each on their own seat")
    void simultaneousJoinsGetDistinctSeats() throws Exception {
        Game game = newGame();

        List<Response> results = race(12, i -> game.joinRaw("player-" + i, "team-" + i));

        assertThat(results).allSatisfy(r -> assertThat(r.status())
                .as("join returned %s: %s", r.status(), r.raw())
                .isEqualTo(200));

        JsonNode lobby = get("/api/games/" + game.code + "/lobby").body();
        List<Integer> seats = new ArrayList<>();
        lobby.path("teams").forEach(t -> seats.add(t.path("seat").asInt()));

        assertThat(seats).hasSize(12);
        assertThat(new HashSet<>(seats))
                .as("every team should have its own seat, got %s", seats)
                .hasSize(12);
    }

    @Test
    @DisplayName("the same player name claimed twice at once is refused, not a 500")
    void duplicateNameRaceIsRefusedCleanly() throws Exception {
        Game game = newGame();

        List<Response> results = race(8, i -> game.joinRaw("გიორგი", "გუნდი-" + i));

        long accepted = results.stream().filter(r -> r.status() == 200).count();
        long serverErrors = results.stream().filter(r -> r.status() >= 500).count();

        assertThat(accepted).as("only one player may hold a name").isEqualTo(1);
        assertThat(serverErrors)
                .as("losing the race is a conflict, not a crash: %s",
                        results.stream().filter(r -> r.status() >= 500)
                                .map(Response::raw).toList())
                .isZero();
    }

    @Test
    @DisplayName("the same team name created twice at once is refused, not a 500")
    void duplicateTeamNameRaceIsRefusedCleanly() throws Exception {
        Game game = newGame();

        List<Response> results = race(8, i -> game.joinRaw("player-" + i, "მთიები"));

        long accepted = results.stream().filter(r -> r.status() == 200).count();
        long serverErrors = results.stream().filter(r -> r.status() >= 500).count();

        assertThat(accepted).as("only one team may hold a name").isEqualTo(1);
        assertThat(serverErrors)
                .as("losing the race is a conflict, not a crash: %s",
                        results.stream().filter(r -> r.status() >= 500)
                                .map(Response::raw).toList())
                .isZero();
    }

    // ------------------------------------------------------------------
    // several rooms at once
    // ------------------------------------------------------------------

    @Test
    @DisplayName("rooms running side by side each get their own winner")
    void parallelRoomsStayIndependent() throws Exception {
        int rooms = 4;
        int teamsPerRoom = 4;

        List<Game> games = new ArrayList<>();
        List<List<String>> tokens = new ArrayList<>();
        for (int r = 0; r < rooms; r++) {
            Game game = newGame();
            List<String> roomTokens = new ArrayList<>();
            for (int t = 0; t < teamsPerRoom; t++) {
                roomTokens.add(game.join("team-" + r + "-" + t));
            }
            JsonNode snap = game.host("start", null).body();
            long clueId = firstAvailableTile(snap);
            game.host("select-clue", "{\"clueId\":" + clueId + "}");
            game.host("open-buzzer", null);
            games.add(game);
            tokens.add(roomTokens);
        }

        // Every buzzer in every room, on the same barrier.
        int racers = rooms * teamsPerRoom;
        List<Response> results = race(racers, i -> {
            int room = i / teamsPerRoom;
            return games.get(room).buzz(tokens.get(room).get(i % teamsPerRoom));
        });

        long accepted = results.stream().filter(r -> r.status() == 200).count();
        assertThat(accepted)
                .as("one winner per room, not one winner overall")
                .isEqualTo(rooms);

        Set<String> winners = new HashSet<>();
        for (Game game : games) {
            JsonNode snap = get("/api/games/" + game.id).body();
            assertThat(snap.path("state").asString())
                    .as("room %s should have a buzz", game.code)
                    .isEqualTo("BUZZED");
            String winner = snap.path("buzzedTeamId").asString();
            assertThat(winner).isNotBlank();
            assertThat(winners.add(winner))
                    .as("a team cannot win in two rooms")
                    .isTrue();
            // The winner really belongs to this room.
            List<String> teamIds = new ArrayList<>();
            snap.path("teams").forEach(t -> teamIds.add(t.path("id").asString()));
            assertThat(teamIds).contains(winner);
        }
    }

    // ------------------------------------------------------------------
    // the host's finger landing twice
    // ------------------------------------------------------------------

    @Test
    @DisplayName("a double-tapped judge scores once")
    void doubleTapJudgeAppliesOnce() throws Exception {
        Game game = newGame();
        String team = game.join("გუნდი ა");
        JsonNode snap = game.host("start", null).body();
        long clueId = firstTileValued(snap, 10);
        game.host("select-clue", "{\"clueId\":" + clueId + "}");
        game.host("open-buzzer", null);
        assertThat(game.buzz(team).status()).isEqualTo(200);

        List<Response> results = race(2, i -> game.hostRaw("judge", "{\"correct\":true}"));

        assertThat(results.stream().filter(r -> r.status() == 200).count())
                .as("only one judgement may land")
                .isEqualTo(1);

        JsonNode after = get("/api/games/" + game.id).body();
        assertThat(scoreOf(after, "გუნდი ა"))
                .as("the value should be credited once, not twice")
                .isEqualTo(10);
    }

    @Test
    @DisplayName("a double-tapped tile is selected once")
    void doubleTapSelectClueAppliesOnce() throws Exception {
        Game game = newGame();
        game.join("გუნდი ა");
        JsonNode snap = game.host("start", null).body();
        long clueId = firstTileValued(snap, 20);

        List<Response> results =
                race(2, i -> game.hostRaw("select-clue", "{\"clueId\":" + clueId + "}"));

        assertThat(results.stream().filter(r -> r.status() == 200).count()).isEqualTo(1);
        assertThat(results.stream().filter(r -> r.status() >= 500).count()).isZero();

        JsonNode after = get("/api/games/" + game.id).body();
        assertThat(after.path("tilesRemaining").asInt())
                .as("one tap, one tile")
                .isEqualTo(29);
    }

    // ------------------------------------------------------------------
    // what a rejected action tells the player
    // ------------------------------------------------------------------

    @Test
    @DisplayName("a refusal carries a readable reason the client can show")
    void refusalCarriesItsReason() throws Exception {
        Game game = newGame();
        String team = game.join("გუნდი ა");
        game.host("start", null);

        // Buzzing from the board -- no clue is up, so this is refused.
        Response refused = game.buzz(team);
        assertThat(refused.status()).isEqualTo(409);
        assertThat(readableMessage(refused.body()))
                .as("the client shows this to the player verbatim; body was %s", refused.raw())
                .isNotBlank();
    }

    /** The two fields {@code RestClient._errorMessage} looks for, in its order. */
    private static String readableMessage(JsonNode body) {
        if (body.path("detail").isString()) {
            return body.path("detail").asString();
        }
        if (body.path("message").isString()) {
            return body.path("message").asString();
        }
        return "";
    }

    // ------------------------------------------------------------------
    // plumbing
    // ------------------------------------------------------------------

    /** Runs {@code task} on {@code workers} threads that all start together. */
    private <T> List<T> race(int workers, ThrowingIntFunction<T> task) throws Exception {
        CyclicBarrier barrier = new CyclicBarrier(workers);
        List<T> out = new ArrayList<>();
        try (ExecutorService pool = Executors.newFixedThreadPool(workers)) {
            List<Future<T>> futures = new ArrayList<>();
            for (int i = 0; i < workers; i++) {
                int idx = i;
                futures.add(pool.submit(() -> {
                    barrier.await(20, TimeUnit.SECONDS);
                    return task.apply(idx);
                }));
            }
            for (Future<T> f : futures) {
                out.add(f.get(30, TimeUnit.SECONDS));
            }
        }
        return out;
    }

    @FunctionalInterface
    private interface ThrowingIntFunction<T> {
        T apply(int i) throws Exception;
    }

    private Game newGame() throws Exception {
        JsonNode body = post("/api/games",
                "{\"roundId\":1,\"hostPlays\":false,\"buzzMode\":\"HOST\"}", null).body();
        return new Game(body.path("gameId").asString(),
                body.path("joinCode").asString(),
                body.path("hostToken").asString());
    }

    private final class Game {
        private final String id;
        private final String code;
        private final String hostToken;

        Game(String id, String code, String hostToken) {
            this.id = id;
            this.code = code;
            this.hostToken = hostToken;
        }

        String join(String name) throws Exception {
            return joinRaw(name, name).body().path("playerToken").asString();
        }

        Response joinRaw(String playerName, String teamName) throws Exception {
            return post("/api/games/" + code + "/players",
                    mapper.writeValueAsString(
                            Map.of("name", playerName, "newTeamName", teamName)), null);
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
                    mapper.writeValueAsString(Map.of("playerToken", playerToken)), null);
        }
    }

    private record Response(int status, String raw, JsonNode body) {
    }

    private URI uri(String path) {
        return URI.create("http://localhost:" + port + path);
    }

    private Response get(String path) throws Exception {
        return toResponse(http.send(
                HttpRequest.newBuilder(uri(path)).GET().build(),
                HttpResponse.BodyHandlers.ofByteArray()));
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
        String raw = new String(res.body(), StandardCharsets.UTF_8);
        JsonNode node = raw.isBlank() ? mapper.createObjectNode() : mapper.readTree(raw);
        return new Response(res.statusCode(), raw, node);
    }

    private static long firstAvailableTile(JsonNode snapshot) {
        for (JsonNode col : snapshot.path("board")) {
            for (JsonNode tile : col.path("tiles")) {
                if ("AVAILABLE".equals(tile.path("status").asString())) {
                    return tile.path("clueId").asLong();
                }
            }
        }
        throw new AssertionError("no available tile");
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
}
