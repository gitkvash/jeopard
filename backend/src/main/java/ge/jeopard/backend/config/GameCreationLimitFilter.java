package ge.jeopard.backend.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Duration;
import java.time.Instant;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedDeque;

/**
 * A ceiling on how many games one client may create per hour.
 *
 * <p>Creating a game is deliberately unauthenticated -- a host just opens the
 * app and picks a package -- which is fine on a LAN and is the one thing worth
 * bounding once the URL is public: each game seeds rows for a whole board, so an
 * unbounded loop against this endpoint is a cheap way to fill the database.
 * Every other write is already gated by an opaque token belonging to a game that
 * had to be created first.
 *
 * <p>In-memory and per-instance on purpose. The alternative is a shared counter
 * in Postgres, which buys correctness across replicas that this deployment does
 * not have, at the cost of a write on the hot path. If it ever runs behind more
 * than one instance, this becomes a per-instance ceiling -- still a ceiling.
 */
@Component
public class GameCreationLimitFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(GameCreationLimitFilter.class);
    private static final Duration WINDOW = Duration.ofHours(1);

    /** Bounds memory if a lot of distinct addresses show up. */
    private static final int MAX_TRACKED_CLIENTS = 10_000;

    private final int limit;
    private final Map<String, Deque<Instant>> creations = new ConcurrentHashMap<>();

    GameCreationLimitFilter(@Value("${jeopard.limits.games-per-hour-per-ip}") int limit) {
        this.limit = limit;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        // Exactly one endpoint: POST /api/games. Anything below it (start, judge,
        // buzz) already needs a token from a game that exists.
        return !("POST".equalsIgnoreCase(request.getMethod())
                && "/api/games".equals(request.getRequestURI()));
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        if (limit <= 0) {                       // 0 disables the limit entirely
            chain.doFilter(request, response);
            return;
        }

        String client = clientAddress(request);
        if (!allow(client)) {
            log.warn("game creation refused for {}: more than {} in the last hour", client, limit);
            // The servlet API predates 429 and has no constant for it.
            response.setStatus(429);
            response.setHeader("Retry-After", Long.toString(WINDOW.toSeconds()));
            response.setContentType("application/json;charset=UTF-8");
            // The client shows a server "detail" message verbatim, so this is
            // what the would-be host actually reads.
            response.getWriter().write(
                    "{\"detail\":\"ძალიან ბევრი თამაში შეიქმნა. სცადეთ ცოტა ხანში.\"}");
            return;
        }
        chain.doFilter(request, response);
    }

    /**
     * Forgets every recorded creation.
     *
     * <p>Exists for tests: the counter lives for the life of the JVM, so without
     * this one test method exhausts the limit for the next and the failure looks
     * like a product bug.
     */
    void reset() {
        creations.clear();
    }

    private boolean allow(String client) {
        if (creations.size() > MAX_TRACKED_CLIENTS) {
            creations.clear();      // crude, and only reachable under abuse
        }
        Deque<Instant> times = creations.computeIfAbsent(client, k -> new ConcurrentLinkedDeque<>());
        Instant cutoff = Instant.now().minus(WINDOW);
        synchronized (times) {
            while (!times.isEmpty() && times.peekFirst().isBefore(cutoff)) {
                times.pollFirst();
            }
            if (times.size() >= limit) {
                return false;
            }
            times.addLast(Instant.now());
            return true;
        }
    }

    /**
     * The address the request really came from.
     *
     * <p>Behind the reverse proxy every request arrives from the proxy, so the
     * limit would be global rather than per client. Spring's
     * {@code forward-headers-strategy} makes {@code getRemoteAddr()} report the
     * forwarded address, but only the first hop is trustworthy -- the rest of
     * {@code X-Forwarded-For} is client-supplied and easy to forge.
     */
    private static String clientAddress(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            int comma = forwarded.indexOf(',');
            return (comma > 0 ? forwarded.substring(0, comma) : forwarded).trim();
        }
        return request.getRemoteAddr();
    }
}
