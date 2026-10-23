package ge.jeopard.backend.content;

import ge.jeopard.backend.content.ContentDtos.AvailableTopic;
import ge.jeopard.backend.content.ContentDtos.BuildPackageRequest;
import ge.jeopard.backend.content.ContentDtos.PackageSummary;
import ge.jeopard.backend.content.ContentDtos.TopicSummary;
import ge.jeopard.backend.content.TopicRepository.AvailableTopicRef;
import ge.jeopard.backend.content.TopicRepository.TopicRef;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class BuildPackageUnitTest {

    @Mock
    private PackageRepository packages;

    @Mock
    private RoundRepository rounds;

    @Mock
    private TopicRepository topics;

    @Mock
    private ClueRepository clues;

    private ContentService contentService;

    @BeforeEach
    void setUp() {
        contentService = new ContentService(packages, rounds, topics, clues, 256);
    }

    @Test
    @DisplayName("availableTopics filters by round and query correctly")
    void testAvailableTopicsFiltering() {
        AvailableTopicRef ref1 = mockTopicRef(101L, "საქართველოს ისტორია", 1, false, "პაკეტი 1");
        AvailableTopicRef ref2 = mockTopicRef(102L, "მსოფლიო გეოგრაფია", 1, false, "პაკეტი 1");
        AvailableTopicRef ref3 = mockTopicRef(201L, "ქართული ლიტერატურა", 2, false, "პაკეტი 2");
        AvailableTopicRef ref4 = mockTopicRef(401L, "ფინალური თემა", 4, true, "პაკეტი 3");

        when(topics.findAvailableTopicRefs()).thenReturn(List.of(ref1, ref2, ref3, ref4));

        // Filter by round 1 (any playable, non-final topic is available for rounds 1-3)
        List<AvailableTopic> round1Topics = contentService.availableTopics(1, null);
        assertThat(round1Topics).hasSize(3);
        assertThat(round1Topics.stream().map(AvailableTopic::name))
                .containsExactlyInAnyOrder("საქართველოს ისტორია", "მსოფლიო გეოგრაფია", "ქართული ლიტერატურა");

        // Filter by query "გეოგრაფია"
        List<AvailableTopic> queryTopics = contentService.availableTopics(null, "გეოგრაფია");
        assertThat(queryTopics).hasSize(1);
        assertThat(queryTopics.get(0).id()).isEqualTo(102L);

        // Filter by final round (round 4)
        List<AvailableTopic> finalTopics = contentService.availableTopics(4, null);
        assertThat(finalTopics).hasSize(1);
        assertThat(finalTopics.get(0).name()).isEqualTo("ფინალური თემა");
    }

    @Test
    @DisplayName("buildCustomPackage builds package with selected and auto-filled topics")
    void testBuildCustomPackage() {
        when(packages.nextSyntheticId()).thenReturn(1_000_005L);
        when(rounds.nextSyntheticIds(anyInt())).thenReturn(List.of(2001L, 2002L, 2003L, 2004L));
        when(topics.nextSyntheticIds(anyInt())).thenAnswer(inv -> {
            int count = inv.getArgument(0);
            List<Long> ids = new ArrayList<>();
            for (long i = 1; i <= count; i++) ids.add(3000L + i);
            return ids;
        });
        when(clues.nextSyntheticIds(anyInt())).thenAnswer(inv -> {
            int count = inv.getArgument(0);
            List<Long> ids = new ArrayList<>();
            for (long i = 1; i <= count; i++) ids.add(4000L + i);
            return ids;
        });

        // Mock playable pools for auto-fill
        List<TopicRef> r1Pool = new ArrayList<>();
        for (int i = 1; i <= 10; i++) r1Pool.add(mockPoolRef((long) i, "თემა 1-" + i, 1));
        List<TopicRef> r2Pool = new ArrayList<>();
        for (int i = 1; i <= 10; i++) r2Pool.add(mockPoolRef((long) (10 + i), "თემა 2-" + i, 2));
        List<TopicRef> r3Pool = new ArrayList<>();
        for (int i = 1; i <= 10; i++) r3Pool.add(mockPoolRef((long) (20 + i), "თემა 3-" + i, 3));
        List<TopicRef> fPool = new ArrayList<>();
        for (int i = 1; i <= 5; i++) fPool.add(mockPoolRef((long) (30 + i), "ფინალი-" + i, 4));

        List<TopicRef> allPlayable = new ArrayList<>();
        allPlayable.addAll(r1Pool);
        allPlayable.addAll(r2Pool);
        allPlayable.addAll(r3Pool);

        when(topics.findPlayableTopicRefs(3)).thenReturn(allPlayable);
        when(topics.findFinalTopicRefs()).thenReturn(fPool);

        Topic chosenTopic = new Topic();
        chosenTopic.setId(1L);
        chosenTopic.setName("შერჩეული ისტორია");
        for (int v = 10; v <= 50; v += 10) {
            Clue c = new Clue();
            c.setId((long) v);
            c.setValue(v);
            c.setQuestion("კითხვა " + v);
            c.setAnswer("პასუხი " + v);
            chosenTopic.getClues().add(c);
        }

        when(topics.findAllById(anyList())).thenReturn(List.of(chosenTopic));
        when(topics.findAllWithCluesByIdIn(anyList())).thenAnswer(inv -> {
            List<Long> ids = inv.getArgument(0);
            List<Topic> result = new ArrayList<>();
            for (Long id : ids) {
                Topic t = new Topic();
                t.setId(id);
                t.setName("თემა " + id);
                for (int v = 10; v <= 50; v += 10) {
                    Clue c = new Clue();
                    c.setId(id * 100 + v);
                    c.setValue(v);
                    c.setQuestion("კითხვა " + v);
                    c.setAnswer("პასუხი " + v);
                    t.getClues().add(c);
                }
                result.add(t);
            }
            return result;
        });

        BuildPackageRequest request = new BuildPackageRequest(
                "ჩემი სატესტო პაკეტი",
                List.of(1L), // Only 1 topic for round 1 provided, remaining 5 to be filled
                List.of(),   // 0 provided for round 2, all 6 auto-filled
                List.of(),   // 0 provided for round 3, all 6 auto-filled
                List.of()    // 0 provided for final, 2 auto-filled
        );

        PackageSummary summary = contentService.buildCustomPackage(request);

        assertThat(summary).isNotNull();
        assertThat(summary.synthetic()).isTrue();
        assertThat(summary.title()).isEqualTo("ჩემი სატესტო პაკეტი");
        assertThat(summary.rounds()).hasSize(4);

        // Check rounds
        assertThat(summary.rounds().get(0).topics()).hasSize(6);
        assertThat(summary.rounds().get(1).topics()).hasSize(6);
        assertThat(summary.rounds().get(2).topics()).hasSize(6);
        assertThat(summary.rounds().get(3).topics()).hasSize(5);

        verify(packages).save(any(QuizPackage.class));
    }

    @Test
    @DisplayName("replaceTopic updates topic name, clues and evicts board cache")
    void testReplaceTopic() {
        QuizPackage pkg = new QuizPackage();
        pkg.setId(1_000_001L);
        pkg.setSynthetic(true);

        GameRound round = new GameRound();
        round.setId(501L);
        round.setIdx(1);
        round.setQuizPackage(pkg);

        Topic targetTopic = new Topic();
        targetTopic.setId(601L);
        targetTopic.setName("ძველი თემა");
        targetTopic.setRound(round);

        Topic sourceTopic = new Topic();
        sourceTopic.setId(901L);
        sourceTopic.setName("ახალი თემა");
        for (int i = 1; i <= 5; i++) {
            Clue c = new Clue();
            c.setId((long) i);
            c.setValue(i * 10);
            c.setQuestion("ახალი კითხვა " + i);
            c.setAnswer("ახალი პასუხი " + i);
            sourceTopic.getClues().add(c);
        }

        when(topics.findById(601L)).thenReturn(Optional.of(targetTopic));
        when(topics.findAllWithCluesByIdIn(List.of(901L))).thenReturn(List.of(sourceTopic));
        when(clues.nextSyntheticIds(5)).thenReturn(List.of(7001L, 7002L, 7003L, 7004L, 7005L));

        TopicSummary updated = contentService.replaceTopic(1_000_001L, 601L, 901L);

        assertThat(updated.name()).isEqualTo("ახალი თემა");
        assertThat(targetTopic.getName()).isEqualTo("ახალი თემა");
        assertThat(targetTopic.getClues()).hasSize(5);
        assertThat(targetTopic.getClues().get(0).getValue()).isEqualTo(10);
        assertThat(targetTopic.getClues().get(4).getValue()).isEqualTo(50);

        verify(clues).deleteByTopicId(601L);
        verify(topics).saveAndFlush(targetTopic);
    }

    private AvailableTopicRef mockTopicRef(Long id, String name, Integer roundIdx, boolean finalRound, String packageTitle) {
        return new AvailableTopicRef() {
            @Override
            public Long getId() { return id; }

            @Override
            public String getName() { return name; }

            @Override
            public Integer getRoundIdx() { return roundIdx; }

            @Override
            public boolean isFinalRound() { return finalRound; }

            @Override
            public String getPackageTitle() { return packageTitle; }
        };
    }

    private TopicRef mockPoolRef(Long id, String name, Integer roundIdx) {
        return new TopicRef() {
            @Override
            public Integer getRoundIdx() { return roundIdx; }

            @Override
            public Long getId() { return id; }

            @Override
            public String getName() { return name; }
        };
    }
}
