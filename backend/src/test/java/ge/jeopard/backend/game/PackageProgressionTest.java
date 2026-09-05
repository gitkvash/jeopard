package ge.jeopard.backend.game;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
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
 * A whole package played end to end: three boards then the final, with scores
 * carried across.
 *
 * <p>This is what makes the final round meaningful -- a wager has to be funded
 * by points won on the boards, so the final cannot be tested in isolation.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class PackageProgressionTest {

    @LocalServerPort
    int port;

    @Autowired
    ObjectMapper mapper;

    private final HttpClient http = HttpClient.newHttpClient();

    private String gameId;
    private String hostToken;

    @Test
    @DisplayName("three boards then the final, scores carried across, wagers funded by real points")
    void playsAWholePackage() throws Exception {
        // Host mode: clearBoard drives the buzzer open on every tile, which the
        // instant default would have opened already.
        JsonNode created = post("/api/games",
                "{\"packageId\":1,\"hostPlays\":false,\"buzzMode\":\"HOST\"}", null);
        gameId = created.path("gameId").asString();
        hostToken = created.path("hostToken").asString();
        String code = created.path("joinCode").asString();

        String alpha = joinTeam(code, "ალფა");
        String beta = joinTeam(code, "ბეტა");

        JsonNode snap = host("start", null);
        assertThat(snap.path("state").asString()).isEqualTo("BOARD");
        assertThat(snap.path("progressRounds").asBoolean()).isTrue();
        assertThat(snap.path("roundIdx").asInt()).isEqualTo(1);
        assertThat(snap.path("tilesRemaining").asInt()).isEqualTo(30);

        // ---- board 1: alpha sweeps it, beta gets nothing ----
        snap = clearBoard(snap, alpha);
        int afterBoard1 = scoreOf(snap, "ალფა");
        // Round 1 ladder is 10..50 across six topics: 6 * (10+20+30+40+50).
        assertThat(afterBoard1).isEqualTo(6 * 150);
        assertThat(scoreOf(snap, "ბეტა")).isZero();

        // Emptying the board rolls into round 2 with scores intact.
        assertThat(snap.path("state").asString()).isEqualTo("BOARD");
        assertThat(snap.path("roundIdx").asInt()).isEqualTo(2);
        assertThat(snap.path("tilesRemaining").asInt()).isEqualTo(30);
        assertThat(scoreOf(snap, "ალფა")).isEqualTo(afterBoard1);

        // ---- board 2: doubled ladder ----
        snap = clearBoard(snap, alpha);
        assertThat(snap.path("roundIdx").asInt()).isEqualTo(3);
        assertThat(scoreOf(snap, "ალფა")).isEqualTo(afterBoard1 + 6 * 300);

        // ---- board 3: tripled ladder, then into the final ----
        snap = clearBoard(snap, beta);
        assertThat(snap.path("state").asString()).isEqualTo("FINAL_WAGER");
        assertThat(snap.path("finalRound").asBoolean()).isTrue();
        assertThat(snap.path("board")).hasSize(2);

        int alphaBeforeFinal = scoreOf(snap, "ალფა");
        int betaBeforeFinal = scoreOf(snap, "ბეტა");
        assertThat(alphaBeforeFinal).isEqualTo(afterBoard1 + 6 * 300);
        assertThat(betaBeforeFinal).isEqualTo(6 * 450);

        // ---- final round ----
        long finalClue = snap.path("board").get(0).path("tiles").get(0).path("clueId").asLong();
        snap = host("select-clue", "{\"clueId\":" + finalClue + "}");
        // Topic is public so teams can wager; the question is not.
        assertThat(snap.path("currentClue").path("topicName").asString()).isNotBlank();
        assertThat(snap.path("currentClue").path("question").isNull()).isTrue();

        wager(alpha, 500);
        // Staking more than you hold is clamped down to your score, not rejected.
        snap = wager(beta, betaBeforeFinal + 10_000);
        assertThat(wagerOf(snap, "ბეტა")).isEqualTo(betaBeforeFinal);
        assertThat(wagerOf(snap, "ალფა")).isEqualTo(500);

        snap = host("open-final", null);
        assertThat(snap.path("state").asString()).isEqualTo("FINAL_CLUE");
        assertThat(snap.path("currentClue").path("question").asString()).isNotBlank();
        assertThat(snap.path("currentClue").path("answer").isNull()).isTrue();

        String alphaId = idOf(snap, "ალფა");
        String betaId = idOf(snap, "ბეტა");

        host("final-judge", judge(alphaId, true));
        // Judging the same team twice is refused.
        assertThat(status("final-judge", judge(alphaId, true))).isEqualTo(409);

        snap = host("final-judge", judge(betaId, false));

        assertThat(snap.path("state").asString()).isEqualTo("FINAL_RESULT");
        assertThat(snap.path("currentClue").path("answer").asString()).isNotBlank();
        assertThat(scoreOf(snap, "ალფა")).isEqualTo(alphaBeforeFinal + 500);
        assertThat(scoreOf(snap, "ბეტა")).isZero();

        snap = host("next", null);
        assertThat(snap.path("state").asString()).isEqualTo("FINISHED");
        assertThat(snap.path("attribution").asString()).contains("moazrovne.net");
    }

    @Test
    @DisplayName("a single-round game finishes at the end of that board")
    void singleRoundGameDoesNotProgress() throws Exception {
        JsonNode created = post("/api/games",
                "{\"roundId\":1,\"hostPlays\":false,\"buzzMode\":\"HOST\"}", null);
        gameId = created.path("gameId").asString();
        hostToken = created.path("hostToken").asString();
        String team = joinTeam(created.path("joinCode").asString(), "მარტო");

        JsonNode snap = host("start", null);
        assertThat(snap.path("progressRounds").asBoolean()).isFalse();

        snap = clearBoard(snap, team);
        assertThat(snap.path("state").asString()).isEqualTo("FINISHED");
        assertThat(snap.path("roundIdx").asInt()).isEqualTo(1);
    }

    @Test
    @DisplayName("creation requires exactly one of packageId or roundId")
    void creationRejectsAmbiguousScope() throws Exception {
        assertThat(postStatus("/api/games", "{\"hostPlays\":false}")).isEqualTo(400);
        assertThat(postStatus("/api/games", "{\"packageId\":1,\"roundId\":1,\"hostPlays\":false}"))
                .isEqualTo(400);
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    /**
     * Wins every remaining tile on the current board for one team, then returns
     * the snapshot after the final `next` (which either rolls to the next round
     * or finishes).
     *
     * <p>Opens the buzzer by hand, so the games it is given are host-mode ones.
     */
    private JsonNode clearBoard(JsonNode snapshot, String teamToken) throws Exception {
        JsonNode snap = snapshot;
        // Emptying a board rolls straight into the next round, which is also
        // state BOARD -- so stop as soon as the round index moves.
        final int round = snap.path("roundIdx").asInt();
        while ("BOARD".equals(snap.path("state").asString())
                && snap.path("roundIdx").asInt() == round) {
            Long clueId = nextAvailableTile(snap);
            if (clueId == null) {
                break;
            }
            host("select-clue", "{\"clueId\":" + clueId + "}");
            host("open-buzzer", null);
            buzz(teamToken);
            host("judge", "{\"correct\":true}");
            snap = host("next", null);
        }
        return snap;
    }

    private static Long nextAvailableTile(JsonNode snapshot) {
        for (JsonNode col : snapshot.path("board")) {
            for (JsonNode tile : col.path("tiles")) {
                if ("AVAILABLE".equals(tile.path("status").asString())) {
                    return tile.path("clueId").asLong();
                }
            }
        }
        return null;
    }

    private String joinTeam(String code, String name) throws Exception {
        return post("/api/games/" + code + "/players",
                mapper.writeValueAsString(Map.of("name", name, "newTeamName", name)), null)
                .path("playerToken").asString();
    }

    private void buzz(String playerToken) throws Exception {
        JsonNode res = post("/api/games/" + gameId + "/buzz",
                mapper.writeValueAsString(Map.of("playerToken", playerToken)), null);
        assertThat(res.path("state").asString()).isEqualTo("BUZZED");
    }

    private JsonNode wager(String playerToken, int amount) throws Exception {
        return post("/api/games/" + gameId + "/wager",
                mapper.writeValueAsString(Map.of("playerToken", playerToken, "wager", amount)),
                null);
    }

    private String judge(String teamId, boolean correct) throws Exception {
        return mapper.writeValueAsString(Map.of("teamId", teamId, "correct", correct));
    }

    private JsonNode host(String action, String json) throws Exception {
        HttpResponse<byte[]> res = hostSend(action, json);
        String raw = new String(res.body(), StandardCharsets.UTF_8);
        assertThat(res.statusCode())
                .as("%s returned %s: %s", action, res.statusCode(), raw)
                .isEqualTo(200);
        return mapper.readTree(raw);
    }

    private int status(String action, String json) throws Exception {
        return hostSend(action, json).statusCode();
    }

    private HttpResponse<byte[]> hostSend(String action, String json) throws Exception {
        return http.send(
                HttpRequest.newBuilder(uri("/api/games/" + gameId + "/" + action))
                        .header("Content-Type", "application/json; charset=utf-8")
                        .header("X-Host-Token", hostToken)
                        .POST(HttpRequest.BodyPublishers.ofString(
                                json == null ? "{}" : json, StandardCharsets.UTF_8))
                        .build(),
                HttpResponse.BodyHandlers.ofByteArray());
    }

    private JsonNode post(String path, String json, String token) throws Exception {
        HttpResponse<byte[]> res = rawPost(path, json, token);
        return mapper.readTree(new String(res.body(), StandardCharsets.UTF_8));
    }

    private int postStatus(String path, String json) throws Exception {
        return rawPost(path, json, null).statusCode();
    }

    private HttpResponse<byte[]> rawPost(String path, String json, String token)
            throws Exception {
        HttpRequest.Builder req = HttpRequest.newBuilder(uri(path))
                .header("Content-Type", "application/json; charset=utf-8")
                .POST(HttpRequest.BodyPublishers.ofString(
                        json == null ? "{}" : json, StandardCharsets.UTF_8));
        if (token != null) {
            req.header("X-Host-Token", token);
        }
        return http.send(req.build(), HttpResponse.BodyHandlers.ofByteArray());
    }

    private URI uri(String path) {
        return URI.create("http://localhost:" + port + path);
    }

    private static String idOf(JsonNode snapshot, String name) {
        return findTeam(snapshot, name).path("id").asString();
    }

    private static int scoreOf(JsonNode snapshot, String name) {
        return findTeam(snapshot, name).path("score").asInt();
    }

    private static int wagerOf(JsonNode snapshot, String name) {
        return findTeam(snapshot, name).path("wager").asInt();
    }

    private static JsonNode findTeam(JsonNode snapshot, String name) {
        for (JsonNode t : snapshot.path("teams")) {
            if (name.equals(t.path("name").asString())) {
                return t;
            }
        }
        throw new AssertionError("no team named " + name);
    }
}
