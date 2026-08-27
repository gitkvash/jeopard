package ge.jeopard.backend.game;

import ge.jeopard.backend.game.GameDtos.BuzzRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.messaging.handler.annotation.DestinationVariable;
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
 */
@Controller
public class BuzzController {

    private static final Logger log = LoggerFactory.getLogger(BuzzController.class);

    private final GameService gameService;

    BuzzController(GameService gameService) {
        this.gameService = gameService;
    }

    @MessageMapping("/games/{gameId}/buzz")
    public void buzz(@DestinationVariable UUID gameId, BuzzRequest request) {
        try {
            gameService.buzz(gameId, request.playerToken());
        } catch (RuntimeException e) {
            // Losing the race is the common case, not an error worth escalating.
            log.debug("buzz rejected for game {}: {}", gameId, e.getMessage());
        }
    }
}
