package ge.jeopard.backend.game;

import ge.jeopard.backend.content.Clue;
import ge.jeopard.backend.content.Attribution;
import ge.jeopard.backend.content.ClueRepository;
import ge.jeopard.backend.content.ContentDtos;
import ge.jeopard.backend.content.ContentService;
import ge.jeopard.backend.content.GameRound;
import ge.jeopard.backend.content.QuizPackage;
import ge.jeopard.backend.config.SchedulingConfig;
import ge.jeopard.backend.game.GameDtos.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.scheduling.TaskScheduler;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.*;

import static org.springframework.http.HttpStatus.*;

/**
 * Owns all game state transitions. Every mutating method loads the game with a
 * pessimistic row lock, so simultaneous buzzes are serialised by the database
 * rather than by JVM-local synchronisation.
 */
@Service
public class GameService {

    /** Default name for a playing host: "მასპინძელი" (host). */
    private static final String DEFAULT_HOST_TEAM_NAME =
            "მასპინძელი";

    /** No I/O/0/1 -- these get misread when someone reads a code out loud. */
    private static final String CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

    /**
     * States in which the clue question is public -- the floor everyone gets.
     * A game can narrow this further with {@link Game#isQuestionsVisibleToParticipants()},
     * which only ever removes it from a participant's own device; it never
     * widens what these states already allow, and it never touches the host.
     */
    private static final Set<GameState> QUESTION_VISIBLE = EnumSet.of(
            GameState.CLUE_READING, GameState.BUZZ_OPEN, GameState.BUZZED,
            GameState.RESOLVED, GameState.FINAL_CLUE, GameState.FINAL_RESULT);

    /**
     * Bounds on an automatic buzzer. One second is the shortest delay that is
     * meaningfully different from opening with the clue; two minutes is longer
     * than any clue takes to read, and the ceiling keeps a typo from parking a
     * scheduler thread for an afternoon.
     */
    static final int MIN_BUZZ_DELAY_SECONDS = 1;
    static final int MAX_BUZZ_DELAY_SECONDS = 120;

    private static final Logger log = LoggerFactory.getLogger(GameService.class);

    private final SecureRandom random = new SecureRandom();

    private final GameRepository games;
    private final TeamRepository teams;
    private final PlayerRepository players;
    private final GameClueRepository gameClues;
    private final ClueLockoutRepository lockouts;
    private final ClueRepository clues;
    private final ContentService content;
    private final Attribution attribution;
    private final SimpMessagingTemplate broker;
    private final TaskScheduler scheduler;

    /**
     * The automatic buzzer fires on a scheduler thread: no request, no proxy,
     * and so no {@code @Transactional} to inherit. That work opens its own
     * transaction through this.
     */
    private final TransactionTemplate transactions;

    GameService(GameRepository games,
                TeamRepository teams,
                PlayerRepository players,
                GameClueRepository gameClues,
                ClueLockoutRepository lockouts,
                ClueRepository clues,
                ContentService content,
                Attribution attribution,
                SimpMessagingTemplate broker,
                @Qualifier(SchedulingConfig.BUZZ_TIMER) TaskScheduler scheduler,
                PlatformTransactionManager transactionManager) {
        this.games = games;
        this.teams = teams;
        this.players = players;
        this.gameClues = gameClues;
        this.lockouts = lockouts;
        this.clues = clues;
        this.content = content;
        this.attribution = attribution;
        this.broker = broker;
        this.scheduler = scheduler;
        this.transactions = new TransactionTemplate(transactionManager);
    }

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    @Transactional
    public CreatedGame createGame(CreateGameRequest req) {
        if ((req.packageId() == null) == (req.roundId() == null)) {
            throw new ResponseStatusException(BAD_REQUEST,
                    "supply exactly one of packageId or roundId");
        }

        // A packageId means play the lot: boards 1-3 then the final, scores
        // carried across. A roundId means just that one round.
        boolean wholePackage = req.packageId() != null;
        GameRound round = wholePackage
                ? content.requireFirstRound(req.packageId())
                : content.requireRound(req.roundId());

        Game game = new Game();
        game.setId(UUID.randomUUID());
        game.setJoinCode(uniqueJoinCode());
        game.setQuizPackage(round.getQuizPackage());
        game.setRound(round);
        game.setProgressRounds(wholePackage);
        game.setHostToken(newToken());
        game.setHostPlays(req.hostPlays());
        game.setBuzzMode(req.buzzMode() == null ? BuzzMode.INSTANT : req.buzzMode());
        game.setBuzzDelaySeconds(buzzDelayFor(game.getBuzzMode(), req.buzzDelaySeconds()));
        game.setQuestionsVisibleToParticipants(req.questionsVisibleToParticipants() == null
                ? true
                : req.questionsVisibleToParticipants());
        game.setState(GameState.LOBBY);
        games.save(game);

        seedTiles(game, round);

        UUID hostTeamId = null;
        UUID hostPlayerId = null;
        String hostPlayerToken = null;
        if (req.hostPlays()) {
            String name = (req.hostTeamName() == null || req.hostTeamName().isBlank())
                    ? DEFAULT_HOST_TEAM_NAME
                    : req.hostTeamName().trim();
            Team hostTeam = addTeam(game.getId(), name);
            Player hostPlayer = addPlayer(game.getId(), hostTeam.getId(), name, true);
            hostTeamId = hostTeam.getId();
            hostPlayerId = hostPlayer.getId();
            hostPlayerToken = hostPlayer.getToken();
        }

        return new CreatedGame(game.getId(), game.getJoinCode(), game.getHostToken(),
                hostTeamId, hostPlayerId, hostPlayerToken);
    }

    /** What a joining player needs in order to choose a team. */
    @Transactional(readOnly = true)
    public LobbyView lobby(String joinCode) {
        Game game = requireByCode(joinCode);
        List<TeamOption> options = teams.findByGameIdOrderBySeatAsc(game.getId()).stream()
                .map(t -> new TeamOption(t.getId(), t.getName(), t.getSeat(), t.getScore(),
                        players.findByTeamIdOrderByJoinedAtAsc(t.getId()).stream()
                                .map(Player::getName)
                                .toList()))
                .toList();
        return new LobbyView(game.getId(), game.getJoinCode(), game.getState(), options);
    }

    /**
     * A person joins: they name themselves, then either join an existing team or
     * start a new one. Several players may share a team, so identity here is the
     * player name -- the team name is not unique to one device.
     *
     * <p>The game row is locked for the whole of this, because everything below
     * reads the room before writing to it: whether a name is taken, and how many
     * teams there are (which is the next seat). A roomful of people scanning the
     * host's code join within the same second, so without the lock they all read
     * the same empty room -- twelve simultaneous joins produced ten teams
     * claiming seat 1. The lock is on this game's row, so a busy lobby never
     * slows a game in the next room.
     */
    @Transactional
    public JoinedPlayer join(String joinCode, JoinRequest req) {
        Game game = requireByCodeForUpdate(joinCode);

        if (game.getState() != GameState.LOBBY && game.getState() != GameState.BOARD) {
            throw new ResponseStatusException(CONFLICT, "game is mid-clue; join between clues");
        }
        boolean hasNewTeam = req.newTeamName() != null && !req.newTeamName().isBlank();
        if ((req.teamId() == null) == !hasNewTeam) {
            throw new ResponseStatusException(BAD_REQUEST,
                    "supply exactly one of teamId or newTeamName");
        }

        String playerName = req.name().trim();
        if (players.existsByGameIdAndName(game.getId(), playerName)) {
            throw new ResponseStatusException(CONFLICT, "that player name is taken");
        }

        Team team;
        if (req.teamId() != null) {
            team = teams.findById(req.teamId())
                    .filter(t -> t.getGameId().equals(game.getId()))
                    .orElseThrow(() -> new ResponseStatusException(NOT_FOUND,
                            "no such team in this game"));
        } else {
            String teamName = req.newTeamName().trim();
            if (teams.existsByGameIdAndName(game.getId(), teamName)) {
                throw new ResponseStatusException(CONFLICT, "that team name is taken");
            }
            team = addTeam(game.getId(), teamName);
        }

        Player player = addPlayer(game.getId(), team.getId(), playerName, false);
        broadcastAfterCommit(game.getId());
        return new JoinedPlayer(game.getId(), player.getId(), player.getToken(),
                player.getName(), team.getId(), team.getName(), team.getSeat());
    }

    @Transactional
    public Snapshot start(UUID gameId, String hostToken) {
        Game game = lockAndAuthorise(gameId, hostToken);
        expect(game, GameState.LOBBY);
        if (teams.countByGameId(gameId) == 0) {
            throw new ResponseStatusException(CONFLICT, "no teams have joined yet");
        }
        game.setState(game.getRound().isFinalRound() ? GameState.FINAL_WAGER : GameState.BOARD);
        bump(game);
        return snapshotAndBroadcast(game);
    }

    // ------------------------------------------------------------------
    // Board flow
    // ------------------------------------------------------------------

    @Transactional
    public Snapshot selectClue(UUID gameId, String hostToken, Long clueId) {
        Game game = lockAndAuthorise(gameId, hostToken);
        boolean finalRound = game.getRound().isFinalRound();
        expect(game, finalRound ? GameState.FINAL_WAGER : GameState.BOARD);

        GameClue tile = gameClues.findByGameIdAndClueId(gameId, clueId)
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "that clue is not on this board"));
        if (tile.getStatus() != ClueStatus.AVAILABLE) {
            throw new ResponseStatusException(CONFLICT, "that tile has already been played");
        }
        if (finalRound && game.getCurrentClue() != null) {
            throw new ResponseStatusException(CONFLICT, "final clue already chosen");
        }

        tile.setStatus(ClueStatus.IN_PLAY);
        game.setCurrentClue(clues.findById(clueId).orElseThrow());
        clearBuzz(game);
        game.setAnswerRevealed(false);
        game.setAnswerPeeked(false);
        // In the final round the topic is shown for wagering but the question
        // stays hidden, so the state does not advance here.
        if (!finalRound) {
            game.setState(GameState.CLUE_READING);
            armBuzzer(game);
        }
        bump(game);
        return snapshotAndBroadcast(game);
    }

    /**
     * Decide when the buzzer opens for the clue that has just gone up.
     *
     * <p>In {@link BuzzMode#HOST} nothing happens here and the host presses the
     * button, as it always was. {@link BuzzMode#INSTANT} skips the reading
     * state entirely. {@link BuzzMode#TIMER} records the deadline and books the
     * work; that booking lives only in this JVM, so a restart mid-clue leaves
     * the clue open with the host's button still there to fall back on.
     */
    private void armBuzzer(Game game) {
        game.setBuzzOpensAt(null);
        if (eligibleTeamCount(game) == 0) {
            return;
        }
        switch (game.getBuzzMode()) {
            case HOST -> {
            }
            case INSTANT -> game.setState(GameState.BUZZ_OPEN);
            case TIMER -> {
                Instant at = Instant.now().plusSeconds(game.getBuzzDelaySeconds());
                game.setBuzzOpensAt(at);
                scheduleAutoOpen(game.getId(), game.getCurrentClue().getId(), at);
            }
        }
    }

    /** Book the automatic open, but only once the clue is really committed. */
    private void scheduleAutoOpen(UUID gameId, Long clueId, Instant at) {
        Runnable task = () -> openBuzzerOnTimer(gameId, clueId);
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            scheduler.schedule(task, at);
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                scheduler.schedule(task, at);
            }
        });
    }

    /**
     * The reading time ran out. Opens the buzzer for the clue this timer was
     * set for -- and for nothing else: by now the host may have opened it
     * themselves, passed, or moved on, and every one of those leaves this a
     * no-op rather than a buzzer opening on the wrong clue.
     */
    void openBuzzerOnTimer(UUID gameId, Long clueId) {
        try {
            transactions.executeWithoutResult(status -> {
                Game game = games.findByIdForUpdate(gameId).orElse(null);
                if (game == null
                        || game.getState() != GameState.CLUE_READING
                        || game.getCurrentClue() == null
                        || !Objects.equals(game.getCurrentClue().getId(), clueId)
                        || eligibleTeamCount(game) == 0) {
                    return;
                }
                clearBuzz(game);
                game.setState(GameState.BUZZ_OPEN);
                game.setBuzzOpensAt(null);
                bump(game);
                snapshotAndBroadcast(game);
            });
        } catch (RuntimeException e) {
            // A failed timer must not take the scheduler thread down with it;
            // the host's button is still there.
            log.warn("automatic buzzer failed for game {} clue {}: {}", gameId, clueId, e.toString());
        }
    }

    /** Host has finished reading the clue aloud; the buzzer goes live. */
    @Transactional
    public Snapshot openBuzzer(UUID gameId, String hostToken) {
        Game game = lockAndAuthorise(gameId, hostToken);
        if (game.getState() != GameState.CLUE_READING && game.getState() != GameState.BUZZED) {
            throw new ResponseStatusException(CONFLICT,
                    "cannot open the buzzer from " + game.getState());
        }
        requireClueInPlay(game);
        if (eligibleTeamCount(game) == 0) {
            throw new ResponseStatusException(CONFLICT, "every team is locked out on this clue");
        }
        clearBuzz(game);
        game.setState(GameState.BUZZ_OPEN);
        game.setBuzzOpensAt(null);
        bump(game);
        return snapshotAndBroadcast(game);
    }

    /**
     * First buzz wins, and the database decides which one that is.
     *
     * <p>The checks below are the fast, friendly path: they turn the ordinary
     * refusals into an explanation the player can read. None of them is what
     * makes the race safe -- {@link GameRepository#claimBuzz} re-tests every
     * condition that matters inside one conditional UPDATE, so a buzz that
     * passed a check a millisecond before the state moved still loses.
     */
    @Transactional
    public Snapshot buzz(UUID gameId, String playerToken) {
        Game game = games.findById(gameId)
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "no such game"));
        Player player = players.findByGameIdAndToken(gameId, playerToken)
                .orElseThrow(() -> new ResponseStatusException(FORBIDDEN,
                        "not a player in this game"));

        if (game.getState() != GameState.BUZZ_OPEN) {
            throw new ResponseStatusException(CONFLICT, "buzzer is not open");
        }
        if (game.getBuzzedTeamId() != null) {
            throw new ResponseStatusException(org.springframework.http.HttpStatus.CONFLICT, "another team buzzed first");
        }
        Long clueId = requireClueInPlay(game).getId();
        // The lockout belongs to the team, so a teammate cannot retry a clue
        // their team has already answered wrong.
        if (lockouts.existsByGameIdAndClueIdAndTeamId(gameId, clueId, player.getTeamId())) {
            throw new ResponseStatusException(org.springframework.http.HttpStatus.CONFLICT,
                    "that team already had a turn on this clue");
        }
        if (player.isHost() && game.isAnswerPeeked()) {
            throw new ResponseStatusException(org.springframework.http.HttpStatus.CONFLICT, "host looked at the answer on this clue");
        }

        int updated = games.claimBuzz(gameId, player.getTeamId(), player.getId(), clueId,
                player.isHost(), GameState.BUZZ_OPEN, GameState.BUZZED);
        if (updated == 0) {
            throw new ResponseStatusException(org.springframework.http.HttpStatus.CONFLICT, "another team buzzed first");
        }

        game = games.findById(gameId).orElseThrow();
        return snapshotAndBroadcast(game);
    }

    /**
     * Host rules on the spoken answer. A wrong answer deducts the value, locks
     * that team out of this clue, and reopens the buzzer for whoever is left.
     */
    @Transactional
    public Snapshot judge(UUID gameId, String hostToken, boolean correct) {
        Game game = lockAndAuthorise(gameId, hostToken);
        expect(game, GameState.BUZZED);
        Clue clue = requireClueInPlay(game);
        UUID buzzed = game.getBuzzedTeamId();
        Team team = teams.findById(buzzed)
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "buzzed team is gone"));
        int value = clue.getValue() == null ? 0 : clue.getValue();

        if (correct) {
            team.setScore(team.getScore() + value);
            game.setPickingTeamId(team.getId());
            resolve(game, clue, team.getId());
        } else {
            team.setScore(team.getScore() - value);
            lockouts.save(new ClueLockout(gameId, clue.getId(), team.getId()));
            clearBuzz(game);
            if (eligibleTeamCount(game) > 0) {
                game.setState(GameState.BUZZ_OPEN);   // second team gets a shot
            } else {
                resolve(game, clue, null);            // nobody left, show the answer
            }
        }
        bump(game);
        return snapshotAndBroadcast(game);
    }

    /** Nobody buzzed (or the host gives up): burn the tile and show the answer. */
    @Transactional
    public Snapshot passClue(UUID gameId, String hostToken) {
        Game game = lockAndAuthorise(gameId, hostToken);
        if (game.getState() != GameState.CLUE_READING && game.getState() != GameState.BUZZ_OPEN) {
            throw new ResponseStatusException(CONFLICT, "cannot pass from " + game.getState());
        }
        Clue clue = requireClueInPlay(game);
        clearBuzz(game);
        resolve(game, clue, null);
        bump(game);
        return snapshotAndBroadcast(game);
    }

    /** Make the answer public without judging (host decides to just show it). */
    @Transactional
    public Snapshot reveal(UUID gameId, String hostToken) {
        Game game = lockAndAuthorise(gameId, hostToken);
        Clue clue = requireClueInPlay(game);
        if (game.getState() == GameState.FINAL_CLUE) {
            game.setAnswerRevealed(true);
        } else {
            resolve(game, clue, null);
        }
        bump(game);
        return snapshotAndBroadcast(game);
    }

    /**
     * Host-only answer lookup, used to judge. When the host is also playing,
     * looking costs them the buzzer on this clue -- that is what keeps
     * host-plays mode honest without needing a second device.
     */
    @Transactional
    public RevealedAnswer peekAnswer(UUID gameId, String hostToken) {
        Game game = lockAndAuthorise(gameId, hostToken);
        Clue clue = requireClueInPlay(game);

        boolean penalty = false;
        if (game.isHostPlays() && !game.isAnswerRevealed() && !game.isAnswerPeeked()) {
            game.setAnswerPeeked(true);
            penalty = true;
            bump(game);
            snapshotAndBroadcast(game);
        }
        return new RevealedAnswer(clue.getId(), clue.getAnswer(), clue.getCorrectionNote(), penalty);
    }

    /** Clear the clue and go back to the board, or finish if the board is empty. */
    @Transactional
    public Snapshot next(UUID gameId, String hostToken) {
        Game game = lockAndAuthorise(gameId, hostToken);
        if (game.getState() != GameState.RESOLVED && game.getState() != GameState.FINAL_RESULT) {
            throw new ResponseStatusException(CONFLICT, "cannot advance from " + game.getState());
        }
        boolean wasFinal = game.getState() == GameState.FINAL_RESULT;
        game.setCurrentClue(null);
        clearBuzz(game);
        game.setAnswerRevealed(false);
        game.setAnswerPeeked(false);

        int remaining = gameClues.countByGameIdAndStatus(gameId, ClueStatus.AVAILABLE);
        if (!wasFinal && remaining > 0) {
            game.setState(GameState.BOARD);
        } else if (game.isProgressRounds() && advanceRound(game)) {
            // Scores and teams stay; only the board changes.
        } else {
            game.setState(GameState.FINISHED);
        }
        bump(game);
        return snapshotAndBroadcast(game);
    }

    // ------------------------------------------------------------------
    // Final round (no buzzer -- every team answers, host judges each)
    // ------------------------------------------------------------------

    @Transactional
    public Snapshot setWager(UUID gameId, String playerToken, int amount) {
        Game game = games.findByIdForUpdate(gameId)
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "no such game"));
        expect(game, GameState.FINAL_WAGER);
        Player player = players.findByGameIdAndToken(gameId, playerToken)
                .orElseThrow(() -> new ResponseStatusException(FORBIDDEN,
                        "not a player in this game"));
        // Any member may set it -- the wager belongs to the team.
        Team team = teams.findById(player.getTeamId())
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "team is gone"));

        // Standard rule: you cannot stake more than you have.
        int max = Math.max(0, team.getScore());
        team.setWager(Math.clamp(amount, 0, max));
        bump(game);
        return snapshotAndBroadcast(game);
    }

    /** All wagers are in; reveal the final question. */
    @Transactional
    public Snapshot openFinalClue(UUID gameId, String hostToken) {
        Game game = lockAndAuthorise(gameId, hostToken);
        expect(game, GameState.FINAL_WAGER);
        requireClueInPlay(game);
        game.setState(GameState.FINAL_CLUE);
        bump(game);
        return snapshotAndBroadcast(game);
    }

    /**
     * Apply one team's wager. A lockout row doubles as the "already judged"
     * marker here -- the final round has no buzzer, so the meaning is the same:
     * this team is done with this clue.
     */
    @Transactional
    public Snapshot finalJudge(UUID gameId, String hostToken, UUID teamId, boolean correct) {
        Game game = lockAndAuthorise(gameId, hostToken);
        expect(game, GameState.FINAL_CLUE);
        Clue clue = requireClueInPlay(game);
        Team team = teams.findById(teamId)
                .filter(t -> t.getGameId().equals(gameId))
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "no such team"));

        if (lockouts.existsByGameIdAndClueIdAndTeamId(gameId, clue.getId(), teamId)) {
            throw new ResponseStatusException(CONFLICT, "that team is already judged");
        }
        int wager = team.getWager() == null ? 0 : team.getWager();
        team.setScore(team.getScore() + (correct ? wager : -wager));
        lockouts.save(new ClueLockout(gameId, clue.getId(), teamId));

        if (lockouts.findByGameIdAndClueId(gameId, clue.getId()).size()
                >= teams.countByGameId(gameId)) {
            game.setAnswerRevealed(true);
            game.setState(GameState.FINAL_RESULT);
            gameClues.findByGameIdAndClueId(gameId, clue.getId())
                    .ifPresent(t -> t.setStatus(ClueStatus.DONE));
        }
        bump(game);
        return snapshotAndBroadcast(game);
    }

    // ------------------------------------------------------------------
    // Snapshots
    // ------------------------------------------------------------------

    /**
     * @param hostToken the caller's claimed host token, or null. Matching this
     *                  game's own is what lifts {@link Snapshot#currentClue()}'s
     *                  question past {@link Game#isQuestionsVisibleToParticipants()}
     *                  -- a wrong or absent token gets exactly what a team's own
     *                  device would.
     */
    @Transactional(readOnly = true)
    public Snapshot snapshot(UUID gameId, String hostToken) {
        Game game = games.findById(gameId)
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "no such game"));
        return buildSnapshot(game, matchesHostToken(game, hostToken));
    }

    @Transactional(readOnly = true)
    public Snapshot snapshotByCode(String joinCode, String hostToken) {
        Game game = requireByCode(joinCode);
        return buildSnapshot(game, matchesHostToken(game, hostToken));
    }

    /**
     * @param forHost true to show the clue question regardless of
     *                {@link Game#isQuestionsVisibleToParticipants()}. Only ever
     *                true for a caller who has already proved they hold the
     *                host token -- see {@link #matchesHostToken}.
     */
    private Snapshot buildSnapshot(Game game, boolean forHost) {
        UUID gameId = game.getId();
        Clue current = game.getCurrentClue();

        List<UUID> lockedOut = current == null
                ? List.of()
                : lockouts.findTeamIds(gameId, current.getId());

        Map<UUID, List<PlayerView>> byTeam = new HashMap<>();
        UUID hostTeamId = null;
        for (Player p : players.findByGameIdOrderByJoinedAtAsc(gameId)) {
            byTeam.computeIfAbsent(p.getTeamId(), k -> new ArrayList<>())
                    .add(new PlayerView(p.getId(), p.getName(), p.isHost()));
            if (p.isHost()) {
                hostTeamId = p.getTeamId();
            }
        }
        final UUID hostTeam = hostTeamId;

        List<TeamView> teamViews = teams.findByGameIdOrderBySeatAsc(gameId).stream()
                .map(t -> new TeamView(t.getId(), t.getName(), t.getScore(),
                        t.getId().equals(hostTeam), t.getSeat(), t.getWager(),
                        lockedOut.contains(t.getId()),
                        byTeam.getOrDefault(t.getId(), List.of())))
                .toList();

        Map<Long, GameClue> byClue = new HashMap<>();
        for (GameClue gc : gameClues.findByGameId(gameId)) {
            byClue.put(gc.getClueId(), gc);
        }

        ContentDtos.BoardView board = content.board(game.getRound().getId());
        List<BoardColumn> columns = board.topics().stream()
                .map(t -> new BoardColumn(t.id(), t.idx(), t.name(),
                        t.tiles().stream()
                                .map(tile -> {
                                    GameClue gc = byClue.get(tile.clueId());
                                    return new TileView(tile.clueId(), tile.value(),
                                            gc == null ? ClueStatus.AVAILABLE : gc.getStatus(),
                                            gc == null ? null : gc.getWonByTeamId());
                                })
                                .toList()))
                .toList();

        CurrentClue currentView = null;
        if (current != null) {
            boolean showQuestion = QUESTION_VISIBLE.contains(game.getState())
                    && (forHost || game.isQuestionsVisibleToParticipants());
            currentView = new CurrentClue(
                    current.getId(),
                    current.getTopic().getName(),
                    current.getValue(),
                    showQuestion ? current.getQuestion() : null,
                    game.isAnswerRevealed() ? current.getAnswer() : null,
                    game.isAnswerRevealed() ? current.getCorrectionNote() : null,
                    lockedOut);
        }

        GameRound round = game.getRound();
        return new Snapshot(gameId, game.getJoinCode(), game.getState(), game.isHostPlays(),
                round.getId(), round.getIdx(), round.isFinalRound(), game.isProgressRounds(),
                board.packageNumber(), board.packageTitle(),
                teamViews, columns, currentView,
                game.getBuzzedTeamId(), game.getBuzzedPlayerId(), game.getPickingTeamId(),
                game.isAnswerRevealed(), game.isAnswerPeeked(),
                gameClues.countByGameIdAndStatus(gameId, ClueStatus.AVAILABLE),
                game.getBuzzMode(), game.getBuzzDelaySeconds(), buzzOpensInMs(game),
                game.isQuestionsVisibleToParticipants(),
                game.getEventSeq(), attribution.text());
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    /**
     * Reading time for an automatic buzzer, refused rather than silently
     * defaulted: a game that opens its own buzzer after a number the host never
     * chose is worse than one that will not start.
     */
    private static int buzzDelayFor(BuzzMode mode, Integer requested) {
        if (mode != BuzzMode.TIMER) {
            return 0;
        }
        if (requested == null
                || requested < MIN_BUZZ_DELAY_SECONDS
                || requested > MAX_BUZZ_DELAY_SECONDS) {
            throw new ResponseStatusException(BAD_REQUEST,
                    "buzzDelaySeconds must be " + MIN_BUZZ_DELAY_SECONDS + "-"
                            + MAX_BUZZ_DELAY_SECONDS + " when buzzMode is TIMER");
        }
        return requested;
    }

    /** Put every clue of a round onto this game's board. */
    private void seedTiles(Game game, GameRound round) {
        gameClues.saveAll(clues.findByRoundId(round.getId()).stream()
                .map(c -> new GameClue(game.getId(), c.getId()))
                .toList());
    }

    /**
     * Move to the next round of the package, keeping teams and scores. Returns
     * false when the package is finished.
     */
    private boolean advanceRound(Game game) {
        QuizPackage pkg = game.getQuizPackage();
        GameRound next = content.roundAfter(pkg.getId(), game.getRound().getIdx());
        if (next == null) {
            return false;
        }
        game.setRound(next);
        seedTiles(game, next);
        // Wagers belong to a single final round.
        for (Team t : teams.findByGameIdOrderBySeatAsc(game.getId())) {
            t.setWager(null);
        }
        game.setState(next.isFinalRound() ? GameState.FINAL_WAGER : GameState.BOARD);
        return true;
    }

    /** Enter RESOLVED: the tile is spent and the answer becomes public. */
    private void resolve(Game game, Clue clue, UUID wonBy) {
        gameClues.findByGameIdAndClueId(game.getId(), clue.getId()).ifPresent(tile -> {
            tile.setStatus(ClueStatus.DONE);
            tile.setWonByTeamId(wonBy);
        });
        game.setAnswerRevealed(true);
        game.setState(GameState.RESOLVED);
        game.setBuzzOpensAt(null);
    }

    /**
     * What is left of the reading time, or null when nothing is counting --
     * which is every mode but TIMER, and TIMER once the buzzer is open.
     */
    private static Long buzzOpensInMs(Game game) {
        if (game.getState() != GameState.CLUE_READING || game.getBuzzOpensAt() == null) {
            return null;
        }
        long left = Duration.between(Instant.now(), game.getBuzzOpensAt()).toMillis();
        return Math.max(0L, left);
    }

    /** Teams that could still buzz on the clue in play. */
    private int eligibleTeamCount(Game game) {
        Clue clue = game.getCurrentClue();
        if (clue == null) {
            return 0;
        }
        List<UUID> lockedOut = lockouts.findTeamIds(game.getId(), clue.getId());
        UUID hostTeamId = game.isAnswerPeeked()
                ? players.findFirstByGameIdAndHostIsTrue(game.getId())
                        .map(Player::getTeamId).orElse(null)
                : null;
        return (int) teams.findByGameIdOrderBySeatAsc(game.getId()).stream()
                .filter(t -> !lockedOut.contains(t.getId()))
                .filter(t -> !t.getId().equals(hostTeamId))
                .count();
    }

    /**
     * Only ever called with this game's row locked -- by {@link #createGame},
     * which has just inserted it, or by {@link #join}, which locks it. That is
     * what makes reading the highest seat and then taking the next one safe.
     */
    private Team addTeam(UUID gameId, String name) {
        Team team = new Team();
        team.setId(UUID.randomUUID());
        team.setGameId(gameId);
        team.setName(name);
        team.setSeat(teams.maxSeat(gameId) + 1);
        return teams.save(team);
    }

    private Player addPlayer(UUID gameId, UUID teamId, String name, boolean host) {
        Player player = new Player();
        player.setId(UUID.randomUUID());
        player.setGameId(gameId);
        player.setTeamId(teamId);
        player.setName(name);
        player.setToken(newToken());
        player.setHost(host);
        return players.save(player);
    }

    private Game requireByCode(String joinCode) {
        return games.findByJoinCode(normalise(joinCode))
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND,
                        "no game with that code"));
    }

    /** As {@link #requireByCode}, holding the row until the transaction ends. */
    private Game requireByCodeForUpdate(String joinCode) {
        return games.findByJoinCodeForUpdate(normalise(joinCode))
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND,
                        "no game with that code"));
    }

    private static String normalise(String joinCode) {
        return joinCode.trim().toUpperCase(Locale.ROOT);
    }

    private static void clearBuzz(Game game) {
        game.setBuzzedTeamId(null);
        game.setBuzzedPlayerId(null);
    }

    private Game lockAndAuthorise(UUID gameId, String hostToken) {
        Game game = games.findByIdForUpdate(gameId)
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "no such game"));
        if (!matchesHostToken(game, hostToken)) {
            throw new ResponseStatusException(FORBIDDEN, "host token required");
        }
        return game;
    }

    /**
     * Same comparison {@link #lockAndAuthorise} enforces, but as a boolean
     * rather than a refusal -- what a read-only snapshot fetch needs, since a
     * team polling with no token at all is a normal request, not a forbidden
     * one, and should just get the team's own view back.
     */
    private static boolean matchesHostToken(Game game, String hostToken) {
        byte[] want = game.getHostToken().getBytes(StandardCharsets.UTF_8);
        byte[] got = hostToken == null ? new byte[0] : hostToken.getBytes(StandardCharsets.UTF_8);
        return MessageDigest.isEqual(want, got);
    }

    private static void expect(Game game, GameState expected) {
        if (game.getState() != expected) {
            throw new ResponseStatusException(CONFLICT,
                    "expected " + expected + " but game is " + game.getState());
        }
    }

    private static Clue requireClueInPlay(Game game) {
        Clue clue = game.getCurrentClue();
        if (clue == null) {
            throw new ResponseStatusException(CONFLICT, "no clue is in play");
        }
        return clue;
    }

    private static void bump(Game game) {
        game.setEventSeq(game.getEventSeq() + 1);
    }

    /**
     * Every mutating action shares this, the host-only ones alongside
     * {@code buzz} and {@code setWager}, which a team calls with its own
     * player token -- so this always builds the team's own view, never the
     * host's, regardless of which of those called it. The host's screen gets
     * the question separately, over {@link #snapshot}, with its token.
     */
    private Snapshot snapshotAndBroadcast(Game game) {
        Snapshot snap = buildSnapshot(game, false);
        publishAfterCommit(game.getId(), snap);
        return snap;
    }

    private void broadcastAfterCommit(UUID gameId) {
        Game game = games.findById(gameId)
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "no such game"));
        publishAfterCommit(gameId, buildSnapshot(game, false));
    }

    /** Publish only once the transaction really committed. */
    private void publishAfterCommit(UUID gameId, Snapshot snap) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            broker.convertAndSend("/topic/games/" + gameId, snap);
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                broker.convertAndSend("/topic/games/" + gameId, snap);
            }
        });
    }

    private String uniqueJoinCode() {
        for (int attempt = 0; attempt < 50; attempt++) {
            StringBuilder sb = new StringBuilder(6);
            for (int i = 0; i < 6; i++) {
                sb.append(CODE_ALPHABET.charAt(random.nextInt(CODE_ALPHABET.length())));
            }
            String code = sb.toString();
            if (!games.existsByJoinCode(code)) {
                return code;
            }
        }
        throw new ResponseStatusException(INTERNAL_SERVER_ERROR, "could not allocate a join code");
    }

    private String newToken() {
        byte[] buf = new byte[24];
        random.nextBytes(buf);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(buf);
    }
}
