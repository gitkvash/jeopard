package ge.jeopard.backend.content;

import ge.jeopard.backend.content.ContentDtos.BoardTile;
import ge.jeopard.backend.content.ContentDtos.BoardTopic;
import ge.jeopard.backend.content.ContentDtos.BoardView;
import ge.jeopard.backend.content.ContentDtos.PackageSummary;
import ge.jeopard.backend.content.ContentDtos.RoundSummary;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.springframework.http.HttpStatus.NOT_FOUND;

@Service
@Transactional(readOnly = true)
public class ContentService {

    /** Final-round clues have a null value, so they sort first. */
    private static final Comparator<Clue> BY_VALUE =
            Comparator.comparing(Clue::getValue, Comparator.nullsFirst(Comparator.naturalOrder()));

    /** Rounds 1-3 are the playable boards a random packet remixes topic by topic. */
    private static final int PLAYABLE_ROUNDS = 3;
    private static final int TOPICS_PER_ROUND = 6;

    private final SecureRandom random = new SecureRandom();

    private final PackageRepository packages;
    private final RoundRepository rounds;
    private final TopicRepository topics;
    private final ClueRepository clues;

    ContentService(PackageRepository packages, RoundRepository rounds, TopicRepository topics,
                    ClueRepository clues) {
        this.packages = packages;
        this.rounds = rounds;
        this.topics = topics;
        this.clues = clues;
    }

    public List<PackageSummary> listPackages() {
        return packages.findAllWithRounds().stream()
                .sorted(Comparator.comparing(QuizPackage::getNumber))
                .map(ContentService::toSummary)
                .toList();
    }

    public GameRound requireRound(Long roundId) {
        return rounds.findById(roundId)
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "round " + roundId + " not found"));
    }

    /** Where a whole-package game starts. */
    public GameRound requireFirstRound(Long packageId) {
        return rounds.findFirstByQuizPackageIdOrderByIdxAsc(packageId)
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND,
                        "package " + packageId + " has no rounds"));
    }

    /** The round following {@code idx} in a package, or null at the end. */
    public GameRound roundAfter(Long packageId, Integer idx) {
        return rounds
                .findFirstByQuizPackageIdAndIdxGreaterThanOrderByIdxAsc(packageId, idx)
                .orElse(null);
    }

    private final java.util.concurrent.ConcurrentHashMap<Long, BoardView> boardCache = new java.util.concurrent.ConcurrentHashMap<>();

    /** Topic names and tile values only -- deliberately no question/answer text. */
    public BoardView board(Long roundId) {
        return boardCache.computeIfAbsent(roundId, id -> {
            GameRound round = requireRound(id);
            List<BoardTopic> boardTopics = topics.findByRoundIdWithClues(id).stream()
                    .sorted(Comparator.comparing(Topic::getIdx))
                    .map(t -> new BoardTopic(t.getId(), t.getIdx(), t.getName(),
                            t.getClues().stream()
                                    .sorted(BY_VALUE)
                                    .map(c -> new BoardTile(c.getId(), c.getValue()))
                                    .toList()))
                    .toList();

            QuizPackage pkg = round.getQuizPackage();
            return new BoardView(round.getId(), round.getIdx(), round.isFinalRound(),
                    pkg.getNumber(), pkg.getTitle(), boardTopics);
        });
    }

    private static PackageSummary toSummary(QuizPackage p) {
        List<RoundSummary> roundSummaries = p.getRounds().stream()
                .sorted(Comparator.comparing(GameRound::getIdx))
                .map(r -> new RoundSummary(r.getId(), r.getIdx(), r.getHeader(),
                        r.isFinalRound(), r.isPlayable(), r.getTopicCount()))
                .toList();
        return new PackageSummary(p.getId(), p.getNumber(), p.getTitle(), p.getSubtitle(),
                p.getSourceUrl(), roundSummaries);
    }

    /**
     * Assembles a fresh packet by sampling topics from the existing (non-synthetic)
     * packets: six random topics per playable round, plus one final round cloned
     * whole from a random source packet. Persisted like any other packet, just
     * marked {@code synthetic} so it stays out of {@link #listPackages()}.
     */
    @Transactional
    public PackageSummary generateRandomPackage() {
        QuizPackage pkg = new QuizPackage();
        pkg.setId(packages.nextSyntheticId());
        pkg.setNumber(packages.maxNumber() + 1);
        pkg.setTitle("შემთხვევითი პაკეტი #" + pkg.getNumber());
        pkg.setSubtitle("თემები შემთხვევითობით აღებულია ყველა პაკეტიდან");
        pkg.setSynthetic(true);

        for (int idx = 1; idx <= PLAYABLE_ROUNDS; idx++) {
            GameRound round = newRound(pkg, idx, false, true);
            for (Topic source : pickDistinctByName(topics.findPlayableTopicsForRoundIdx(idx), TOPICS_PER_ROUND)) {
                round.getTopics().add(cloneTopic(source, round));
            }
            pkg.getRounds().add(round);
        }

        List<GameRound> finalPool = rounds.findFinalRounds();
        if (!finalPool.isEmpty()) {
            GameRound sourceFinal = finalPool.get(random.nextInt(finalPool.size()));
            GameRound round = newRound(pkg, PLAYABLE_ROUNDS + 1, true, false);
            for (Topic source : topics.findByRoundIdWithClues(sourceFinal.getId())) {
                round.getTopics().add(cloneTopic(source, round));
            }
            pkg.getRounds().add(round);
        }

        packages.save(pkg);
        return toSummary(pkg);
    }

    private GameRound newRound(QuizPackage pkg, int idx, boolean finalRound, boolean playable) {
        GameRound round = new GameRound();
        round.setId(rounds.nextSyntheticId());
        round.setQuizPackage(pkg);
        round.setIdx(idx);
        round.setFinalRound(finalRound);
        round.setPlayable(playable);
        round.setTopicCount(0);
        return round;
    }

    private Topic cloneTopic(Topic source, GameRound round) {
        Topic topic = new Topic();
        topic.setId(topics.nextSyntheticId());
        topic.setRound(round);
        topic.setIdx(round.getTopics().size() + 1);
        topic.setName(source.getName());
        for (Clue sourceClue : source.getClues()) {
            Clue clue = new Clue();
            clue.setId(clues.nextSyntheticId());
            clue.setTopic(topic);
            clue.setValue(sourceClue.getValue());
            clue.setQuestion(sourceClue.getQuestion());
            clue.setAnswer(sourceClue.getAnswer());
            topic.getClues().add(clue);
        }
        round.setTopicCount(round.getTopics().size() + 1);
        return topic;
    }

    /** Shuffles then takes the first {@code count} topics with distinct names. */
    private List<Topic> pickDistinctByName(List<Topic> pool, int count) {
        List<Topic> shuffled = new ArrayList<>(pool);
        Collections.shuffle(shuffled, random);
        Map<String, Topic> chosen = new LinkedHashMap<>();
        for (Topic t : shuffled) {
            if (chosen.size() >= count) break;
            chosen.putIfAbsent(t.getName(), t);
        }
        return new ArrayList<>(chosen.values());
    }
}
