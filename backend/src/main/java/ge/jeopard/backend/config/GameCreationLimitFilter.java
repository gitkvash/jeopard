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
import java.util.concurrent.atomic.AtomicBoolean;

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

    /** So a misconfigured proxy is reported once rather than per request. */
    private final AtomicBoolean proxyWarningIssued = new AtomicBoolean();

    GameCreationLimitFilter(@Value("${jeopard.limits.games-per-hour-per-ip}") int limit) {
        this.limit = limit;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        // POST /api/games, and POST /api/packages/random which is the same kind of
        // unauthenticated row-seeding write. Anything below /api/games (start,
        // judge, buzz) already needs a token from a game that exists.
        if (!"POST".equalsIgnoreCase(request.getMethod())) {
            return true;
        }
        String uri = request.getRequestURI();
        return !("/api/games".equals(uri) || "/api/packages/random".equals(uri));
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        if (limit <= 0) {                       // 0 disables the limit entirely
            chain.doFilter(request, response);
            return;
        }

        warnIfBehindAnUntrustedProxy(request);

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
     * <p>This used to read {@code X-Forwarded-For} itself and fall back to
     * {@code getRemoteAddr()}. That inverted the limit: the header is supplied
     * by whoever is calling, so a different value on each request bought a fresh
     * allowance every time, and the one endpoint with no credentials had, in
     * effect, no ceiling either.
     *
     * <p>{@code getRemoteAddr()} cannot be forged -- it is the address the TCP
     * connection came from. Behind a proxy that address is the proxy's, and
     * making it the client's again is a deployment decision rather than this
     * filter's: {@code server.forward-headers-strategy} (set to {@code
     * framework} in deploy/docker-compose.yml) puts a filter ahead of this one
     * that rewrites {@code getRemoteAddr()} from the forwarded headers and then
     * strips them. Trusting a header is only safe when something upstream is
     * known to have written it, and only the deployment knows that.
     *
     * @see #warnIfBehindAnUntrustedProxy(HttpServletRequest)
     */
    private static String clientAddress(HttpServletRequest request) {
        return request.getRemoteAddr();
    }

    /**
     * Says so, once, if this looks like a proxy nobody told Spring about.
     *
     * <p>A forwarded header still visible here means the filter that would have
     * consumed it is not installed -- so every request is arriving from the same
     * address, the proxy's, and this limit is one shared allowance for the whole
     * internet rather than one per host. That misconfiguration is silent until
     * the thirty-first game of the hour is refused for somebody who created
     * none, which is a bad way to find out.
     */
    private void warnIfBehindAnUntrustedProxy(HttpServletRequest request) {
        if (proxyWarningIssued.get() || request.getHeader("X-Forwarded-For") == null) {
            return;
        }
        if (proxyWarningIssued.compareAndSet(false, true)) {
            log.warn("X-Forwarded-For is present but Spring is not configured to trust it, so "
                    + "every request looks like it came from {}: the game creation limit is now "
                    + "shared by all clients. Set server.forward-headers-strategy=framework.",
                    request.getRemoteAddr());
        }
    }
}
