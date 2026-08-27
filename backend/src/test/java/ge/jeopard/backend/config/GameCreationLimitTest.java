package ge.jeopard.backend.config;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.TestPropertySource;
import tools.jackson.databind.ObjectMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Creating a game needs no credentials, which is fine on a LAN and is the one
 * thing worth bounding on a public URL: each game seeds a whole board, so an
 * unbounded loop against it fills the database.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestPropertySource(properties = "jeopard.limits.games-per-hour-per-ip=3")
class GameCreationLimitTest {

    @LocalServerPort
    int port;

    @Autowired
    ObjectMapper mapper;

    @Autowired
    GameCreationLimitFilter filter;

    @BeforeEach
    void clearTheCounter() {
        // The counter outlives a test method, so without this the first test to
        // reach the limit fails the next one.
        filter.reset();
    }

    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    @Test
    @DisplayName("a client may create games up to the limit, then is refused")
    void limitsGameCreation() throws Exception {
        for (int i = 1; i <= 3; i++) {
            assertThat(createGame().statusCode())
                    .as("creation %d of 3 should be allowed", i)
                    .isEqualTo(200);
        }

        HttpResponse<String> refused = createGame();
        assertThat(refused.statusCode()).isEqualTo(429);
        assertThat(refused.headers().firstValue("Retry-After")).isPresent();
        // The client renders the server's own "detail" verbatim, so the host
        // reads this rather than a status code.
        assertThat(mapper.readTree(refused.body()).path("detail").asString())
                .isNotBlank();
    }

    @Test
    @DisplayName("the limit applies to creation only, not to playing")
    void doesNotTouchOtherEndpoints() throws Exception {
        // A game that exists can still be driven however much it needs to be;
        // every other write is gated by a token anyway.
        HttpResponse<String> created = createGame();
        assertThat(created.statusCode()).isEqualTo(200);

        var body = mapper.readTree(created.body());
        String gameId = body.path("gameId").asString();
        String hostToken = body.path("hostToken").asString();

        for (int i = 0; i < 5; i++) {
            HttpResponse<String> lookup = http.send(
                    HttpRequest.newBuilder(uri("/api/games/" + gameId)).GET().build(),
                    HttpResponse.BodyHandlers.ofString());
            assertThat(lookup.statusCode()).isEqualTo(200);
        }
        assertThat(hostToken).isNotBlank();
    }

    private HttpResponse<String> createGame() throws Exception {
        HttpRequest request = HttpRequest.newBuilder(uri("/api/games"))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(
                        "{\"packageId\":1,\"hostPlays\":false}"))
                .build();
        return http.send(request, HttpResponse.BodyHandlers.ofString());
    }

    private URI uri(String path) {
        return URI.create("http://localhost:" + port + path);
    }
}
