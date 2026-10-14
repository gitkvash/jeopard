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
 * Playing without a team, setting a buzz aside, and the host's corrections:
 * editing a score and moving people between teams.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
// Each test makes a game of its own; seventeen of them would spend the creation
// limit that the other game tests, sharing a context, are counting on.
@TestPropertySource(properties = "jeopard.limits.games-per-hour-per-ip=0")
class HostControlsTest {

    @LocalServerPort
    int port;

    @Autowired
    ObjectMapper mapper;

    private final HttpClient http = HttpClient.newHttpClient();

    private String gameId;
    private String hostToken;
    private String code;

    // ------------------------------------------------------------------
    // Playing without a team
    // ------------------------------------------------------------------

    @Test
    @DisplayName("a player may join with no team, and plays as a team of one named after them")
    void joinWithoutATeam() throws Exception {
        newGame(false);
        JsonNode ana = join("ანა", null, null);

        assertThat(ana.path("solo").asBoolean()).isTrue();
        assertThat(ana.path("teamName").asString()).isEqualTo("ანა");

        // Nobody can sit with a solo player, so the join list does not offer them.
        join("ბექა", null, "მთიები");
        JsonNode lobby = get("/api/games/" + code + "/lobby");
        assertThat(lobby.path("teams")).hasSize(1);
        assertThat(lobby.path("teams").get(0).path("name").asString()).isEqualTo("მთიები");

        // ...but they are a scoring unit on the board like any other.
        JsonNode snap = host("start", null);
        assertThat(snap.path("teams")).hasSize(2);
        assertThat(team(snap, "ანა").path("solo").asBoolean()).isTrue();
        assertThat(team(snap, "მთიები").path("solo").asBoolean()).isFalse();
    }

    @Test
    @DisplayName("a solo player scores, and is locked out, like any team")
    void soloPlayerBuzzesAndScores() throws Exception {
        newGame(false, BuzzMode.HOST);
        JsonNode ana = join("ანა", null, null);
        join("ბექა", null, null);

        JsonNode snap = host("start", null);
        host("select-clue", "{\"clueId\":" + firstAvailableTile(snap) + "}");
        host("open-buzzer", null);

        snap = buzz(ana.path("playerToken").asString(), 200);
        assertThat(snap.path("buzzedTeamId").asString()).isEqualTo(ana.path("teamId").asString());
        snap = host("judge", "{\"correct\":true}");
        assertThat(team(snap, "ანა").path("score").asInt()).isPositive();
    }

    @Test
    @DisplayName("a solo player's name does not collide with a team of the same name")
    void soloNameDoesNotBlockATeamName() throws Exception {
        newGame(false);
        join("ანა", null, null);
        // A team called ანა is a different thing from the person called ანა.
        assertThat(joinStatus("ბექა", null, "ანა")).isEqualTo(200);
        // Two chosen teams still cannot share a name.
        assertThat(joinStatus("გიო", null, "ანა")).isEqualTo(409);
    }

    @Test
    @DisplayName("before the game starts a player can leave a team, go back, and switch")
    void playerMovesThemselvesInTheLobby() throws Exception {
        newGame(false);
        JsonNode nino = join("ნინო", null, "მთიები");
        JsonNode gio = join("გიო", nino.path("teamId").asString(), null);
        join("ლევანი", null, "ვეფხვები");
        String ninoTeam = nino.path("teamId").asString();

        // Gio leaves: he is alone now, and Nino's team is still there with her in it.
        JsonNode snap = changeTeam(gio, null, null, 200);
        assertThat(team(snap, "გიო").path("solo").asBoolean()).isTrue();
        assertThat(names(team(snap, "მთიები"))).containsExactly("ნინო");

        // ...asking to be alone when already alone changes nothing.
        snap = changeTeam(gio, null, null, 200);
        assertThat(snap.path("teams")).hasSize(3);

        // He enrolls in the other team. His own team of one is gone with him.
        String tigers = team(snap, "ვეფხვები").path("id").asString();
        snap = changeTeam(gio, tigers, null, 200);
        assertThat(snap.path("teams")).hasSize(2);
        // Members are listed in the order they joined the game, not the order they moved.
        assertThat(names(team(snap, "ვეფხვები"))).containsExactlyInAnyOrder("ლევანი", "გიო");

        // He starts a team of his own.
        snap = changeTeam(gio, null, "ახალი", 200);
        assertThat(names(team(snap, "ახალი"))).containsExactly("გიო");

        // Nino was the only one left on her team and leaves too: the team goes.
        snap = changeTeam(nino, null, null, 200);
        assertThat(snap.path("teams")).hasSize(3);
        for (JsonNode t : snap.path("teams")) {
            assertThat(t.path("id").asString()).isNotEqualTo(ninoTeam);
        }
    }

    @Test
    @DisplayName("a player cannot change teams once the game has started")
    void noSelfServiceMovesAfterStart() throws Exception {
        newGame(false);
        JsonNode nino = join("ნინო", null, "მთიები");
        join("ლევანი", null, "ვეფხვები");
        host("start", null);
        changeTeam(nino, null, null, 409);
    }

    @Test
    @DisplayName("a token that is not a player's in this game is refused")
    void changeTeamNeedsAPlayerToken() throws Exception {
        newGame(false);
        join("ნინო", null, "მთიები");
        assertThat(rawPost("/api/games/" + gameId + "/team",
                "{\"playerToken\":\"nope\"}", null).statusCode()).isEqualTo(403);
    }

    @Test
    @DisplayName("the playing host's own seat cannot be moved")
    void hostSeatIsFixed() throws Exception {
        JsonNode created = newGame(true);
        join("სტუმარი", null, "სტუმრები");
        assertThat(rawPost("/api/games/" + gameId + "/team",
                "{\"playerToken\":\"" + created.path("hostPlayerToken").asString() + "\"}",
                null).statusCode()).isEqualTo(409);
        assertThat(rawPost("/api/games/" + gameId + "/players/"
                        + created.path("hostPlayerId").asString() + "/move", "{}",
                hostToken).statusCode()).isEqualTo(409);
    }

    // ------------------------------------------------------------------
    // Setting a buzz aside
    // ------------------------------------------------------------------

    @Test
    @DisplayName("skipping a buzz moves no points, locks nobody out, and reopens the buzzer for everyone")
    void skipBuzz() throws Exception {
        newGame(false, BuzzMode.HOST);
        JsonNode nino = join("ნინო", null, "მთიები");
        JsonNode levan = join("ლევანი", null, "ვეფხვები");

        JsonNode snap = host("start", null);
        host("select-clue", "{\"clueId\":" + firstAvailableTile(snap) + "}");
        host("open-buzzer", null);
        buzz(nino.path("playerToken").asString(), 200);

        snap = host("skip-buzz", null);
        assertThat(snap.path("state").asString()).isEqualTo("BUZZ_OPEN");
        assertThat(snap.path("buzzedTeamId").isNull()).isTrue();
        assertThat(team(snap, "მთიები").path("score").asInt()).isZero();
        assertThat(team(snap, "მთიები").path("lockedOutOnCurrentClue").asBoolean()).isFalse();

        // The team that pressed by accident is not penalised: it may buzz again,
        // and so may the other team.
        buzz(nino.path("playerToken").asString(), 200);
        host("skip-buzz", null);
        snap = buzz(levan.path("playerToken").asString(), 200);
        assertThat(snap.path("buzzedTeamId").asString()).isEqualTo(levan.path("teamId").asString());
    }

    @Test
    @DisplayName("a buzz can only be skipped while somebody is holding it")
    void skipNeedsABuzz() throws Exception {
        newGame(false, BuzzMode.HOST);
        join("ნინო", null, "მთიები");
        JsonNode snap = host("start", null);
        host("select-clue", "{\"clueId\":" + firstAvailableTile(snap) + "}");
        host("open-buzzer", null);
        assertThat(rawPost("/api/games/" + gameId + "/skip-buzz", null, hostToken).statusCode())
                .isEqualTo(409);
        assertThat(rawPost("/api/games/" + gameId + "/skip-buzz", null, "wrong").statusCode())
                .isEqualTo(403);
    }

    // ------------------------------------------------------------------
    // The answer, once the host has passed
    // ------------------------------------------------------------------

    @Test
    @DisplayName("after the host passes, the answer is in the snapshot a team gets")
    void passRevealsTheAnswerToTeams() throws Exception {
        newGame(false, BuzzMode.HOST);
        join("ნინო", null, "მთიები");
        JsonNode snap = host("start", null);
        host("select-clue", "{\"clueId\":" + firstAvailableTile(snap) + "}");
        host("open-buzzer", null);
        host("pass", null);

        // No host token: exactly what a team's own device would fetch.
        JsonNode teamView = get("/api/games/" + gameId);
        assertThat(teamView.path("state").asString()).isEqualTo("RESOLVED");
        assertThat(teamView.path("answerRevealed").asBoolean()).isTrue();
        assertThat(teamView.path("currentClue").path("answer").asString()).isNotBlank();
    }

    // ------------------------------------------------------------------
    // Host corrections
    // ------------------------------------------------------------------

    @Test
    @DisplayName("the host sets a team's score outright, in any state")
    void hostEditsAScore() throws Exception {
        newGame(false, BuzzMode.HOST);
        JsonNode nino = join("ნინო", null, "მთიები");
        join("ლევანი", null, "ვეფხვები");
        String teamId = nino.path("teamId").asString();

        // Even in the lobby.
        JsonNode snap = setScore(teamId, 70, 200);
        assertThat(team(snap, "მთიები").path("score").asInt()).isEqualTo(70);

        // And mid-clue, where a ruling is not what is being corrected.
        snap = host("start", null);
        host("select-clue", "{\"clueId\":" + firstAvailableTile(snap) + "}");
        snap = setScore(teamId, -30, 200);
        assertThat(team(snap, "მთიები").path("score").asInt()).isEqualTo(-30);

        // The other team is untouched.
        assertThat(team(snap, "ვეფხვები").path("score").asInt()).isZero();
    }

    @Test
    @DisplayName("editing a score needs the host token, a team of this game, and a sane number")
    void scoreEditIsGuarded() throws Exception {
        newGame(false);
        JsonNode nino = join("ნინო", null, "მთიები");
        String teamId = nino.path("teamId").asString();
        String path = "/api/games/" + gameId + "/teams/" + teamId + "/score";

        assertThat(rawPost(path, "{\"score\":10}", "wrong").statusCode()).isEqualTo(403);
        assertThat(rawPost(path, "{\"score\":10}", null).statusCode()).isEqualTo(400);
        assertThat(rawPost(path, "{}", hostToken).statusCode()).isEqualTo(400);
        assertThat(rawPost(path, "{\"score\":99999999}", hostToken).statusCode()).isEqualTo(400);
        assertThat(rawPost("/api/games/" + gameId + "/teams/"
                + java.util.UUID.randomUUID() + "/score", "{\"score\":10}", hostToken)
                .statusCode()).isEqualTo(404);
    }

    @Test
    @DisplayName("lowering a score trims a wager that the team could no longer fund")
    void scoreEditTrimsWager() throws Exception {
        // A single-round game on package 1's final round opens straight on the wager.
        JsonNode created = post("/api/games",
                "{\"roundId\":" + finalRoundId() + ",\"hostPlays\":false}", null);
        gameId = created.path("gameId").asString();
        hostToken = created.path("hostToken").asString();
        code = created.path("joinCode").asString();
        JsonNode nino = join("ნინო", null, "მთიები");
        String teamId = nino.path("teamId").asString();

        host("start", null);
        setScore(teamId, 100, 200);
        post("/api/games/" + gameId + "/wager", mapper.writeValueAsString(
                Map.of("playerToken", nino.path("playerToken").asString(), "wager", 80)), null);
        JsonNode snap = setScore(teamId, 30, 200);
        assertThat(team(snap, "მთიები").path("wager").asInt()).isEqualTo(30);
    }

    @Test
    @DisplayName("between clues the host moves a person to another team, a new team, or on their own")
    void hostMovesPlayers() throws Exception {
        newGame(false);
        JsonNode nino = join("ნინო", null, "მთიები");
        JsonNode gio = join("გიო", nino.path("teamId").asString(), null);
        JsonNode levan = join("ლევანი", null, "ვეფხვები");
        JsonNode snap = host("start", null);

        // Gio goes to the other team; Levan's team gains a member, Nino's keeps hers.
        snap = movePlayer(gio.path("playerId").asString(),
                levan.path("teamId").asString(), null, 200);
        // Members are listed in the order they joined the game, not the order they moved.
        assertThat(names(team(snap, "ვეფხვები"))).containsExactlyInAnyOrder("ლევანი", "გიო");
        assertThat(names(team(snap, "მთიები"))).containsExactly("ნინო");

        // Gio is sent off on his own.
        snap = movePlayer(gio.path("playerId").asString(), null, null, 200);
        assertThat(team(snap, "გიო").path("solo").asBoolean()).isTrue();

        // Levan, now alone on his team, goes to a brand-new one; the team he left
        // had nobody else, so it vanishes.
        snap = movePlayer(levan.path("playerId").asString(), null, "ახალი", 200);
        assertThat(names(team(snap, "ახალი"))).containsExactly("ლევანი");
        assertThat(snap.path("teams")).hasSize(3);
    }

    @Test
    @DisplayName("a team that loses its last member takes its score with it")
    void emptiedTeamIsRemoved() throws Exception {
        newGame(false);
        JsonNode nino = join("ნინო", null, "მთიები");
        JsonNode levan = join("ლევანი", null, "ვეფხვები");
        host("start", null);
        setScore(nino.path("teamId").asString(), 50, 200);

        JsonNode snap = movePlayer(nino.path("playerId").asString(),
                levan.path("teamId").asString(), null, 200);
        assertThat(snap.path("teams")).hasSize(1);
        assertThat(team(snap, "ვეფხვები").path("score").asInt()).isZero();
    }

    @Test
    @DisplayName("people cannot be moved while a clue is up")
    void noMovesMidClue() throws Exception {
        newGame(false, BuzzMode.HOST);
        JsonNode nino = join("ნინო", null, "მთიები");
        JsonNode levan = join("ლევანი", null, "ვეფხვები");
        JsonNode snap = host("start", null);
        host("select-clue", "{\"clueId\":" + firstAvailableTile(snap) + "}");

        assertThat(rawMove(nino.path("playerId").asString(),
                levan.path("teamId").asString(), null).statusCode()).isEqualTo(409);

        // Once the clue is done, it is allowed again.
        host("pass", null);
        movePlayer(nino.path("playerId").asString(), levan.path("teamId").asString(), null, 200);
    }

    @Test
    @DisplayName("moving a player needs the host token and a player of this game")
    void moveIsGuarded() throws Exception {
        newGame(false);
        JsonNode nino = join("ნინო", null, "მთიები");
        String path = "/api/games/" + gameId + "/players/" + nino.path("playerId").asString()
                + "/move";
        assertThat(rawPost(path, "{}", "wrong").statusCode()).isEqualTo(403);
        assertThat(rawPost("/api/games/" + gameId + "/players/" + java.util.UUID.randomUUID()
                + "/move", "{}", hostToken).statusCode()).isEqualTo(404);
        // Nobody can be put on a solo player's team.
        JsonNode solo = join("მარტო", null, null);
        assertThat(rawMove(nino.path("playerId").asString(), solo.path("teamId").asString(), null)
                .statusCode()).isEqualTo(404);
    }

    // ------------------------------------------------------------------
    // Ending / deleting game
    // ------------------------------------------------------------------

    @Test
    @DisplayName("host can delete the game, removing it and preventing further access")
    void hostCanDeleteGame() throws Exception {
        newGame(false);
        join("ნინო", null, "მთიები");

        HttpResponse<byte[]> wrongToken = http.send(
                HttpRequest.newBuilder(uri("/api/games/" + gameId))
                        .header("X-Host-Token", "wrong-token")
                        .DELETE().build(),
                HttpResponse.BodyHandlers.ofByteArray());
        assertThat(wrongToken.statusCode()).isEqualTo(403);

        HttpResponse<byte[]> deleted = http.send(
                HttpRequest.newBuilder(uri("/api/games/" + gameId))
                        .header("X-Host-Token", hostToken)
                        .DELETE().build(),
                HttpResponse.BodyHandlers.ofByteArray());
        assertThat(deleted.statusCode()).isEqualTo(204);

        HttpResponse<byte[]> snapshot = http.send(
                HttpRequest.newBuilder(uri("/api/games/" + gameId)).GET().build(),
                HttpResponse.BodyHandlers.ofByteArray());
        assertThat(snapshot.statusCode()).isEqualTo(404);
    }

    @Test
    @DisplayName("host can end the game via POST /end endpoint")
    void hostCanEndGameViaPost() throws Exception {
        newGame(false);
        join("გიორგი", null, "დინამო");

        HttpResponse<byte[]> ended = http.send(
                HttpRequest.newBuilder(uri("/api/games/" + gameId + "/end"))
                        .header("X-Host-Token", hostToken)
                        .POST(HttpRequest.BodyPublishers.noBody()).build(),
                HttpResponse.BodyHandlers.ofByteArray());
        assertThat(ended.statusCode()).isEqualTo(204);

        HttpResponse<byte[]> snapshot = http.send(
                HttpRequest.newBuilder(uri("/api/games/" + gameId)).GET().build(),
                HttpResponse.BodyHandlers.ofByteArray());
        assertThat(snapshot.statusCode()).isEqualTo(404);
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    private JsonNode newGame(boolean hostPlays) throws Exception {
        return newGame(hostPlays, null);
    }

    private JsonNode newGame(boolean hostPlays, BuzzMode buzzMode) throws Exception {
        JsonNode created = post("/api/games",
                "{\"packageId\":1,\"hostPlays\":" + hostPlays
                        + (buzzMode == null ? "" : ",\"buzzMode\":\"" + buzzMode + "\"")
                        + "}", null);
        gameId = created.path("gameId").asString();
        hostToken = created.path("hostToken").asString();
        code = created.path("joinCode").asString();
        return created;
    }

    /** The id of package 1's final round -- a single-round game that opens on the wager. */
    private long finalRoundId() throws Exception {
        for (JsonNode pkg : get("/api/packages")) {
            if (pkg.path("number").asInt() == 1) {
                for (JsonNode r : pkg.path("rounds")) {
                    if (r.path("finalRound").asBoolean()) {
                        return r.path("id").asLong();
                    }
                }
            }
        }
        throw new AssertionError("no final round in package 1");
    }

    private JsonNode join(String name, String teamId, String newTeamName) throws Exception {
        return post("/api/games/" + code + "/players", joinBody(name, teamId, newTeamName), null);
    }

    private int joinStatus(String name, String teamId, String newTeamName) throws Exception {
        return rawPost("/api/games/" + code + "/players",
                joinBody(name, teamId, newTeamName), null).statusCode();
    }

    private String joinBody(String name, String teamId, String newTeamName) throws Exception {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", name);
        if (teamId != null) {
            body.put("teamId", teamId);
        }
        if (newTeamName != null) {
            body.put("newTeamName", newTeamName);
        }
        return mapper.writeValueAsString(body);
    }

    /** A player moving themselves; null team and null name means "on my own". */
    private JsonNode changeTeam(JsonNode player, String teamId, String newTeamName, int expected)
            throws Exception {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("playerToken", player.path("playerToken").asString());
        if (teamId != null) {
            body.put("teamId", teamId);
        }
        if (newTeamName != null) {
            body.put("newTeamName", newTeamName);
        }
        HttpResponse<byte[]> res = rawPost("/api/games/" + gameId + "/team",
                mapper.writeValueAsString(body), null);
        String raw = new String(res.body(), StandardCharsets.UTF_8);
        assertThat(res.statusCode()).as("change team -> %s", raw).isEqualTo(expected);
        return mapper.readTree(raw);
    }

    private JsonNode movePlayer(String playerId, String teamId, String newTeamName, int expected)
            throws Exception {
        HttpResponse<byte[]> res = rawMove(playerId, teamId, newTeamName);
        String raw = new String(res.body(), StandardCharsets.UTF_8);
        assertThat(res.statusCode()).as("move -> %s", raw).isEqualTo(expected);
        return mapper.readTree(raw);
    }

    private HttpResponse<byte[]> rawMove(String playerId, String teamId, String newTeamName)
            throws Exception {
        Map<String, Object> body = new LinkedHashMap<>();
        if (teamId != null) {
            body.put("teamId", teamId);
        }
        if (newTeamName != null) {
            body.put("newTeamName", newTeamName);
        }
        return rawPost("/api/games/" + gameId + "/players/" + playerId + "/move",
                mapper.writeValueAsString(body), hostToken);
    }

    private JsonNode setScore(String teamId, int score, int expected) throws Exception {
        HttpResponse<byte[]> res = rawPost("/api/games/" + gameId + "/teams/" + teamId + "/score",
                "{\"score\":" + score + "}", hostToken);
        String raw = new String(res.body(), StandardCharsets.UTF_8);
        assertThat(res.statusCode()).as("set score -> %s", raw).isEqualTo(expected);
        return mapper.readTree(raw);
    }

    private JsonNode buzz(String playerToken, int expectedStatus) throws Exception {
        HttpResponse<byte[]> res = rawPost("/api/games/" + gameId + "/buzz",
                mapper.writeValueAsString(Map.of("playerToken", playerToken)), null);
        String raw = new String(res.body(), StandardCharsets.UTF_8);
        assertThat(res.statusCode()).as("buzz -> %s", raw).isEqualTo(expectedStatus);
        return mapper.readTree(raw);
    }

    private JsonNode host(String action, String json) throws Exception {
        HttpResponse<byte[]> res = rawPost("/api/games/" + gameId + "/" + action, json, hostToken);
        String raw = new String(res.body(), StandardCharsets.UTF_8);
        assertThat(res.statusCode()).as("%s -> %s", action, raw).isEqualTo(200);
        return mapper.readTree(raw);
    }

    private JsonNode get(String path) throws Exception {
        HttpResponse<byte[]> res = http.send(
                HttpRequest.newBuilder(uri(path)).GET().build(),
                HttpResponse.BodyHandlers.ofByteArray());
        return mapper.readTree(new String(res.body(), StandardCharsets.UTF_8));
    }

    private JsonNode post(String path, String json, String token) throws Exception {
        HttpResponse<byte[]> res = rawPost(path, json, token);
        String raw = new String(res.body(), StandardCharsets.UTF_8);
        assertThat(res.statusCode()).as("POST %s -> %s", path, raw).isEqualTo(200);
        return mapper.readTree(raw);
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

    private static JsonNode team(JsonNode snapshot, String name) {
        for (JsonNode t : snapshot.path("teams")) {
            if (name.equals(t.path("name").asString())) {
                return t;
            }
        }
        throw new AssertionError("no team named " + name);
    }

    private static java.util.List<String> names(JsonNode teamNode) {
        java.util.List<String> out = new java.util.ArrayList<>();
        teamNode.path("players").forEach(p -> out.add(p.path("name").asString()));
        return out;
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
