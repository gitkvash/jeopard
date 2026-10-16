package ge.jeopard.backend.game;

import ge.jeopard.backend.game.GameDtos.*;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.messaging.converter.JacksonJsonMessageConverter;
import org.springframework.messaging.simp.stomp.StompHeaders;
import org.springframework.messaging.simp.stomp.StompSession;
import org.springframework.messaging.simp.stomp.StompSessionHandlerAdapter;
import org.springframework.test.context.TestPropertySource;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.messaging.WebSocketStompClient;

import java.time.Duration;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Whoever pressed first gets the buzzer -- not whichever request the server
 * happened to finish first.
 *
 * <p>Presses are handed to the service with explicit arrival stamps, so each
 * test controls exactly when every press "arrived" and in what order the server
 * got round to it. The window closes a fixed time after the first press's
 * stamp, so a stamp a little in the future buys a test time to act inside it.
 *
 * <p>Runs on the default window (150 ms) and compensation (250 ms), and on the
 * same properties as {@link ConcurrencyTest}: every distinct set is another
 * cached context holding another pool of connections, and the shared Postgres
 * runs out of them.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestPropertySource(properties = "jeopard.limits.games-per-hour-per-ip=0")
class BuzzFairnessTest {

    private static final long MS = 1_000_000L;

    @Autowired
    GameService games;

    @LocalServerPort
    int port;

    @Test
    @DisplayName("the press that arrived first wins, even when the server reaches it second")
    void arrivalOrderBeatsProcessingOrder() throws Exception {
        Room room = openRoom();
        long t = System.nanoTime();

        // B is processed first but arrived 30 ms after A.
        CompletableFuture<Snapshot> b = games.buzz(room.gameId, room.b.playerToken(), null, t + 40 * MS);
        CompletableFuture<Snapshot> a = games.buzz(room.gameId, room.a.playerToken(), null, t + 10 * MS);

        assertWon(a, room.a);
        assertLost(b);
    }

    @Test
    @DisplayName("a slow connection does not cost a faster reaction the buzzer")
    void reactionTimeMakesUpForNetworkDelay() throws Exception {
        Room room = openRoom();
        long t = System.nanoTime();

        // A's press reached the server first, but A took 100 ms to react; B
        // reacted in 30 ms and was simply further away.
        CompletableFuture<Snapshot> a = games.buzz(room.gameId, room.a.playerToken(), 100L, t + 60 * MS);
        CompletableFuture<Snapshot> b = games.buzz(room.gameId, room.b.playerToken(), 30L, t + 120 * MS);

        assertWon(b, room.b);
        assertLost(a);
    }

    @Test
    @DisplayName("a device claiming an impossible reaction is only believed so far")
    void doctoredReactionTimeIsCapped() throws Exception {
        Room room = openRoom();
        long t = System.nanoTime();

        // B arrives 360 ms after A and claims it reacted instantly. At most 250 ms
        // of that is believed, which still leaves B behind.
        CompletableFuture<Snapshot> a = games.buzz(room.gameId, room.a.playerToken(), 20L, t + 20 * MS);
        CompletableFuture<Snapshot> b = games.buzz(room.gameId, room.b.playerToken(), 0L, t + 380 * MS);

        assertWon(a, room.a);
        assertLost(b);
    }

    @Test
    @DisplayName("a reaction can never be claimed longer than the server saw elapse")
    void reactionTimeCannotExceedWhatTheServerSaw() throws Exception {
        Room room = openRoom();
        long t = System.nanoTime();

        // A says it took ten seconds -- it cannot have, it arrived 50 ms in.
        CompletableFuture<Snapshot> a = games.buzz(room.gameId, room.a.playerToken(), 10_000L, t + 50 * MS);
        CompletableFuture<Snapshot> b = games.buzz(room.gameId, room.b.playerToken(), null, t + 200 * MS);

        assertWon(a, room.a);
        assertLost(b);
    }

    @Test
    @DisplayName("a press made for one clue never lands on the next")
    void pressForAnOldClueCannotLandOnTheNext() throws Exception {
        Room room = openRoom();
        // Stamped ahead, so its window is still open while the host moves on.
        CompletableFuture<Snapshot> a = games.buzz(room.gameId, room.a.playerToken(), null,
                System.nanoTime() + 2_000 * MS);

        // Inside A's window, the host gives up on this clue and opens another.
        games.passClue(room.gameId, room.hostToken);
        games.next(room.gameId, room.hostToken);
        Snapshot board = games.snapshot(room.gameId, room.hostToken);
        games.selectClue(room.gameId, room.hostToken, firstAvailable(board));
        games.openBuzzer(room.gameId, room.hostToken);

        assertLost(a);
        Snapshot after = games.snapshot(room.gameId, room.hostToken);
        assertThat(after.state()).isEqualTo(GameState.BUZZ_OPEN);
        assertThat(after.buzzedTeamId()).isNull();
    }

    @Test
    @DisplayName("a teammate of the winner gets no second go in the same window")
    void oneWinnerPerWindowEvenWithinATeam() throws Exception {
        CreatedGame created = games.createGame(new CreateGameRequest(
                null, 1L, false, null, BuzzMode.HOST, null, null, null, null));
        JoinedPlayer first = games.join(created.joinCode(), new JoinRequest("ანა", null, "მთიები"));
        JoinedPlayer mate = games.join(created.joinCode(), new JoinRequest("ბექა", first.teamId(), null));
        open(created.gameId(), created.hostToken());
        long t = System.nanoTime();

        CompletableFuture<Snapshot> m = games.buzz(created.gameId(), mate.playerToken(), null, t + 20 * MS);
        CompletableFuture<Snapshot> f = games.buzz(created.gameId(), first.playerToken(), null, t + 5 * MS);

        Snapshot won = f.get(5, TimeUnit.SECONDS);
        assertThat(won.buzzedPlayerId()).isEqualTo(first.playerId());
        assertLost(m);
    }

    @Test
    @DisplayName("over the socket, the faster reaction wins although its frame came second")
    void stompBuzzIsRankedByReaction() throws Exception {
        Room room = seatRoom();
        WebSocketStompClient stomp = new WebSocketStompClient(new StandardWebSocketClient());
        stomp.setMessageConverter(new JacksonJsonMessageConverter());
        StompSession session = stomp
                .connectAsync("ws://localhost:" + port + "/ws", new StompSessionHandlerAdapter() {
                })
                .get(10, TimeUnit.SECONDS);
        try {
            open(room.gameId, room.hostToken);
            // Let some time pass since the buzzer opened, as it would for a person.
            Thread.sleep(120);
            String destination = "/app/games/" + room.gameId + "/buzz";
            session.send(destination, Map.of("playerToken", room.a.playerToken(), "reactionMs", 110));
            Thread.sleep(30);
            session.send(destination, Map.of("playerToken", room.b.playerToken(), "reactionMs", 25));

            Snapshot after = awaitBuzzed(room);
            assertThat(after.buzzedTeamId()).isEqualTo(room.b.teamId());
        } finally {
            session.disconnect();
            stomp.stop();
        }
    }

    // ------------------------------------------------------------------

    private record Room(UUID gameId, String hostToken, JoinedPlayer a, JoinedPlayer b) {
    }

    /** Two solo players, a clue up and the buzzer open. */
    private Room openRoom() {
        Room room = seatRoom();
        open(room.gameId, room.hostToken);
        return room;
    }

    /** Two solo players in the lobby. */
    private Room seatRoom() {
        CreatedGame created = games.createGame(new CreateGameRequest(
                null, 1L, false, null, BuzzMode.HOST, null, null, null, null));
        JoinedPlayer a = games.join(created.joinCode(), new JoinRequest("ანა", null, null));
        JoinedPlayer b = games.join(created.joinCode(), new JoinRequest("ბექა", null, null));
        return new Room(created.gameId(), created.hostToken(), a, b);
    }

    private void open(UUID gameId, String hostToken) {
        Snapshot snap = games.start(gameId, hostToken);
        games.selectClue(gameId, hostToken, firstAvailable(snap));
        games.openBuzzer(gameId, hostToken);
    }

    private static Long firstAvailable(Snapshot snap) {
        return snap.board().stream()
                .flatMap(c -> c.tiles().stream())
                .filter(t -> t.status() == ClueStatus.AVAILABLE)
                .findFirst()
                .orElseThrow()
                .clueId();
    }

    private Snapshot awaitBuzzed(Room room) throws InterruptedException {
        long deadline = System.nanoTime() + Duration.ofSeconds(5).toNanos();
        while (System.nanoTime() < deadline) {
            Snapshot snap = games.snapshot(room.gameId, room.hostToken);
            if (snap.state() == GameState.BUZZED) {
                return snap;
            }
            Thread.sleep(25);
        }
        throw new AssertionError("nobody's buzz was settled");
    }

    private static void assertWon(CompletableFuture<Snapshot> press, JoinedPlayer who) throws Exception {
        Snapshot snap = press.get(5, TimeUnit.SECONDS);
        assertThat(snap.state()).isEqualTo(GameState.BUZZED);
        assertThat(snap.buzzedTeamId()).isEqualTo(who.teamId());
        assertThat(snap.buzzedPlayerId()).isEqualTo(who.playerId());
    }

    private static void assertLost(CompletableFuture<Snapshot> press) {
        assertThatThrownBy(() -> press.get(5, TimeUnit.SECONDS))
                .isInstanceOf(ExecutionException.class)
                .cause()
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("another team buzzed first");
    }
}
