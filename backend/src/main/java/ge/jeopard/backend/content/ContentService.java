package ge.jeopard.backend.content;

import ge.jeopard.backend.content.ContentDtos.BoardTile;
import ge.jeopard.backend.content.ContentDtos.BoardTopic;
import ge.jeopard.backend.content.ContentDtos.BoardView;
import ge.jeopard.backend.content.ContentDtos.PackageSummary;
import ge.jeopard.backend.content.ContentDtos.RoundSummary;
import ge.jeopard.backend.content.TopicRepository.TopicRef;
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
import java.util.Objects;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Function;
import java.util.stream.Collectors;

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

    /** Where V5's id sequences for generated content start. */
    private static final long SYNTHETIC_ID_BASE = 1_000_000L;

    private final SecureRandom random = new SecureRandom();

    private final PackageRepository packages;
    private final RoundRepository rounds;
    private final TopicRepository topics;
    private final ClueRepository clues;

    /**
     * The browsable package list, and the tag that identifies this copy of it.
     *
     * <p>Seeded content never changes while the process is up -- and the one
     * thing that does write packages, {@link #generateRandomPackage()}, writes
     * only synthetic ones, which this list excludes by definition. So the list
     * is worth building once: a fresh page load then costs no query, no DTO
     * mapping, and (thanks to the tag) often not even a response body.
     */
    private volatile List<PackageSummary> packageCache;
    private volatile String packageCacheTag = "\"empty\"";

    private final ConcurrentHashMap<Long, BoardView> boardCache = new ConcurrentHashMap<>();

    ContentService(PackageRepository packages, RoundRepository rounds, TopicRepository topics,
                    ClueRepository clues) {
        this.packages = packages;
        this.rounds = rounds;
        this.topics = topics;
        this.clues = clues;
    }

    public List<PackageSummary> listPackages() {
        List<PackageSummary> cached = packageCache;
        if (cached != null) return cached;

        List<PackageSummary> fresh = packages.findAllWithRounds().stream()
                .sorted(Comparator.comparing(QuizPackage::getNumber))
                .map(ContentService::toSummary)
                .toList();
        // Tomcat is serving before the seeder has finished its first run, so an
        // empty answer here is "not ready yet", not "no packages" -- caching it
        // would freeze the app on an empty picker for the life of the process.
        if (!fresh.isEmpty()) {
            packageCacheTag = '"' + Integer.toHexString(fresh.hashCode()) + '"';
            packageCache = fresh;
        }
        return fresh;
    }

    /** Strong ETag for {@link #listPackages()}; changes when the content does. */
    public String packagesTag() {
        listPackages();
        return packageCacheTag;
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
     *
     * <p>The host is watching a spinner while this runs, so it is written to a
     * round-trip budget rather than to whatever JPA does by default: a handful
     * of reads -- names to choose from, then only the chosen topics, then one
     * id block per table -- and a hundred and seventeen rows inserted in a few
     * JDBC batches. What it replaced asked the sequence for every id one at a
     * time and hydrated every candidate topic <em>with its clues</em> to pick
     * six of them, which is where the second of wall clock went.
     */
    @Transactional
    public PackageSummary generateRandomPackage() {
        // --- choose, using nothing heavier than topic names -------------------
        Map<Integer, List<TopicRef>> pool = topics.findPlayableTopicRefs(PLAYABLE_ROUNDS).stream()
                .collect(Collectors.groupingBy(TopicRef::getRoundIdx));

        Map<Integer, List<Long>> boardTopicIds = new LinkedHashMap<>();
        for (int idx = 1; idx <= PLAYABLE_ROUNDS; idx++) {
            boardTopicIds.put(idx, pickDistinctByName(
                    pool.getOrDefault(idx, List.of()), TOPICS_PER_ROUND));
        }

        List<Long> finalRoundIds = rounds.findFinalRoundIds();
        List<Long> finalTopicIds = finalRoundIds.isEmpty()
                ? List.of()
                : topics.findIdsByRoundId(finalRoundIds.get(random.nextInt(finalRoundIds.size())));

        // --- load only what is actually being copied --------------------------
        List<Long> chosen = new ArrayList<>(finalTopicIds);
        boardTopicIds.values().forEach(chosen::addAll);
        Map<Long, Topic> sources = topics.findAllWithCluesByIdIn(chosen).stream()
                .collect(Collectors.toMap(Topic::getId, Function.identity()));

        int roundCount = PLAYABLE_ROUNDS + (finalTopicIds.isEmpty() ? 0 : 1);
        int clueCount = chosen.stream()
                .map(sources::get)
                .filter(Objects::nonNull)
                .mapToInt(t -> t.getClues().size())
                .sum();
        Ids roundIds = new Ids(rounds.nextSyntheticIds(roundCount));
        Ids topicIds = new Ids(topics.nextSyntheticIds(chosen.size()));
        Ids clueIds = new Ids(clues.nextSyntheticIds(clueCount));

        // --- assemble ---------------------------------------------------------
        QuizPackage pkg = new QuizPackage();
        pkg.setId(packages.nextSyntheticId());
        // Numbered below zero, where seeded content can never reach. This used
        // to take the next catalogue number, which was safe only while the
        // seeder refused to touch a database that had any content; now that it
        // adds missing packages, a generated packet sitting on number 43 would
        // make seeding the real package 43 fail on a UNIQUE violation. The
        // ordinal -- first random packet, second, third -- is what the host
        // sees, and the app shows the magnitude.
        int ordinal = Math.toIntExact(pkg.getId() - SYNTHETIC_ID_BASE + 1);
        pkg.setNumber(-ordinal);
        pkg.setTitle("შემთხვევითი პაკეტი #" + ordinal);
        pkg.setSubtitle("თემები შემთხვევითობით აღებულია ყველა პაკეტიდან");
        pkg.setSynthetic(true);

        for (int idx = 1; idx <= PLAYABLE_ROUNDS; idx++) {
            pkg.getRounds().add(cloneRound(pkg, roundIds.take(), idx, false, true,
                    boardTopicIds.get(idx), sources, topicIds, clueIds));
        }
        if (!finalTopicIds.isEmpty()) {
            pkg.getRounds().add(cloneRound(pkg, roundIds.take(), PLAYABLE_ROUNDS + 1, true, false,
                    finalTopicIds, sources, topicIds, clueIds));
        }

        packages.save(pkg);
        return toSummary(pkg);
    }

    private GameRound cloneRound(QuizPackage pkg, Long id, int idx, boolean finalRound,
                                 boolean playable, List<Long> sourceTopicIds,
                                 Map<Long, Topic> sources, Ids topicIds, Ids clueIds) {
        GameRound round = new GameRound();
        round.setId(id);
        round.setQuizPackage(pkg);
        round.setIdx(idx);
        round.setFinalRound(finalRound);
        round.setPlayable(playable);

        for (Long sourceId : sourceTopicIds) {
            Topic source = sources.get(sourceId);
            if (source == null) continue;
            round.getTopics().add(cloneTopic(source, round, topicIds, clueIds));
        }
        round.setTopicCount(round.getTopics().size());
        return round;
    }

    private Topic cloneTopic(Topic source, GameRound round, Ids topicIds, Ids clueIds) {
        Topic topic = new Topic();
        topic.setId(topicIds.take());
        topic.setRound(round);
        topic.setIdx(round.getTopics().size() + 1);
        topic.setName(source.getName());
        for (Clue sourceClue : source.getClues()) {
            Clue clue = new Clue();
            clue.setId(clueIds.take());
            clue.setTopic(topic);
            clue.setValue(sourceClue.getValue());
            clue.setQuestion(sourceClue.getQuestion());
            clue.setAnswer(sourceClue.getAnswer());
            topic.getClues().add(clue);
        }
        return topic;
    }

    /** Shuffles then takes the first {@code count} topics with distinct names. */
    private List<Long> pickDistinctByName(List<TopicRef> pool, int count) {
        List<TopicRef> shuffled = new ArrayList<>(pool);
        Collections.shuffle(shuffled, random);
        Map<String, Long> chosen = new LinkedHashMap<>();
        for (TopicRef t : shuffled) {
            if (chosen.size() >= count) break;
            chosen.putIfAbsent(t.getName(), t.getId());
        }
        return new ArrayList<>(chosen.values());
    }

    /** A block of sequence values fetched in one round trip, handed out one at a time. */
    private static final class Ids {
        private final List<Long> values;
        private int next;

        Ids(List<Long> values) {
            this.values = values;
        }

        Long take() {
            return values.get(next++);
        }
    }
}
