package ge.jeopard.backend.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

/**
 * STOMP over a native WebSocket at /ws. No SockJS: every target (Chrome,
 * Android, iOS) speaks WebSocket natively, and SockJS fallback would only add
 * polling paths nobody uses.
 */
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    private final String[] allowedOriginPatterns;

    WebSocketConfig(@Value("${jeopard.ws.allowed-origin-patterns}") String[] allowedOriginPatterns) {
        this.allowedOriginPatterns = allowedOriginPatterns;
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        // Mobile clients send no Origin header, and the web client's dev port
        // changes every run, so origins are matched by pattern. A deployment
        // narrows this to its own origin; the default stays permissive so a
        // phone on the LAN keeps working.
        registry.addEndpoint("/ws").setAllowedOriginPatterns(allowedOriginPatterns);
    }

    @Override
    public void configureMessageBroker(MessageBrokerRegistry config) {
        config.setApplicationDestinationPrefixes("/app");
        config.enableSimpleBroker("/topic");
    }
}
