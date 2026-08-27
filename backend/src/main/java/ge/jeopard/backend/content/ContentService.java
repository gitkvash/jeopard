package ge.jeopard.backend.content;

import ge.jeopard.backend.content.ContentDtos.BoardTile;
import ge.jeopard.backend.content.ContentDtos.BoardTopic;
import ge.jeopard.backend.content.ContentDtos.BoardView;
import ge.jeopard.backend.content.ContentDtos.PackageSummary;
import ge.jeopard.backend.content.ContentDtos.RoundSummary;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.Comparator;
import java.util.List;

import static org.springframework.http.HttpStatus.NOT_FOUND;

@Service
@Transactional(readOnly = true)
public class ContentService {

    /** Final-round clues have a null value, so they sort first. */
    private static final Comparator<Clue> BY_VALUE =
            Comparator.comparing(Clue::getValue, Comparator.nullsFirst(Comparator.naturalOrder()));

    private final PackageRepository packages;
    private final RoundRepository rounds;
    private final TopicRepository topics;

    ContentService(PackageRepository packages, RoundRepository rounds, TopicRepository topics) {
        this.packages = packages;
        this.rounds = rounds;
        this.topics = topics;
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
}
