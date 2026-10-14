package ge.jeopard.backend.game;

import ge.jeopard.backend.game.GameDtos.*;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

/**
 * Host and team actions.
 *
 * <p>Host-only endpoints require the {@code X-Host-Token} handed out at game
 * creation. That token is the only thing standing between a player and the
 * answers, so it is never included in any broadcast.
 */
@RestController
@RequestMapping("/api/games")
public class GameController {

    private static final String HOST_TOKEN = "X-Host-Token";

    private final GameService gameService;

    GameController(GameService gameService) {
        this.gameService = gameService;
    }

    // ---------- setup ----------

    @PostMapping
    public CreatedGame create(@Valid @RequestBody CreateGameRequest req) {
        return gameService.createGame(req);
    }

    /**
     * A person joins the game. They name themselves and either pick an existing
     * team by id or create one with {@code newTeamName} -- several players can
     * share a team, each with their own buzzer.
     */
    @PostMapping("/{joinCode}/players")
    public JoinedPlayer join(@PathVariable String joinCode, @Valid @RequestBody JoinRequest req) {
        return gameService.join(joinCode, req);
    }

    /**
     * A player moving themselves before the game starts: onto another team, onto
     * a new one, or -- supplying neither -- out of their team and on their own.
     */
    @PostMapping("/{gameId}/team")
    public Snapshot changeTeam(@PathVariable UUID gameId, @Valid @RequestBody ChangeTeamRequest req) {
        return gameService.changeOwnTeam(gameId, req.playerToken(), req.teamId(), req.newTeamName());
    }

    /** A player voluntarily leaving the game. */
    @PostMapping("/{gameId}/leave")
    @ResponseStatus(org.springframework.http.HttpStatus.NO_CONTENT)
    public void leave(@PathVariable UUID gameId, @Valid @RequestBody LeaveRequest req) {
        gameService.leave(gameId, req.playerToken());
    }

    /** The teams available to join, so a player can choose one. */
    @GetMapping("/{joinCode}/lobby")
    public LobbyView lobby(@PathVariable String joinCode) {
        return gameService.lobby(joinCode);
    }

    /**
     * The host token is optional here, unlike every host action below: a team
     * polls this same endpoint with none at all, and should get its own view
     * back rather than a 403. Supplying the right one is what lifts the clue
     * question past {@link GameDtos.Snapshot#questionsVisibleToParticipants()}.
     */
    @GetMapping("/{gameId}")
    public Snapshot snapshot(@PathVariable UUID gameId,
                              @RequestHeader(value = HOST_TOKEN, required = false) String hostToken) {
        return gameService.snapshot(gameId, hostToken);
    }

    /** Lets a team that only knows the code find the game to subscribe to. */
    @GetMapping("/by-code/{joinCode}")
    public Snapshot snapshotByCode(@PathVariable String joinCode,
                                    @RequestHeader(value = HOST_TOKEN, required = false) String hostToken) {
        return gameService.snapshotByCode(joinCode, hostToken);
    }

    // ---------- host actions ----------

    @PostMapping("/{gameId}/start")
    public Snapshot start(@PathVariable UUID gameId, @RequestHeader(HOST_TOKEN) String token) {
        return gameService.start(gameId, token);
    }

    @PostMapping("/{gameId}/select-clue")
    public Snapshot selectClue(@PathVariable UUID gameId,
                               @RequestHeader(HOST_TOKEN) String token,
                               @Valid @RequestBody SelectClueRequest req) {
        return gameService.selectClue(gameId, token, req.clueId());
    }

    /**
     * A player choosing the tile on their team's turn, in a game that lets the
     * players pick. The same outcome as the host's {@code select-clue}, but
     * authorised by a player token and refused out of turn.
     */
    @PostMapping("/{gameId}/pick-clue")
    public Snapshot pickClue(@PathVariable UUID gameId, @Valid @RequestBody PickClueRequest req) {
        return gameService.pickClue(gameId, req.playerToken(), req.clueId());
    }

    @PostMapping("/{gameId}/open-buzzer")
    public Snapshot openBuzzer(@PathVariable UUID gameId, @RequestHeader(HOST_TOKEN) String token) {
        return gameService.openBuzzer(gameId, token);
    }

    @PostMapping("/{gameId}/judge")
    public Snapshot judge(@PathVariable UUID gameId,
                          @RequestHeader(HOST_TOKEN) String token,
                          @RequestBody JudgeRequest req) {
        return gameService.judge(gameId, token, req.correct());
    }

    /** Set a buzz aside unjudged: the buzzer reopens for everyone, no points move. */
    @PostMapping("/{gameId}/skip-buzz")
    public Snapshot skipBuzz(@PathVariable UUID gameId, @RequestHeader(HOST_TOKEN) String token) {
        return gameService.skipBuzz(gameId, token);
    }

    @PostMapping("/{gameId}/teams/{teamId}/score")
    public Snapshot setScore(@PathVariable UUID gameId,
                             @PathVariable UUID teamId,
                             @RequestHeader(HOST_TOKEN) String token,
                             @Valid @RequestBody SetScoreRequest req) {
        return gameService.setScore(gameId, token, teamId, req.score());
    }

    /** Move a person to a team, a new team, or on their own -- supply neither field for that. */
    @PostMapping("/{gameId}/players/{playerId}/move")
    public Snapshot movePlayer(@PathVariable UUID gameId,
                               @PathVariable UUID playerId,
                               @RequestHeader(HOST_TOKEN) String token,
                               @Valid @RequestBody MovePlayerRequest req) {
        return gameService.movePlayer(gameId, token, playerId, req.teamId(), req.newTeamName());
    }

    @PostMapping("/{gameId}/pass")
    public Snapshot pass(@PathVariable UUID gameId, @RequestHeader(HOST_TOKEN) String token) {
        return gameService.passClue(gameId, token);
    }

    @PostMapping("/{gameId}/reveal")
    public Snapshot reveal(@PathVariable UUID gameId, @RequestHeader(HOST_TOKEN) String token) {
        return gameService.reveal(gameId, token);
    }

    /**
     * Host-only answer lookup used for judging. When the host is also playing,
     * this costs them the buzzer on the current clue.
     */
    @PostMapping("/{gameId}/peek")
    public RevealedAnswer peek(@PathVariable UUID gameId, @RequestHeader(HOST_TOKEN) String token) {
        return gameService.peekAnswer(gameId, token);
    }

    @PostMapping("/{gameId}/next")
    public Snapshot next(@PathVariable UUID gameId, @RequestHeader(HOST_TOKEN) String token) {
        return gameService.next(gameId, token);
    }

    // ---------- buzzing ----------

    /**
     * REST fallback for the STOMP buzz. Same locking path, so it is equally
     * race-safe -- handy for scripted tests and for clients whose WebSocket
     * dropped.
     */
    @PostMapping("/{gameId}/buzz")
    public Snapshot buzz(@PathVariable UUID gameId, @Valid @RequestBody BuzzRequest req) {
        return gameService.buzz(gameId, req.playerToken());
    }

    // ---------- final round ----------

    @PostMapping("/{gameId}/wager")
    public Snapshot wager(@PathVariable UUID gameId, @Valid @RequestBody WagerRequest req) {
        return gameService.setWager(gameId, req.playerToken(), req.wager());
    }

    @PostMapping("/{gameId}/open-final")
    public Snapshot openFinal(@PathVariable UUID gameId, @RequestHeader(HOST_TOKEN) String token) {
        return gameService.openFinalClue(gameId, token);
    }

    @PostMapping("/{gameId}/final-judge")
    public Snapshot finalJudge(@PathVariable UUID gameId,
                               @RequestHeader(HOST_TOKEN) String token,
                               @Valid @RequestBody FinalJudgeRequest req) {
        return gameService.finalJudge(gameId, token, req.teamId(), req.correct());
    }

    @PostMapping("/{gameId}/topics/{topicId}/reroll")
    public Snapshot rerollTopic(@PathVariable UUID gameId,
                                @PathVariable Long topicId,
                                @RequestHeader(HOST_TOKEN) String token) {
        return gameService.rerollTopic(gameId, token, topicId);
    }

    @DeleteMapping("/{gameId}")
    @ResponseStatus(org.springframework.http.HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID gameId, @RequestHeader(HOST_TOKEN) String token) {
        gameService.deleteGame(gameId, token);
    }

    @PostMapping("/{gameId}/end")
    @ResponseStatus(org.springframework.http.HttpStatus.NO_CONTENT)
    public void end(@PathVariable UUID gameId, @RequestHeader(HOST_TOKEN) String token) {
        gameService.deleteGame(gameId, token);
    }
}
