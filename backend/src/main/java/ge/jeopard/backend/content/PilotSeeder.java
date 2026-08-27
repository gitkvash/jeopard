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

/**
 * Loads data/pilot.json (copied to the classpath) into Postgres on first start.
 *
 * <p>The JSON is produced by {@code src/build_pilot_db.py}; this walks the same
 * package -&gt; round -&gt; topic -&gt; clue nesting and assigns ids in the same
 * order, so row ids line up with data/pilot.db. Idempotent: if any clue already
 * exists, seeding is skipped.
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
        long existing = clues.count();
        if (existing > 0) {
            log.info("content already seeded ({} clues) -- skipping", existing);
            return;
        }

        Resource resource = resourceLoader.getResource(seedLocation);
        if (!resource.exists()) {
            log.error("seed resource {} not found -- no content loaded", seedLocation);
            return;
        }

        JsonNode root;
        try (InputStream in = resource.getInputStream()) {
            root = objectMapper.readTree(in);
        }

        long pid = 0;
        long rid = 0;
        long tid = 0;
        long cid = 0;
        long corrected = 0;
        long boards = 0;
        long finals = 0;

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
            packages.save(pkg);
        }

        log.info("seeded {} packages, {} rounds ({} playable boards, {} finals), {} topics, {} clues ({} corrected)",
                pid, rid, boards, finals, tid, cid, corrected);
    }

    private static String text(JsonNode node, String field) {
        JsonNode v = node.path(field);
        return v.isMissingNode() || v.isNull() ? null : v.asString();
    }
}
