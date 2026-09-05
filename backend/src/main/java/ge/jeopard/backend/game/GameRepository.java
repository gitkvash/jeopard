package ge.jeopard.backend.game;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

import java.util.Optional;
import java.util.UUID;

public interface GameRepository extends JpaRepository<Game, UUID> {

    Optional<Game> findByJoinCode(String joinCode);

    boolean existsByJoinCode(String joinCode);

    /**
     * SELECT ... FOR UPDATE. Every host action that changes the game takes this
     * first, so two of them queue rather than interleave, and the lock is on the
     * game row -- so it serialises one room without touching any other. Buzzing
     * takes {@link #claimBuzz} instead, which needs no lock at all.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select g from Game g where g.id = ?1")
    Optional<Game> findByIdForUpdate(UUID id);

    /**
     * The same lock, for the one write that arrives knowing only the join code.
     *
     * <p>Joining reads the room (which names are taken, how many teams there
     * are) and then writes to it, and a roomful of people scan the host's code
     * within the same second. Without the lock those reads are all taken before
     * any of the writes land: twelve people joining together produced ten teams
     * on seat 1 and two duplicate-name inserts that failed at the constraint.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select g from Game g where g.joinCode = ?1")
    Optional<Game> findByJoinCodeForUpdate(String joinCode);

    /**
     * Take the buzz, if it is still there to take.
     *
     * <p>One conditional UPDATE rather than a read followed by a write: the
     * database evaluates the WHERE clause against the committed row, so of any
     * number of simultaneous buzzes exactly one updates a row and the rest
     * update none. The losers are told by the count, not by a lock they waited
     * on, which is why a burst of buzzes does not queue.
     *
     * <p>{@code hostPeeked} carries the one condition that is not visible in the
     * game row alone: a playing host who has looked at the answer is out of this
     * clue. It is passed in rather than read first because reading it first is
     * exactly the race -- the peek can commit between the read and the update.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update Game g
               set g.buzzedTeamId = :teamId,
                   g.buzzedPlayerId = :playerId,
                   g.state = :newState,
                   g.eventSeq = g.eventSeq + 1
             where g.id = :gameId
               and g.state = :oldState
               and g.buzzedTeamId is null
               and (:buzzerIsHost = false or g.answerPeeked = false)
               and not exists (
                     select l.teamId from ClueLockout l
                      where l.gameId = g.id
                        and l.clueId = :clueId
                        and l.teamId = :teamId)
            """)
    int claimBuzz(UUID gameId, UUID teamId, UUID playerId, Long clueId,
                  boolean buzzerIsHost, GameState oldState, GameState newState);
}
