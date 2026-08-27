package ge.jeopard.backend.content;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;
import org.springframework.stereotype.Component;
import tools.jackson.databind.ObjectMapper;

import java.io.InputStream;

/**
 * The credit line that must accompany the questions, read straight out of
 * pilot.json rather than copied into source. The questions come from the
 * moazrovne.net archive and belong to their authors, so this string has to be
 * shown wherever they are used -- keeping one source of truth avoids a
 * transcription slip in a script the developer cannot proofread at a glance.
 */
@Component
public class Attribution {

    private static final String FALLBACK = "moazrovne.net";

    private final String text;
    private final String source;

    Attribution(ResourceLoader resourceLoader,
                ObjectMapper objectMapper,
                @Value("${jeopard.seed.resource:classpath:pilot.json}") String seedLocation) {
        String loadedText = FALLBACK;
        String loadedSource = FALLBACK;
        Resource resource = resourceLoader.getResource(seedLocation);
        if (resource.exists()) {
            try (InputStream in = resource.getInputStream()) {
                var root = objectMapper.readTree(in);
                loadedText = root.path("attribution").asString(FALLBACK);
                loadedSource = root.path("source").asString(FALLBACK);
            } catch (Exception e) {
                // Fall back to the bare source name; never fail startup over a credit line.
                loadedText = FALLBACK;
            }
        }
        this.text = loadedText;
        this.source = loadedSource;
    }

    public String text() {
        return text;
    }

    public String source() {
        return source;
    }
}
