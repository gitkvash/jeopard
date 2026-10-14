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
import java.util.LinkedHashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * A game where the players choose the tile, in turn, instead of the host: the
 * turn passes team to team (or solo player to solo player) in seat order, any
 * member of the team whose turn it is may tap, and the host may choose at any
 * moment instead.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestPropertySource(properties = "jeopard.limits.games-per-hour-per-ip=0")
class PlayersPickCluesTest {

    @LocalServerPort
    int port;

    @Autowired
    ObjectMapper mapper;

    private final HttpClient http = HttpClient.newHttpClient();

    private String gameId;
    private String hostToken;
    private String code;

    @Test
    @DisplayName("the first seat has the first pick, and nobody else can take it")
    void firstSeatPicksFirst() throws Exception {
        newGame(true);
        JsonNode ana = join("ანა", null, "მთიები");
        JsonNode beka = join("ბექა", null, "ვეფხვები");

        JsonNode snap = host("start", null);
        assertThat(snap.path("playersPickClues").asBoolean()).isTrue();
        assertThat(snap.path("pickingTeamId").asString()).isEqualTo(ana.path("teamId").asString());

        long tile = firstAvailableTile(snap);
        // Out of turn: refused, and the board is untouched.
        assertThat(pick(beka, tile).statusCode()).isEqualTo(409);
        assertThat(get("/api/games/" + gameId).path("state").asString()).isEqualTo("BOARD");

        JsonNode after = json(pick(ana, tile));
        assertThat(after.path("state").asString()).isEqualTo("CLUE_READING");
        assertThat(after.path("currentClue").path("clueId").asLong()).isEqualTo(tile);
    }

    @Test
    @DisplayName("the turn moves on with every clue, whoever answered it, and wraps round")
    void turnRotatesInSeatOrder() throws Exception {
        newGame(true);
        JsonNode ana = join("ანა", null, "მთიები");
        JsonNode beka = join("ბექა", null, "ვეფხვები");

        JsonNode snap = host("start", null);
        // Ana's team picks and then *wins* the clue: winning does not keep the turn.
        snap = json(pick(ana, firstAvailableTile(snap)));
        host("open-buzzer", null);
        buzz(ana);
        snap = host("judge", "{\"correct\":true}");
        assertThat(snap.path("state").asString()).isEqualTo("RESOLVED");
        snap = host("next", null);
        assertThat(snap.path("pickingTeamId").asString()).isEqualTo(beka.path("teamId").asString());

        // Ana is out of turn now; Beka is in.
        long tile = firstAvailableTile(snap);
        assertThat(pick(ana, tile).statusCode()).isEqualTo(409);
        snap = json(pick(beka, tile));
        host("pass", null);
        snap = host("next", null);
        assertThat(snap.path("pickingTeamId").asString()).isEqualTo(ana.path("teamId").asString());
    }

    @Test
    @DisplayName("any member of the team whose turn it is may pick")
    void anyTeammateMayPick() throws Exception {
        newGame(true);
        JsonNode ana = join("ანა", null, "მთიები");
        JsonNode gio = join("გიო", ana.path("teamId").asString(), null);
        join("ბექა", null, "ვეფხვები");

        JsonNode snap = host("start", null);
        JsonNode after = json(pick(gio, firstAvailableTile(snap)));
        assertThat(after.path("state").asString()).isEqualTo("CLUE_READING");
    }

    @Test
    @DisplayName("solo players take turns as individuals")
    void soloPlayersRotate() throws Exception {
        newGame(true);
        JsonNode ana = join("ანა", null, null);
        JsonNode beka = join("ბექა", null, null);
        JsonNode gio = join("გიო", null, null);

        JsonNode snap = host("start", null);
        assertThat(snap.path("pickingTeamId").asString()).isEqualTo(ana.path("teamId").asString());

        snap = json(pick(ana, firstAvailableTile(snap)));
        assertThat(snap.path("pickingTeamId").asString()).isEqualTo(beka.path("teamId").asString());
        host("pass", null);
        snap = host("next", null);
        snap = json(pick(beka, firstAvailableTile(snap)));
        assertThat(snap.path("pickingTeamId").asString()).isEqualTo(gio.path("teamId").asString());
    }

    @Test
    @DisplayName("the host may choose a tile at any time, and that spends the turn")
    void hostMayAlwaysChoose() throws Exception {
        newGame(true);
        JsonNode ana = join("ანა", null, "მთიები");
        JsonNode beka = join("ბექა", null, "ვეფხვები");

        JsonNode snap = host("start", null);
        snap = host("select-clue", "{\"clueId\":" + firstAvailableTile(snap) + "}");
        assertThat(snap.path("state").asString()).isEqualTo("CLUE_READING");
        // It was Ana's turn and the host took it for her.
        assertThat(snap.path("pickingTeamId").asString()).isEqualTo(beka.path("teamId").asString());
        host("pass", null);
        snap = host("next", null);
        assertThat(pick(ana, firstAvailableTile(snap)).statusCode()).isEqualTo(409);
    }

    @Test
    @DisplayName("a player cannot pick while a clue is up, or in a game the host runs")
    void refusedOutsideTheBoardAndTheMode() throws Exception {
        newGame(true);
        JsonNode ana = join("ანა", null, "მთიები");
        join("ბექა", null, "ვეფხვები");
        // Not started yet.
        assertThat(pick(ana, 1).statusCode()).isEqualTo(409);

        JsonNode snap = host("start", null);
        long tile = firstAvailableTile(snap);
        json(pick(ana, tile));
        // A second tap -- a double tap, or a teammate -- finds the board already gone.
        assertThat(pick(ana, tile).statusCode()).isEqualTo(409);

        newGame(false);
        JsonNode cara = join("კარა", null, "მთიები");
        snap = host("start", null);
        assertThat(pick(cara, firstAvailableTile(snap)).statusCode()).isEqualTo(403);
        assertThat(snap.path("playersPickClues").asBoolean()).isFalse();
    }

    @Test
    @DisplayName("when the team holding the turn leaves, the turn goes to the next seat")
    void turnSurvivesTheHolderLeaving() throws Exception {
        newGame(true);
        JsonNode ana = join("ანა", null, "მთიები");
        JsonNode beka = join("ბექა", null, "ვეფხვები");
        join("გიო", null, "ლომები");

        host("start", null);
        post("/api/games/" + gameId + "/leave",
                mapper.writeValueAsString(Map.of("playerToken", ana.path("playerToken").asString())),
                null, 204);
        JsonNode snap = get("/api/games/" + gameId);
        assertThat(snap.path("pickingTeamId").asString()).isEqualTo(beka.path("teamId").asString());
    }

    @Test
    @DisplayName("the clue text is not what decides a pick: it works with the question hidden")
    void worksWithQuestionsHidden() throws Exception {
        JsonNode created = post("/api/games",
                "{\"packageId\":1,\"hostPlays\":false,\"buzzMode\":\"HOST\",\"playersPickClues\":true,"
                        + "\"questionsVisibleToParticipants\":false}", null, 200);
        gameId = created.path("gameId").asString();
        hostToken = created.path("hostToken").asString();
        code = created.path("joinCode").asString();
        JsonNode ana = join("ანა", null, "მთიები");

        JsonNode snap = host("start", null);
        JsonNode after = json(pick(ana, firstAvailableTile(snap)));
        assertThat(after.path("state").asString()).isEqualTo("CLUE_READING");
        assertThat(after.path("currentClue").path("question").isNull()).isTrue();
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    private void newGame(boolean playersPick) throws Exception {
        JsonNode created = post("/api/games",
                "{\"packageId\":1,\"hostPlays\":false,\"buzzMode\":\"HOST\",\"playersPickClues\":"
                        + playersPick + "}", null, 200);
        gameId = created.path("gameId").asString();
        hostToken = created.path("hostToken").asString();
        code = created.path("joinCode").asString();
    }

    private JsonNode join(String name, String teamId, String newTeamName) throws Exception {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", name);
        if (teamId != null) {
            body.put("teamId", teamId);
        }
        if (newTeamName != null) {
            body.put("newTeamName", newTeamName);
        }
        return post("/api/games/" + code + "/players", mapper.writeValueAsString(body), null, 200);
    }

    private HttpResponse<byte[]> pick(JsonNode player, long clueId) throws Exception {
        return rawPost("/api/games/" + gameId + "/pick-clue",
                mapper.writeValueAsString(Map.of(
                        "playerToken", player.path("playerToken").asString(),
                        "clueId", clueId)),
                null);
    }

    private JsonNode json(HttpResponse<byte[]> res) throws Exception {
        String raw = new String(res.body(), StandardCharsets.UTF_8);
        assertThat(res.statusCode()).as("-> %s", raw).isEqualTo(200);
        return mapper.readTree(raw);
    }

    private void buzz(JsonNode player) throws Exception {
        json(rawPost("/api/games/" + gameId + "/buzz",
                mapper.writeValueAsString(Map.of("playerToken", player.path("playerToken").asString())),
                null));
    }

    private JsonNode host(String action, String json) throws Exception {
        return json(rawPost("/api/games/" + gameId + "/" + action, json, hostToken));
    }

    private JsonNode get(String path) throws Exception {
        HttpResponse<byte[]> res = http.send(
                HttpRequest.newBuilder(uri(path)).GET().build(),
                HttpResponse.BodyHandlers.ofByteArray());
        return mapper.readTree(new String(res.body(), StandardCharsets.UTF_8));
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
}
