package ge.jeopard.backend.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.PessimisticLockingFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * Turns the two database failures that a race can still produce into an answer
 * a player can read.
 *
 * <p>The service checks before it writes -- is this name taken, has this team
 * had its turn -- and those checks are made reliable by locking the game row.
 * This is the layer underneath: if a check is ever outrun, the constraint in
 * Postgres holds, and what arrives here is a driver exception that Spring would
 * otherwise answer with 500. A player who typed a name someone else was typing
 * at the same moment has not caused a server error; they have lost a race, and
 * the right thing to tell them is to pick another name.
 *
 * <p>Deliberately narrow: only these two, so a genuine bug still surfaces as a
 * 500 rather than being dressed up as a conflict.
 */
@RestControllerAdvice
public class ApiErrorHandler {

    private static final Logger log = LoggerFactory.getLogger(ApiErrorHandler.class);

    /** "That is taken" -- a unique constraint that the pre-check did not catch. */
    @ExceptionHandler(DataIntegrityViolationException.class)
    ProblemDetail onConstraintViolation(DataIntegrityViolationException e) {
        log.warn("constraint violation answered as a conflict: {}", e.getMostSpecificCause().toString());
        return ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT,
                "ეს სახელი უკვე დაკავებულია — აირჩიეთ სხვა");
    }

    /**
     * The row lock could not be taken. Postgres only reports this on a deadlock
     * or a lock timeout, neither of which this application should produce -- but
     * a retry is a better answer than a stack trace.
     */
    @ExceptionHandler(PessimisticLockingFailureException.class)
    ProblemDetail onLockFailure(PessimisticLockingFailureException e) {
        log.warn("lock could not be taken: {}", e.getMostSpecificCause().toString());
        return ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT,
                "სცადეთ ხელახლა");
    }
}
