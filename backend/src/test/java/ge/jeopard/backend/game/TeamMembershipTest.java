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
import java.util.LinkedHashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Several people on one team.
 *
 * <p>A team is the scoring unit; a player is a person with their own device.
 * Any member may buzz for their team, but the consequences -- score and the
 * per-clue lockout -- land on the team, not the individual.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class TeamMembershipTest {

    @LocalServerPort
    int port;

    @Autowired
    ObjectMapper mapper;

    private final HttpClient http = HttpClient.newHttpClient();

    private String gameId;
    private String hostToken;
    private String code;

    @Test
    @DisplayName("two players share a team, either may buzz, and a wrong answer locks out both")
    void teammatesShareOneBuzzerAndOneLockout() throws Exception {
        newGame(false);

        // Nino starts a team; Gio joins her rather than creating his own.
        JsonNode nino = join("ნინო", null, "მთიები");
        String ninoTeamId = nino.path("teamId").asString();
        JsonNode gio = join("გიორგი", ninoTeamId, null);
        // A rival team, so the buzzer has somewhere to go.
        JsonNode rival = join("ლევანი", null, "ვეფხვები");

        assertThat(gio.path("teamId").asString()).isEqualTo(ninoTeamId);
        assertThat(gio.path("teamName").asString()).isEqualTo("მთიები");

        JsonNode snap = host("start", null);
        // Three players, but only two scoring teams.
        assertThat(snap.path("teams")).hasSize(2);
        JsonNode mtiebi = team(snap, "მთიები");
        assertThat(mtiebi.path("players")).hasSize(2);
        assertThat(names(mtiebi)).containsExactly("ნინო", "გიორგი");

        long clueId = firstAvailableTile(snap);
        host("select-clue", "{\"clueId\":" + clueId + "}");
        host("open-buzzer", null);

        // Nino buzzes; the snapshot names both her team and her personally.
        snap = buzz(nino.path("playerToken").asString(), 200);
        assertThat(snap.path("buzzedTeamId").asString()).isEqualTo(ninoTeamId);
        assertThat(snap.path("buzzedPlayerId").asString())
                .isEqualTo(nino.path("playerId").asString());

        // Wrong: the whole team is docked and locked out, not just Nino.
        snap = host("judge", "{\"correct\":false}");
        assertThat(snap.path("state").asString()).isEqualTo("BUZZ_OPEN");
        assertThat(team(snap, "მთიები").path("score").asInt()).isNegative();
        assertThat(team(snap, "მთიები").path("lockedOutOnCurrentClue").asBoolean()).isTrue();

        // Gio is on that team, so his buzzer is dead for this clue too -- this is
        // the rule that would break if the lockout were per player.
        buzz(gio.path("playerToken").asString(), 409);

        // The rival team is unaffected and can take the clue.
        snap = buzz(rival.path("playerToken").asString(), 200);
        assertThat(snap.path("buzzedPlayerId").asString())
                .isEqualTo(rival.path("playerId").asString());
        snap = host("judge", "{\"correct\":true}");
        assertThat(team(snap, "ვეფხვები").path("score").asInt()).isPositive();
    }

    @Test
    @DisplayName("the lobby lists teams with their members so a player can pick one")
    void lobbyListsTeamsAndMembers() throws Exception {
        newGame(false);
        JsonNode a = join("ანა", null, "პირველი");
        join("ბექა", a.path("teamId").asString(), null);
        join("ცისკარა", null, "მეორე");

        JsonNode lobby = get("/api/games/" + code + "/lobby");
        assertThat(lobby.path("teams")).hasSize(2);

        JsonNode first = lobby.path("teams").get(0);
        assertThat(first.path("name").asString()).isEqualTo("პირველი");
        assertThat(first.path("memberNames")).hasSize(2);

        // No credentials leak through the lobby -- it is an unauthenticated view.
        assertThat(lobby.toString()).doesNotContain("token");
    }

    @Test
    @DisplayName("player names are unique per game, but a team may be reused")
    void playerNamesAreUnique() throws Exception {
        newGame(false);
        JsonNode a = join("ანა", null, "გუნდი");

        // Same person name twice is refused...
        assertThat(joinStatus("ანა", a.path("teamId").asString(), null)).isEqualTo(409);
        // ...as is a duplicate team name...
        assertThat(joinStatus("სხვა", null, "გუნდი")).isEqualTo(409);
        // ...and joining must name exactly one of team id or new team.
        assertThat(joinStatus("კიდევ", null, null)).isEqualTo(400);
        assertThat(joinStatus("კიდევ", a.path("teamId").asString(), "მესამე")).isEqualTo(400);
    }

    @Test
    @DisplayName("a playing host is a player on their own team")
    void playingHostIsAPlayer() throws Exception {
        JsonNode created = newGame(true);
        assertThat(created.path("hostPlayerToken").asString()).isNotBlank();
        assertThat(created.path("hostTeamId").asString()).isNotBlank();

        join("სტუმარი", null, "სტუმრები");
        JsonNode snap = host("start", null);

        JsonNode hostTeam = null;
        for (JsonNode t : snap.path("teams")) {
            if (t.path("host").asBoolean()) {
                hostTeam = t;
            }
        }
        assertThat(hostTeam).isNotNull();
        assertThat(hostTeam.path("players")).hasSize(1);
        assertThat(hostTeam.path("players").get(0).path("host").asBoolean()).isTrue();
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    private JsonNode newGame(boolean hostPlays) throws Exception {
        JsonNode created = post("/api/games",
                "{\"packageId\":1,\"hostPlays\":" + hostPlays + "}", null);
        gameId = created.path("gameId").asString();
        hostToken = created.path("hostToken").asString();
        code = created.path("joinCode").asString();
        return created;
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
