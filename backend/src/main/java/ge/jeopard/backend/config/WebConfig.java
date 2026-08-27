package ge.jeopard.backend.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * CORS for the Flutter web client. `flutter run -d chrome` picks a random port
 * each run, so origin *patterns* are used rather than fixed origins.
 */
@Configuration
public class WebConfig implements WebMvcConfigurer {

    private final String[] allowedOriginPatterns;

    WebConfig(@Value("${jeopard.cors.allowed-origin-patterns}") String[] allowedOriginPatterns) {
        this.allowedOriginPatterns = allowedOriginPatterns;
    }

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOriginPatterns(allowedOriginPatterns)
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
                .allowedHeaders("*")
                .maxAge(3600);
    }
}
