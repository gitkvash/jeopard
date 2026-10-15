package ge.jeopard.backend.game;

import ge.jeopard.backend.config.WebSocketConfig;
import ge.jeopard.backend.game.GameDtos.BuzzRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.messaging.handler.annotation.DestinationVariable;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.stereotype.Controller;

import java.util.UUID;

/**
 * STOMP entry point for buzzing -- the one action that has to be as low-latency
 * as possible, so it skips HTTP.
 *
 * <p>Losers are told implicitly: the snapshot broadcast that follows names the
 * winning team, so a client that buzzed and does not see itself in
 * {@code buzzedTeamId} knows it lost the race. That avoids a per-user reply
 * channel for information every client is about to receive anyway.
 *
 * <p>Nothing here waits for the outcome: the press is handed to the arbiter and
 * this inbound thread is free for the next frame at once.
 */
@Controller
public class BuzzController {

    private static final Logger log = LoggerFactory.getLogger(BuzzController.class);

    private final GameService gameService;

    BuzzController(GameService gameService) {
        this.gameService = gameService;
    }

    /**
     * @param arrivedAt when the frame came off the socket, stamped by
     *                  {@link WebSocketConfig} before the inbound pool could
     *                  reorder it against other players' frames
     */
    @MessageMapping("/games/{gameId}/buzz")
    public void buzz(@DestinationVariable UUID gameId, BuzzRequest request,
                     @Header(name = WebSocketConfig.ARRIVED_AT_HEADER, required = false) Long arrivedAt) {
        long at = arrivedAt == null ? System.nanoTime() : arrivedAt;
        try {
            gameService.buzz(gameId, request.playerToken(), request.reactionMs(), at)
                    .whenComplete((snap, e) -> {
                        if (e != null) {
                            log.debug("buzz lost for game {}: {}", gameId, e.getMessage());
                        }
                    });
        } catch (RuntimeException e) {
            // Losing the race is the common case, not an error worth escalating.
            log.debug("buzz rejected for game {}: {}", gameId, e.getMessage());
        }
    }
}
