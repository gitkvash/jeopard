package ge.jeopard.backend.content;

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
import java.util.HashSet;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/** Random practice questions: whole cards, from the catalogue only, never cached. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestPropertySource(properties = "jeopard.limits.games-per-hour-per-ip=0")
class PracticeQuestionsTest {

    /** Where the synthetic id sequences start (V5__random_packages.sql). */
    private static final long FIRST_SYNTHETIC_ID = 1_000_000L;

    @LocalServerPort
    int port;

    @Autowired
    ObjectMapper mapper;

    private final HttpClient http = HttpClient.newHttpClient();

    @Test
    @DisplayName("a batch is whole cards, each a different clue, and is not cached")
    void wholeCards() throws Exception {
        HttpResponse<byte[]> res = get("/api/practice/questions?count=30");
        assertThat(res.statusCode()).isEqualTo(200);
        assertThat(res.headers().firstValue("Cache-Control").orElse("")).contains("no-store");

        JsonNode batch = mapper.readTree(new String(res.body(), StandardCharsets.UTF_8));
        JsonNode questions = batch.path("questions");
        assertThat(questions).hasSize(30);
        assertThat(batch.path("attribution").asString()).isNotBlank();

        Set<Long> ids = new HashSet<>();
        for (JsonNode q : questions) {
            ids.add(q.path("id").asLong());
            assertThat(q.path("question").asString()).isNotBlank();
            assertThat(q.path("answer").asString()).isNotBlank();
            assertThat(q.path("topicName").asString()).isNotBlank();
            assertThat(q.path("packageTitle").asString()).isNotBlank();
            // A board clue has a value; only a final has none.
            assertThat(q.path("value").isNull()).isEqualTo(q.path("finalRound").asBoolean());
        }
        assertThat(ids).hasSize(30);
    }

    @Test
    @DisplayName("never a copy from a random package")
    void catalogueOnly() throws Exception {
        // Make sure there is a remixed package to draw from, if the draw allowed it.
        HttpRequest make = HttpRequest.newBuilder(uri("/api/packages/random"))
                .POST(HttpRequest.BodyPublishers.noBody()).build();
        assertThat(http.send(make, HttpResponse.BodyHandlers.discarding()).statusCode()).isEqualTo(200);

        for (int i = 0; i < 5; i++) {
            JsonNode batch = mapper.readTree(new String(
                    get("/api/practice/questions?count=50").body(), StandardCharsets.UTF_8));
            for (JsonNode q : batch.path("questions")) {
                assertThat(q.path("id").asLong()).isLessThan(FIRST_SYNTHETIC_ID);
            }
        }
    }

    @Test
    @DisplayName("the size of a batch is kept within bounds")
    void boundedCount() throws Exception {
        assertThat(count("/api/practice/questions")).isEqualTo(PracticeController.DEFAULT_COUNT);
        assertThat(count("/api/practice/questions?count=0")).isEqualTo(1);
        assertThat(count("/api/practice/questions?count=5000")).isEqualTo(PracticeController.MAX_COUNT);
    }

    private int count(String path) throws Exception {
        return mapper.readTree(new String(get(path).body(), StandardCharsets.UTF_8))
                .path("questions").size();
    }

    private HttpResponse<byte[]> get(String path) throws Exception {
        return http.send(HttpRequest.newBuilder(uri(path)).GET().build(),
                HttpResponse.BodyHandlers.ofByteArray());
    }

    private URI uri(String path) {
        return URI.create("http://localhost:" + port + path);
    }
}
