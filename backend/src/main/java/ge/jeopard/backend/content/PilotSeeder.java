package ge.jeopard.backend.content;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/**
 * Loads data/pilot.json (copied to the classpath) into Postgres, on first start
 * and on any start that brings packages the database does not have yet.
 *
 * <p>The JSON is produced by {@code src/build_pilot_db.py}; this walks the same
 * package -&gt; round -&gt; topic -&gt; clue nesting and assigns ids in the same
 * order, so row ids line up with data/pilot.db.
 *
 * <p><b>Content, not structure.</b> A package the database already has keeps its
 * rounds, topics, tiles and ids exactly as they are -- this never adds a clue to
 * an existing board or takes one away. What it does do is bring the wording of
 * those clues up to date, so a package can gain a new question and a seeded one
 * can gain a correction without emptying the content tables and deleting every
 * game along with them.
 *
 * <p>That works only because ids are positional rather than generated: the nth
 * package in the file is always id n. Reordering the file, or inserting a
 * package anywhere but the end, would renumber everything after it and silently
 * repoint live games at different clues. {@code src/merge_packets.py} appends,
 * which is what keeps that true.
 *
 * <p>Uses Jackson 3 ({@code tools.jackson.*}) as shipped with Spring Boot 4.
 */
@Component
public class PilotSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(PilotSeeder.class);

    private final PackageRepository packages;
    private final ClueRepository clues;
    private final ResourceLoader resourceLoader;
    private final ObjectMapper objectMapper;
    private final String seedLocation;

    PilotSeeder(PackageRepository packages,
                ClueRepository clues,
                ResourceLoader resourceLoader,
                ObjectMapper objectMapper,
                @Value("${jeopard.seed.resource:classpath:pilot.json}") String seedLocation) {
        this.packages = packages;
        this.clues = clues;
        this.resourceLoader = resourceLoader;
        this.objectMapper = objectMapper;
        this.seedLocation = seedLocation;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) throws Exception {
        Resource resource = resourceLoader.getResource(seedLocation);
        if (!resource.exists()) {
            log.error("seed resource {} not found -- no content loaded", seedLocation);
            return;
        }

        JsonNode root;
        try (InputStream in = resource.getInputStream()) {
            root = objectMapper.readTree(in);
        }

        // Ids are positional: the nth package in the file is always id n, and
        // its rounds, topics and clues follow in file order. That is what makes
        // adding a package to a database that already has some safe -- every
        // package keeps the ids a seed-from-empty would have given it, so a
        // game that points at clue 3,900 goes on meaning the same clue.
        Set<Long> present = new HashSet<>(packages.findAllIds());

        long pid = 0;
        long rid = 0;
        long tid = 0;
        long cid = 0;
        long corrected = 0;
        long boards = 0;
        long finals = 0;
        long added = 0;
        long skipped = 0;
        Map<Long, Clue> fromFile = new HashMap<>();

        for (JsonNode pkgNode : root.path("packages")) {
            QuizPackage pkg = new QuizPackage();
            pkg.setId(++pid);
            pkg.setNumber(pkgNode.path("number").asInt());
            pkg.setTitle(pkgNode.path("title").asString());
            pkg.setSubtitle(text(pkgNode, "subtitle"));
            pkg.setSourceUrl(text(pkgNode, "source_url"));

            for (JsonNode roundNode : pkgNode.path("rounds")) {
                GameRound round = new GameRound();
                round.setId(++rid);
                round.setQuizPackage(pkg);
                round.setIdx(roundNode.path("index").asInt());
                round.setHeader(text(roundNode, "header"));
                round.setFinalRound(roundNode.path("is_final").asBoolean(false));
                round.setPlayable(roundNode.path("playable").asBoolean(false));

                JsonNode topicsNode = roundNode.path("topics");
                round.setTopicCount(topicsNode.size());
                if (round.isFinalRound()) {
                    finals++;
                }
                if (round.isPlayable()) {
                    boards++;
                }

                int topicIdx = 0;
                for (JsonNode topicNode : topicsNode) {
                    Topic topic = new Topic();
                    topic.setId(++tid);
                    topic.setRound(round);
                    topic.setIdx(++topicIdx);
                    topic.setName(topicNode.path("name").asString());

                    for (JsonNode clueNode : topicNode.path("clues")) {
                        Clue clue = new Clue();
                        clue.setId(++cid);
                        clue.setTopic(topic);
                        JsonNode value = clueNode.path("value");
                        clue.setValue(value.isNumber() ? value.asInt() : null);
                        clue.setQuestion(clueNode.path("question").asString());
                        clue.setAnswer(clueNode.path("answer").asString());
                        clue.setQuestionOriginal(text(clueNode, "question_original"));
                        clue.setAnswerOriginal(text(clueNode, "answer_original"));
                        clue.setCorrectionNote(text(clueNode, "correction_note"));
                        if (clue.getCorrectionNote() != null) {
                            corrected++;
                        }
                        topic.getClues().add(clue);
                    }
                    round.getTopics().add(topic);
                }
                pkg.getRounds().add(round);
            }

            // A package already in the database is not saved again -- but its
            // clues are still worth comparing, so a corrected question reaches
            // a deployment without emptying the content tables. Building the
            // graph is also what advanced rid/tid/cid past its rows; deriving
            // those spans some other way would be a second description of this
            // loop's shape, free to drift from it.
            if (present.contains(pkg.getId())) {
                skipped++;
                pkg.getRounds().forEach(r -> r.getTopics()
                        .forEach(t -> t.getClues().forEach(c -> fromFile.put(c.getId(), c))));
                continue;
            }
            packages.save(pkg);
            added++;
        }

        long corrections = applyCorrections(fromFile);

        if (added == 0 && corrections == 0) {
            log.info("content already seeded ({} packages, {} clues) -- nothing to add or correct",
                    skipped, clues.count());
            return;
        }
        if (added > 0) {
            log.info("seeded {} package(s) ({} already present), {} rounds "
                            + "({} playable boards, {} finals), {} topics, {} clues ({} carrying a "
                            + "2008 correction note) in the file",
                    added, skipped, rid, boards, finals, tid, cid, corrected);
        }
        if (corrections > 0) {
            // Structure is never rewritten, so this cannot renumber a board or
            // move a tile: an existing package gains no clues and loses none.
            log.info("reworded {} clue(s) in packages that were already seeded", corrections);
        }
    }

    /**
     * Brings clues that are already in the database up to date with the file.
     *
     * <p>Only the wording moves. A clue keeps its id, its value and its place on
     * the board, which is what lets this run against a live database: a game
     * holding clue 3,900 still holds clue 3,900 afterwards, and the next time it
     * is read aloud it is read in the corrected words.
     *
     * <p>The value is the tripwire. Ids are positional, so if the file were ever
     * reordered, id 3,900 would name a different clue and this would happily
     * overwrite one clue with another's text. A value that disagrees is the
     * cheapest evidence that has happened, so nothing is written at all and the
     * mismatch is reported instead -- reordering the file is a mistake to fix,
     * not to absorb.
     *
     * @return how many clues were reworded
     */
    private long applyCorrections(Map<Long, Clue> fromFile) {
        if (fromFile.isEmpty()) return 0;

        List<Clue> stale = new ArrayList<>();
        for (ClueRepository.ClueText row : clues.findAllText()) {
            Clue parsed = fromFile.get(row.getId());
            if (parsed == null) continue;
            if (!Objects.equals(parsed.getValue(), row.getValue())) {
                log.error("clue {} is worth {} in the database but {} in {} -- ids no longer line up "
                                + "with the file, so no clue text was updated. Reseed instead.",
                        row.getId(), row.getValue(), parsed.getValue(), seedLocation);
                return 0;
            }
            if (!parsed.getQuestion().equals(row.getQuestion())
                    || !parsed.getAnswer().equals(row.getAnswer())) {
                stale.add(parsed);
            }
        }
        if (stale.isEmpty()) return 0;

        // Loaded only now, and only for the handful that actually differ.
        for (Clue parsed : stale) {
            clues.findById(parsed.getId()).ifPresent(row -> {
                row.setQuestion(parsed.getQuestion());
                row.setAnswer(parsed.getAnswer());
                row.setQuestionOriginal(parsed.getQuestionOriginal());
                row.setAnswerOriginal(parsed.getAnswerOriginal());
                row.setCorrectionNote(parsed.getCorrectionNote());
            });
        }
        return stale.size();
    }

    private static String text(JsonNode node, String field) {
        JsonNode v = node.path(field);
        return v.isMissingNode() || v.isNull() ? null : v.asString();
    }
}
