package ge.jeopard.backend.content;

import ge.jeopard.backend.content.TopicSuggestionDtos.ReviewTopicSuggestionRequest;
import ge.jeopard.backend.content.TopicSuggestionDtos.SubmitTopicSuggestionRequest;
import ge.jeopard.backend.content.TopicSuggestionDtos.SubmitTopicSuggestionResponse;
import ge.jeopard.backend.content.TopicSuggestionDtos.TopicSuggestionView;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.server.ResponseStatusException;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class TopicSuggestionServiceTest {

    @Mock
    private TopicSuggestionRepository repository;

    private TopicSuggestionService service;

    @BeforeEach
    void setup() {
        // limit 3 per hour, 5s cooldown
        service = new TopicSuggestionService(repository, 3, 5);
    }

    @Test
    @DisplayName("valid topic suggestion is saved and returns ok")
    void submitsValidSuggestion() {
        when(repository.existsByTopicNameIgnoreCaseAndStatus("ქართული როკი", TopicSuggestion.Status.PENDING))
                .thenReturn(false);

        SubmitTopicSuggestionRequest req = new SubmitTopicSuggestionRequest(
                "ქართული როკი",
                "კითხვები როკ-ჯგუფებზე, როგორიცაა 33ა, რობი კუხიანიძე...",
                "გიორგი"
        );

        SubmitTopicSuggestionResponse res = service.submitSuggestion(req, "127.0.0.1");

        assertThat(res.status()).isEqualTo("ok");
        assertThat(res.message()).contains("თემის შემოთავაზება მიღებულია");
        verify(repository, times(1)).save(any(TopicSuggestion.class));
    }

    @Test
    @DisplayName("short topic name under 2 chars is rejected with 400")
    void rejectsShortTopicName() {
        SubmitTopicSuggestionRequest req = new SubmitTopicSuggestionRequest("ა", null, null);

        assertThatThrownBy(() -> service.submitSuggestion(req, "127.0.0.1"))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("მინიმუმ 2 სიმბოლოს");

        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("duplicate pending suggestion returns duplicate status without saving")
    void suppressesDuplicatePendingSuggestion() {
        when(repository.existsByTopicNameIgnoreCaseAndStatus("ასტრონომია", TopicSuggestion.Status.PENDING))
                .thenReturn(true);

        SubmitTopicSuggestionRequest req = new SubmitTopicSuggestionRequest("ასტრონომია", "პლანეტები", null);
        SubmitTopicSuggestionResponse res = service.submitSuggestion(req, "127.0.0.1");

        assertThat(res.status()).isEqualTo("duplicate");
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("cooldown is enforced on rapid submissions")
    void enforcesCooldown() {
        when(repository.existsByTopicNameIgnoreCaseAndStatus(anyString(), eq(TopicSuggestion.Status.PENDING)))
                .thenReturn(false);

        SubmitTopicSuggestionRequest req1 = new SubmitTopicSuggestionRequest("თემა 1", null, null);
        SubmitTopicSuggestionRequest req2 = new SubmitTopicSuggestionRequest("თემა 2", null, null);

        service.submitSuggestion(req1, "127.0.0.1");

        assertThatThrownBy(() -> service.submitSuggestion(req2, "127.0.0.1"))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("დაიცადოთ რამდენიმე წამი");
    }

    @Test
    @DisplayName("hourly rate limit is enforced")
    void enforcesHourlyLimit() {
        TopicSuggestionService limitedService = new TopicSuggestionService(repository, 2, 0);
        when(repository.existsByTopicNameIgnoreCaseAndStatus(anyString(), eq(TopicSuggestion.Status.PENDING)))
                .thenReturn(false);

        limitedService.submitSuggestion(new SubmitTopicSuggestionRequest("თემა 1", null, null), "127.0.0.1");
        limitedService.submitSuggestion(new SubmitTopicSuggestionRequest("თემა 2", null, null), "127.0.0.1");

        assertThatThrownBy(() -> limitedService.submitSuggestion(new SubmitTopicSuggestionRequest("თემა 3", null, null), "127.0.0.1"))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("ძალიან ბევრი შემოთავაზება გაიგზავნა");
    }

    @Test
    @DisplayName("approving a suggestion updates status and notes")
    void approvesSuggestion() {
        TopicSuggestion entity = new TopicSuggestion("კოსმოსი", "ვარსკვლავები", "ნიკა", "127.0.0.1");
        entity.setId(10L);

        when(repository.findById(10L)).thenReturn(Optional.of(entity));

        TopicSuggestionView view = service.approveSuggestion(10L, new ReviewTopicSuggestionRequest("დაემატება პაკეტ #32-ში"));

        assertThat(view.status()).isEqualTo("APPROVED");
        assertThat(entity.getReviewNote()).isEqualTo("დაემატება პაკეტ #32-ში");
        assertThat(entity.getReviewedAt()).isNotNull();
        verify(repository).save(entity);
    }
}
