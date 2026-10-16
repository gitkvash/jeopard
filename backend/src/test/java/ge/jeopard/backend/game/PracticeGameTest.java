package ge.jeopard.backend.game;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.TestPropertySource;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * One person practising alone: host and only player at once, opening on the
 * board, judging their own answers, and closed to anyone else.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestPropertySource(properties = "jeopard.limits.games-per-hour-per-ip=0")
class PracticeGameTest {

    @LocalServerPort
    int port;

    @Autowired
    ObjectMapper mapper;

    private final HttpClient http = HttpClient.newHttpClient();

    private String gameId;
    private String hostToken;
    private String code;
    private String playerToken;
    private String teamId;

    @Test
    @DisplayName("opens on the board with one player, whatever the buzzer options asked for")
    void opensOnTheBoard() throws Exception {
        JsonNode snap = newPractice("{\"packageId\":1,\"hostPlays\":false,\"hostTeamName\":\"ანა\","
                + "\"buzzMode\":\"INSTANT\",\"playersPickClues\":true,"
                + "\"questionsVisibleToParticipants\":false,\"practice\":true}");

        assertThat(snap.path("state").asString()).isEqualTo("BOARD");
        assertThat(snap.path("practice").asBoolean()).isTrue();
        assertThat(snap.path("hostPlays").asBoolean()).isTrue();
        assertThat(snap.path("buzzMode").asString()).isEqualTo("HOST");
        assertThat(snap.path("playersPickClues").asBoolean()).isFalse();
        assertThat(snap.path("teams")).hasSize(1);
        assertThat(snap.path("teams").get(0).path("name").asString()).isEqualTo("ანა");

        // The question is on the shared payload too: there is nobody to hide it from.
        snap = host("select-clue", "{\"clueId\":" + firstAvailableTile(snap) + "}");
        assertThat(snap.path("state").asString()).isEqualTo("CLUE_READING");
        assertThat(snap.path("currentClue").path("question").asString()).isNotBlank();
    }

    @Test
    @DisplayName("right wins the value, wrong loses it, passing costs nothing")
    void selfJudging() throws Exception {
        JsonNode snap = newPractice("{\"packageId\":1,\"hostPlays\":true,\"practice\":true}");
        assertThat(snap.path("teams").get(0).path("name").asString()).isEqualTo("მოთამაშე");

        // Right: looked at the answer first, which is the normal way to judge.
        snap = host("select-clue", "{\"clueId\":" + firstAvailableTile(snap) + "}");
        int first = snap.path("currentClue").path("value").asInt();
        long firstId = snap.path("currentClue").path("clueId").asLong();
        JsonNode peek = host("peek", null);
        assertThat(peek.path("answer").asString()).isNotBlank();
        snap = host("self-judge", "{\"correct\":true}");
        assertThat(snap.path("state").asString()).isEqualTo("RESOLVED");
        assertThat(snap.path("answerRevealed").asBoolean()).isTrue();
        assertThat(score(snap)).isEqualTo(first);
        assertThat(tile(snap, firstId).path("wonByTeamId").asString()).isEqualTo(teamId);

        // Wrong.
        snap = host("next", null);
        snap = host("select-clue", "{\"clueId\":" + firstAvailableTile(snap) + "}");
        int second = snap.path("currentClue").path("value").asInt();
        snap = host("self-judge", "{\"correct\":false}");
        assertThat(snap.path("state").asString()).isEqualTo("RESOLVED");
        assertThat(score(snap)).isEqualTo(first - second);

        // Did not know: no points either way.
        snap = host("next", null);
        snap = host("select-clue", "{\"clueId\":" + firstAvailableTile(snap) + "}");
        snap = host("pass", null);
        assertThat(snap.path("state").asString()).isEqualTo("RESOLVED");
        assertThat(score(snap)).isEqualTo(first - second);

        // Judged once: a second ruling on the same clue is refused.
        assertThat(rawPost("/api/games/" + gameId + "/self-judge", "{\"correct\":true}", hostToken)
                .statusCode()).isEqualTo(409);
    }

    @Test
    @DisplayName("nobody can join a practice game or see its lobby")
    void closedToOthers() throws Exception {
        newPractice("{\"packageId\":1,\"hostPlays\":true,\"practice\":true}");

        assertThat(rawPost("/api/games/" + code + "/players", "{\"name\":\"ბექა\"}", null)
                .statusCode()).isEqualTo(409);
        assertThat(rawGet("/api/games/" + code + "/lobby").statusCode()).isEqualTo(409);
    }

    @Test
    @DisplayName("an ordinary game cannot be self-judged")
    void selfJudgeIsPracticeOnly() throws Exception {
        JsonNode created = post("/api/games",
                "{\"packageId\":1,\"hostPlays\":true,\"buzzMode\":\"HOST\"}", null, 200);
        gameId = created.path("gameId").asString();
        hostToken = created.path("hostToken").asString();
        JsonNode snap = host("start", null);
        assertThat(snap.path("practice").asBoolean()).isFalse();
        host("select-clue", "{\"clueId\":" + firstAvailableTile(snap) + "}");

        assertThat(rawPost("/api/games/" + gameId + "/self-judge", "{\"correct\":true}", hostToken)
                .statusCode()).isEqualTo(409);
    }

    @Test
    @DisplayName("the final round plays through with the player's own wager")
    void finalRound() throws Exception {
        long finalRoundId = 0;
        for (JsonNode r : get("/api/packages/1").path("rounds")) {
            if (r.path("finalRound").asBoolean()) {
                finalRoundId = r.path("id").asLong();
            }
        }
        assertThat(finalRoundId).isPositive();

        JsonNode snap = newPractice("{\"roundId\":" + finalRoundId + ",\"hostPlays\":true,\"practice\":true}");
        assertThat(snap.path("state").asString()).isEqualTo("FINAL_WAGER");

        host("select-clue", "{\"clueId\":" + firstAvailableTile(snap) + "}");
        post("/api/games/" + gameId + "/wager",
                mapper.writeValueAsString(Map.of("playerToken", playerToken, "wager", 0)), null, 200);
        snap = host("open-final", null);
        assertThat(snap.path("state").asString()).isEqualTo("FINAL_CLUE");
        snap = host("final-judge", "{\"teamId\":\"" + teamId + "\",\"correct\":true}");
        assertThat(snap.path("state").asString()).isEqualTo("FINAL_RESULT");
        snap = host("next", null);
        assertThat(snap.path("state").asString()).isEqualTo("FINISHED");
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    private JsonNode newPractice(String body) throws Exception {
        JsonNode created = post("/api/games", body, null, 200);
        gameId = created.path("gameId").asString();
        hostToken = created.path("hostToken").asString();
        code = created.path("joinCode").asString();
        playerToken = created.path("hostPlayerToken").asString();
        teamId = created.path("hostTeamId").asString();
        assertThat(playerToken).isNotBlank();
        return get("/api/games/" + gameId);
    }

    private static long firstAvailableTile(JsonNode snap) {
        for (JsonNode col : snap.path("board")) {
            for (JsonNode t : col.path("tiles")) {
                if ("AVAILABLE".equals(t.path("status").asString())) {
                    return t.path("clueId").asLong();
                }
            }
        }
        throw new AssertionError("no tile left");
    }

    private static JsonNode tile(JsonNode snap, long clueId) {
        for (JsonNode col : snap.path("board")) {
            for (JsonNode t : col.path("tiles")) {
                if (t.path("clueId").asLong() == clueId) {
                    return t;
                }
            }
        }
        throw new AssertionError("no such tile " + clueId);
    }

    private static int score(JsonNode snap) {
        return snap.path("teams").get(0).path("score").asInt();
    }

    private JsonNode host(String action, String json) throws Exception {
        return post("/api/games/" + gameId + "/" + action, json, hostToken, 200);
    }

    private JsonNode get(String path) throws Exception {
        HttpResponse<byte[]> res = rawGet(path);
        String raw = new String(res.body(), StandardCharsets.UTF_8);
        assertThat(res.statusCode()).as("GET %s -> %s", path, raw).isEqualTo(200);
        return mapper.readTree(raw);
    }

    private HttpResponse<byte[]> rawGet(String path) throws Exception {
        return http.send(HttpRequest.newBuilder(uri(path)).GET().build(),
                HttpResponse.BodyHandlers.ofByteArray());
    }

    private JsonNode post(String path, String json, String token, int expected) throws Exception {
        HttpResponse<byte[]> res = rawPost(path, json, token);
        String raw = new String(res.body(), StandardCharsets.UTF_8);
        assertThat(res.statusCode()).as("POST %s -> %s", path, raw).isEqualTo(expected);
        return raw.isBlank() ? null : mapper.readTree(raw);
    }

    private HttpResponse<byte[]> rawPost(String path, String json, String token) throws Exception {
        HttpRequest.Builder req = HttpRequest.newBuilder(uri(path))
                .header("Content-Type", "application/json; charset=utf-8")
                .POST(json == null
                        ? HttpRequest.BodyPublishers.noBody()
                        : HttpRequest.BodyPublishers.ofString(json, StandardCharsets.UTF_8));
        if (token != null) {
            req.header("X-Host-Token", token);
        }
        return http.send(req.build(), HttpResponse.BodyHandlers.ofByteArray());
    }

    private URI uri(String path) {
        return URI.create("http://localhost:" + port + path);
    }
}
