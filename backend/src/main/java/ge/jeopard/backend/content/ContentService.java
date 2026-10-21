package ge.jeopard.backend.content;

import ge.jeopard.backend.content.ContentDtos.AvailableTopic;
import ge.jeopard.backend.content.ContentDtos.BoardTile;
import ge.jeopard.backend.content.ContentDtos.BoardTopic;
import ge.jeopard.backend.content.ContentDtos.BoardView;
import ge.jeopard.backend.content.ContentDtos.BuildPackageRequest;
import ge.jeopard.backend.content.ContentDtos.PackageSummary;
import ge.jeopard.backend.content.ContentDtos.RoundSummary;
import ge.jeopard.backend.content.ContentDtos.TopicSummary;
import ge.jeopard.backend.content.TopicRepository.TopicRef;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

import static org.springframework.http.HttpStatus.BAD_REQUEST;
import static org.springframework.http.HttpStatus.CONFLICT;
import static org.springframework.http.HttpStatus.INTERNAL_SERVER_ERROR;
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

    private volatile List<PackageSummary> packageCache;
    private volatile String packageCacheTag = "\"empty\"";
    private volatile List<AvailableTopic> availableTopicsCache;

    private final Map<Long, BoardView> boardCache;

    ContentService(PackageRepository packages, RoundRepository rounds, TopicRepository topics,
                    ClueRepository clues,
                    @Value("${jeopard.board-cache.size:256}") int maxCachedBoards) {
        this.packages = packages;
        this.rounds = rounds;
        this.topics = topics;
        this.clues = clues;
        this.boardCache = Collections.synchronizedMap(
                new LinkedHashMap<>(64, 0.75f, true) {
                    @Override
                    protected boolean removeEldestEntry(Map.Entry<Long, BoardView> eldest) {
                        return size() > maxCachedBoards;
                    }
                });
    }

    public List<PackageSummary> listPackages() {
        List<PackageSummary> cached = packageCache;
        if (cached != null) return cached;

        List<PackageSummary> fresh = packages.findAllWithRounds().stream()
                .sorted(Comparator.comparing(QuizPackage::getNumber))
                .map(p -> toSummary(p, false))
                .toList();
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

    public PackageSummary getPackage(Long packageId) {
        QuizPackage pkg = packages.findById(packageId)
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "package " + packageId + " not found"));
        return toSummary(pkg, true);
    }

    /** Topic names and tile values only -- deliberately no question/answer text. */
    public BoardView board(Long roundId) {
        BoardView cached = boardCache.get(roundId);
        if (cached != null) {
            return cached;
        }
        BoardView fresh = buildBoard(roundId);
        boardCache.put(roundId, fresh);
        return fresh;
    }

    public void invalidateBoard(Long roundId) {
        if (roundId != null) {
            boardCache.remove(roundId);
        } else {
            boardCache.clear();
        }
    }

    private BoardView buildBoard(Long roundId) {
        GameRound round = requireRound(roundId);
        List<BoardTopic> boardTopics = topics.findByRoundIdWithClues(roundId).stream()
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
    }

    private static PackageSummary toSummary(QuizPackage p, boolean includeTopics) {
        List<RoundSummary> roundSummaries = p.getRounds().stream()
                .sorted(Comparator.comparing(GameRound::getIdx))
                .map(r -> new RoundSummary(r.getId(), r.getIdx(), r.getHeader(),
                        r.isFinalRound(), r.isPlayable(), r.getTopicCount(),
                        includeTopics && r.getTopics() != null
                                ? r.getTopics().stream()
                                        .sorted(Comparator.comparing(Topic::getIdx))
                                        .map(t -> new TopicSummary(t.getId(), t.getIdx(), t.getName()))
                                        .toList()
                                : List.of()))
                .toList();
        return new PackageSummary(p.getId(), p.getNumber(), p.getTitle(), p.getSubtitle(),
                p.getSourceUrl(), p.isSynthetic(), roundSummaries);
    }

    public List<AvailableTopic> availableTopics(Integer roundIdx, String query) {
        List<AvailableTopic> all = availableTopicsCache;
        if (all == null) {
            all = topics.findAvailableTopicRefs().stream()
                    .map(r -> new AvailableTopic(
                            r.getId(),
                            r.getName(),
                            r.getRoundIdx(),
                            r.isFinalRound(),
                            r.getPackageTitle()
                    ))
                    .toList();
            availableTopicsCache = all;
        }

        final String q = query != null ? query.trim().toLowerCase() : null;
        return all.stream()
                .filter(t -> {
                    if (roundIdx != null) {
                        if (roundIdx == 4 || roundIdx > PLAYABLE_ROUNDS) {
                            if (!t.finalRound()) return false;
                        } else {
                            if (t.finalRound() || !Objects.equals(t.roundIdx(), roundIdx)) return false;
                        }
                    }
                    if (q != null && !q.isEmpty()) {
                        if (!t.name().toLowerCase().contains(q)) return false;
                    }
                    return true;
                })
                .toList();
    }

    @Transactional
    public PackageSummary generateRandomPackage() {
        return buildCustomPackage(null);
    }

    @Transactional
    public PackageSummary buildCustomPackage(BuildPackageRequest req) {
        Map<Integer, List<TopicRef>> pool = topics.findPlayableTopicRefs(PLAYABLE_ROUNDS).stream()
                .collect(Collectors.groupingBy(TopicRef::getRoundIdx));

        Set<String> chosenNames = new HashSet<>();
        Map<Integer, List<Long>> boardTopicIds = new LinkedHashMap<>();

        List<List<Long>> roundInputs = List.of(
                req != null && req.round1TopicIds() != null ? req.round1TopicIds() : List.<Long>of(),
                req != null && req.round2TopicIds() != null ? req.round2TopicIds() : List.<Long>of(),
                req != null && req.round3TopicIds() != null ? req.round3TopicIds() : List.<Long>of()
        );

        for (int idx = 1; idx <= PLAYABLE_ROUNDS; idx++) {
            List<Long> inputIds = roundInputs.get(idx - 1);
            List<Long> roundTopicIds = new ArrayList<>();
            for (Long id : inputIds) {
                if (roundTopicIds.size() >= TOPICS_PER_ROUND) break;
                if (!roundTopicIds.contains(id)) {
                    roundTopicIds.add(id);
                }
            }
            if (!roundTopicIds.isEmpty()) {
                topics.findAllById(roundTopicIds).forEach(t -> chosenNames.add(t.getName()));
            }

            int needed = TOPICS_PER_ROUND - roundTopicIds.size();
            if (needed > 0) {
                List<TopicRef> available = pool.getOrDefault(idx, List.of()).stream()
                        .filter(t -> !chosenNames.contains(t.getName()) && !roundTopicIds.contains(t.getId()))
                        .toList();
                List<Long> randomPicked = pickDistinctByNameAndExclude(available, needed, chosenNames);
                roundTopicIds.addAll(randomPicked);
            }
            boardTopicIds.put(idx, roundTopicIds);
        }

        List<Long> finalTopicIds = new ArrayList<>();
        List<Long> finalInput = req != null && req.finalTopicIds() != null ? req.finalTopicIds() : List.of();
        for (Long id : finalInput) {
            if (finalTopicIds.size() >= 2) break;
            if (!finalTopicIds.contains(id)) finalTopicIds.add(id);
        }
        if (!finalTopicIds.isEmpty()) {
            topics.findAllById(finalTopicIds).forEach(t -> chosenNames.add(t.getName()));
        }
        int finalNeeded = 2 - finalTopicIds.size();
        if (finalNeeded > 0) {
            List<TopicRef> finalPool = topics.findFinalTopicRefs().stream()
                    .filter(t -> !chosenNames.contains(t.getName()) && !finalTopicIds.contains(t.getId()))
                    .toList();
            List<Long> randomFinal = pickDistinctByNameAndExclude(finalPool, finalNeeded, chosenNames);
            finalTopicIds.addAll(randomFinal);
        }

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

        QuizPackage pkg = new QuizPackage();
        pkg.setId(packages.nextSyntheticId());
        int ordinal = Math.toIntExact(pkg.getId() - SYNTHETIC_ID_BASE + 1);
        pkg.setNumber(-ordinal);
        String customTitle = req != null && req.title() != null ? req.title().trim() : "";
        if (!customTitle.isEmpty()) {
            pkg.setTitle(customTitle);
            pkg.setSubtitle("ხელით აწყობილი პაკეტი");
        } else if (req != null && (req.round1TopicIds() != null || req.round2TopicIds() != null || req.round3TopicIds() != null || req.finalTopicIds() != null)) {
            pkg.setTitle("მორგებული პაკეტი #" + ordinal);
            pkg.setSubtitle("ხელით აწყობილი პაკეტი");
        } else {
            pkg.setTitle("შემთხვევითი პაკეტი #" + ordinal);
            pkg.setSubtitle("თემები შემთხვევითობით აღებულია ყველა პაკეტიდან");
        }
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
        return toSummary(pkg, true);
    }

    @Transactional
    public TopicSummary rerollTopic(Long packageId, Long topicId) {
        Topic topic = topics.findById(topicId)
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "topic " + topicId + " not found"));

        GameRound round = topic.getRound();
        QuizPackage pkg = round.getQuizPackage();
        if (!pkg.getId().equals(packageId)) {
            throw new ResponseStatusException(BAD_REQUEST,
                    "topic " + topicId + " does not belong to package " + packageId);
        }
        if (!pkg.isSynthetic()) {
            throw new ResponseStatusException(BAD_REQUEST,
                    "only random package categories can be changed");
        }

        Set<String> existingNames = new HashSet<>(topics.findNamesByPackageId(packageId));

        List<TopicRef> candidates;
        if (round.isFinalRound()) {
            candidates = topics.findFinalTopicRefs();
        } else {
            int roundIdx = round.getIdx();
            candidates = topics.findPlayableTopicRefs(roundIdx).stream()
                    .filter(t -> Objects.equals(t.getRoundIdx(), roundIdx))
                    .toList();
        }

        List<TopicRef> available = candidates.stream()
                .filter(t -> !existingNames.contains(t.getName()))
                .toList();

        if (available.isEmpty()) {
            available = candidates.stream()
                    .filter(t -> !Objects.equals(t.getName(), topic.getName()))
                    .toList();
        }

        if (available.isEmpty()) {
            throw new ResponseStatusException(CONFLICT, "no alternative topic available");
        }

        TopicRef chosen = available.get(random.nextInt(available.size()));
        return replaceTopicInternal(topic, round, chosen.getId());
    }

    @Transactional
    public TopicSummary replaceTopic(Long packageId, Long topicId, Long sourceTopicId) {
        if (sourceTopicId == null) {
            throw new ResponseStatusException(BAD_REQUEST, "sourceTopicId is required");
        }
        Topic topic = topics.findById(topicId)
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "topic " + topicId + " not found"));

        GameRound round = topic.getRound();
        QuizPackage pkg = round.getQuizPackage();
        if (!pkg.getId().equals(packageId)) {
            throw new ResponseStatusException(BAD_REQUEST,
                    "topic " + topicId + " does not belong to package " + packageId);
        }
        if (!pkg.isSynthetic()) {
            throw new ResponseStatusException(BAD_REQUEST,
                    "only custom/random package categories can be changed");
        }

        return replaceTopicInternal(topic, round, sourceTopicId);
    }

    private TopicSummary replaceTopicInternal(Topic topic, GameRound round, Long sourceTopicId) {
        Topic source = topics.findAllWithCluesByIdIn(List.of(sourceTopicId)).stream()
                .findFirst()
                .orElseThrow(() -> new ResponseStatusException(NOT_FOUND,
                        "failed to load source topic " + sourceTopicId));

        clues.deleteByTopicId(topic.getId());
        topic.getClues().clear();
        topic.setName(source.getName());

        Ids clueIds = new Ids(clues.nextSyntheticIds(source.getClues().size()));
        List<Clue> sortedSourceClues = source.getClues().stream()
                .sorted(BY_VALUE)
                .toList();

        int clueIdx = 0;
        for (Clue sourceClue : sortedSourceClues) {
            Clue clue = new Clue();
            clue.setId(clueIds.take());
            clue.setTopic(topic);
            if (round.isFinalRound()) {
                clue.setValue(null);
            } else {
                clue.setValue((clueIdx + 1) * round.getIdx() * 10);
            }
            clueIdx++;
            clue.setQuestion(sourceClue.getQuestion());
            clue.setAnswer(sourceClue.getAnswer());
            clue.setQuestionOriginal(sourceClue.getQuestionOriginal());
            clue.setAnswerOriginal(sourceClue.getAnswerOriginal());
            clue.setCorrectionNote(sourceClue.getCorrectionNote());
            topic.getClues().add(clue);
        }

        topics.saveAndFlush(topic);
        boardCache.remove(round.getId());

        return new TopicSummary(topic.getId(), topic.getIdx(), topic.getName());
    }

    private GameRound cloneRound(QuizPackage pkg, Long id, int idx, boolean finalRound,
                                 boolean playable, List<Long> sourceTopicIds,
                                 Map<Long, Topic> sources, Ids topicIds, Ids clueIds) {
        GameRound round = new GameRound();
        round.setId(id);
        round.setQuizPackage(pkg);
        round.setIdx(idx);
        round.setHeader(finalRound ? "ფინალური ტური" : (idx + " ტური"));
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
        List<Clue> sortedSourceClues = source.getClues().stream()
                .sorted(BY_VALUE)
                .toList();
        int clueIdx = 0;
        for (Clue sourceClue : sortedSourceClues) {
            Clue clue = new Clue();
            clue.setId(clueIds.take());
            clue.setTopic(topic);
            if (round.isFinalRound()) {
                clue.setValue(null);
            } else {
                clue.setValue((clueIdx + 1) * round.getIdx() * 10);
            }
            clueIdx++;
            clue.setQuestion(sourceClue.getQuestion());
            clue.setAnswer(sourceClue.getAnswer());
            clue.setQuestionOriginal(sourceClue.getQuestionOriginal());
            clue.setAnswerOriginal(sourceClue.getAnswerOriginal());
            clue.setCorrectionNote(sourceClue.getCorrectionNote());
            topic.getClues().add(clue);
        }
        return topic;
    }

    private List<Long> pickDistinctByNameAndExclude(List<TopicRef> pool, int count, Set<String> excludeNames) {
        List<TopicRef> shuffled = new ArrayList<>(pool);
        Collections.shuffle(shuffled, random);
        Map<String, Long> chosen = new LinkedHashMap<>();
        for (TopicRef t : shuffled) {
            if (chosen.size() >= count) break;
            if (excludeNames.contains(t.getName())) continue;
            chosen.putIfAbsent(t.getName(), t.getId());
            excludeNames.add(t.getName());
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
