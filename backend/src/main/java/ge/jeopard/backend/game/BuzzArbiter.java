package ge.jeopard.backend.game;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.TaskScheduler;
import org.springframework.web.server.ResponseStatusException;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Function;

import static org.springframework.http.HttpStatus.CONFLICT;

/**
 * Decides who pressed first.
 *
 * <p>Racing straight to the database answered a different question: whose
 * request happened to reach the UPDATE first. Every buzz did three lookups
 * before that UPDATE, each on whatever pooled connection and inbound thread it
 * drew, so a press that reached the server first could still lose to one that
 * arrived a few milliseconds later. And a phone on a sleepy Wi-Fi radio sees the
 * buzzer open late and has its press delivered late, which arrival order
 * charges to the player twice.
 *
 * <p>So a buzz is not settled on arrival. The first one opens a short window
 * ({@code jeopard.buzz.window-ms}); everything that arrives inside it is ranked,
 * and only then is the winner written -- through the same conditional UPDATE as
 * before, which stays the authority on whether a buzz may land at all.
 *
 * <p>The rank is the moment of the press, as near as the server can know it:
 *
 * <ul>
 *   <li>Without a client measurement, it is when the frame arrived, stamped
 *       before any thread pool or connection pool could reorder it.</li>
 *   <li>With one -- the device's own count from showing the open buzzer to the
 *       finger landing -- it is that reaction time, which no network delay in
 *       either direction can inflate. The device is trusted only so far: the
 *       claim can never be longer than the server saw elapse, nor shorter than
 *       that by more than {@code jeopard.buzz.max-latency-compensation-ms}. A
 *       doctored client can win a close race, never a lost one.</li>
 * </ul>
 *
 * <p>This state is per JVM, like the STOMP broker and the buzzer timer beside
 * it. A second instance would need its own arbitration, which is the rest of the
 * application's position too.
 */
final class BuzzArbiter {

    private static final Logger log = LoggerFactory.getLogger(BuzzArbiter.class);

    /** Openings older than this are of no use to anyone and are pruned. */
    private static final long STALE_OPENING_NANOS = Duration.ofHours(1).toNanos();
    private static final int PRUNE_ABOVE = 1_000;

    /** One press waiting for its window to close. */
    record Candidate(UUID teamId, UUID playerId, boolean host, long arrivedAtNanos,
                     long rankNanos, CompletableFuture<GameDtos.Snapshot> result) {
    }

    /** What settling a window produced: the winner, if any, and the snapshot to hand back. */
    record Outcome(Candidate winner, GameDtos.Snapshot snapshot) {
    }

    private record Key(UUID gameId, Long clueId) {
    }

    /** When the buzzer last went live for a clue, on this JVM's monotonic clock. */
    private record Opening(Long clueId, long atNanos) {
    }

    private static final class Window {
        final List<Candidate> candidates = new ArrayList<>();
        boolean closed;
    }

    private final TaskScheduler scheduler;
    private final long windowNanos;
    private final long maxCompensationNanos;
    private final Map<Key, Window> windows = new ConcurrentHashMap<>();
    private final Map<UUID, Opening> openings = new ConcurrentHashMap<>();

    BuzzArbiter(TaskScheduler scheduler, long windowMs, long maxCompensationMs) {
        this.scheduler = scheduler;
        this.windowNanos = Duration.ofMillis(Math.max(0, windowMs)).toNanos();
        this.maxCompensationNanos = Duration.ofMillis(Math.max(0, maxCompensationMs)).toNanos();
    }

    /**
     * The buzzer went live for {@code clueId}. Called once the state change has
     * committed, just before it is broadcast, so the server's count of elapsed
     * time is never shorter than what any device could have seen.
     */
    void opened(UUID gameId, Long clueId) {
        long now = System.nanoTime();
        openings.put(gameId, new Opening(clueId, now));
        if (openings.size() > PRUNE_ABOVE) {
            openings.values().removeIf(o -> now - o.atNanos() > STALE_OPENING_NANOS);
        }
    }

    void forget(UUID gameId) {
        openings.remove(gameId);
    }

    /**
     * Rank a press by when it happened. Earlier is better; the values only mean
     * anything relative to one another, on this JVM.
     *
     * @param reactionMs the device's own measurement from seeing the buzzer open
     *                   to the press, or null from a client that does not send it
     */
    long rank(UUID gameId, Long clueId, long arrivedAtNanos, Long reactionMs) {
        Opening opening = openings.get(gameId);
        if (opening == null || !opening.clueId().equals(clueId) || arrivedAtNanos < opening.atNanos()) {
            return arrivedAtNanos;
        }
        long elapsed = arrivedAtNanos - opening.atNanos();
        if (reactionMs == null || reactionMs < 0) {
            return arrivedAtNanos;
        }
        long claimed = Duration.ofMillis(reactionMs).toNanos();
        long floor = Math.max(0, elapsed - maxCompensationNanos);
        return opening.atNanos() + Math.clamp(claimed, floor, elapsed);
    }

    /**
     * Enter a press for the window of this clue, opening the window if it is
     * the first. The future completes once the window is settled: with the
     * snapshot for the winner, with a 409 for everyone else.
     *
     * @param settle runs once per window, with the presses best first; it owns
     *               the transaction and decides which of them, if any, still holds
     */
    CompletableFuture<GameDtos.Snapshot> submit(UUID gameId, Long clueId, Candidate candidate,
                                                Function<List<Candidate>, Outcome> settle) {
        Key key = new Key(gameId, clueId);
        while (true) {
            Window window = windows.computeIfAbsent(key, k -> new Window());
            boolean first;
            synchronized (window) {
                if (window.closed) {
                    // Settled between the lookup and the lock; start the next one.
                    windows.remove(key, window);
                    continue;
                }
                first = window.candidates.isEmpty();
                window.candidates.add(candidate);
            }
            if (first) {
                long closeAt = candidate.arrivedAtNanos() + windowNanos;
                long delay = closeAt - System.nanoTime();
                if (windowNanos == 0 || delay <= 0) {
                    close(key, window, settle);
                } else {
                    scheduler.schedule(() -> close(key, window, settle),
                            Instant.now().plusNanos(delay));
                }
            }
            return candidate.result();
        }
    }

    private void close(Key key, Window window, Function<List<Candidate>, Outcome> settle) {
        List<Candidate> ranked;
        synchronized (window) {
            window.closed = true;
            ranked = new ArrayList<>(window.candidates);
        }
        windows.remove(key, window);
        // Ties go to whoever reached the server first.
        ranked.sort(Comparator.comparingLong(Candidate::rankNanos)
                .thenComparingLong(Candidate::arrivedAtNanos));

        Outcome outcome;
        try {
            outcome = settle.apply(ranked);
        } catch (RuntimeException e) {
            log.warn("settling buzzes for game {} failed: {}", key.gameId(), e.toString());
            ranked.forEach(c -> c.result().completeExceptionally(e));
            return;
        }
        if (outcome.winner() != null) {
            openings.remove(key.gameId());
        }
        for (Candidate c : ranked) {
            if (c == outcome.winner()) {
                c.result().complete(outcome.snapshot());
            } else {
                c.result().completeExceptionally(
                        new ResponseStatusException(CONFLICT, "another team buzzed first"));
            }
        }
    }
}
