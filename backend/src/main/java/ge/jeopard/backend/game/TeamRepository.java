package ge.jeopard.backend.game;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;
import java.util.UUID;

public interface TeamRepository extends JpaRepository<Team, UUID> {

    List<Team> findByGameIdOrderBySeatAsc(UUID gameId);

    boolean existsByGameIdAndName(UUID gameId, String name);

    int countByGameId(UUID gameId);

    /**
     * The next seat to hand out is this plus one. Asked as a maximum rather than
     * a count so the answer stays right whatever happens to the rows in between;
     * the caller holds the game row, which is what stops two teams reading it.
     */
    @Query("select coalesce(max(t.seat), 0) from Team t where t.gameId = ?1")
    int maxSeat(UUID gameId);
}
