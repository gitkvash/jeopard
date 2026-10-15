package ge.jeopard.backend.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.SimpMessageHeaderAccessor;
import org.springframework.messaging.simp.SimpMessageType;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.messaging.support.MessageHeaderAccessor;
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

    /**
     * {@link System#nanoTime()} when a client's frame came off its socket. Read
     * by the buzz handler, which ranks presses by when they happened.
     */
    public static final String ARRIVED_AT_HEADER = "jeopardArrivedAt";

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

    /**
     * Stamp every SEND frame with its arrival time. Interceptors run on the
     * thread that read the frame, before it is handed to the inbound pool --
     * after that, frames from different players run in whatever order the pool
     * gets to them, which is not the order they arrived in.
     */
    @Override
    public void configureClientInboundChannel(ChannelRegistration registration) {
        registration.interceptors(new ChannelInterceptor() {
            @Override
            public Message<?> preSend(Message<?> message, MessageChannel channel) {
                if (SimpMessageHeaderAccessor.getMessageType(message.getHeaders())
                        != SimpMessageType.MESSAGE) {
                    return message;
                }
                MessageHeaderAccessor headers = MessageHeaderAccessor.getMutableAccessor(message);
                headers.setHeader(ARRIVED_AT_HEADER, System.nanoTime());
                return MessageBuilder.createMessage(message.getPayload(), headers.getMessageHeaders());
            }
        });
    }

    @Override
    public void configureMessageBroker(MessageBrokerRegistry config) {
        config.setApplicationDestinationPrefixes("/app");
        config.enableSimpleBroker("/topic");
    }
}
