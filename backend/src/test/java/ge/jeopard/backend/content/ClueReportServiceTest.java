package ge.jeopard.backend.content;

import ge.jeopard.backend.content.ReportDtos.DismissReportRequest;
import ge.jeopard.backend.content.ReportDtos.ReportView;
import ge.jeopard.backend.content.ReportDtos.ResolveReportRequest;
import ge.jeopard.backend.content.ReportDtos.SubmitReportResponse;
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
class ClueReportServiceTest {

    @Mock
    private ClueReportRepository reports;

    @Mock
    private ClueRepository clues;

    @Mock
    private ContentService contentService;

    private ClueReportService service;

    private Clue sampleClue;

    @BeforeEach
    void setup() {
        // limit 3 per hour, 5s cooldown
        service = new ClueReportService(reports, clues, contentService, 3, 5);

        sampleClue = new Clue();
        sampleClue.setId(100L);
        sampleClue.setQuestion("ძველი შეკითხვა?");
        sampleClue.setAnswer("ძველი პასუხი");

        Topic topic = new Topic();
        topic.setId(10L);
        topic.setName("გეოგრაფია");
        GameRound round = new GameRound();
        round.setId(1L);
        topic.setRound(round);
        sampleClue.setTopic(topic);
    }

    @Test
    @DisplayName("valid report is saved and returns ok")
    void submitsValidReport() {
        when(clues.findById(100L)).thenReturn(Optional.of(sampleClue));
        when(reports.existsByClueIdAndReporterIpAndStatus(100L, "127.0.0.1", ClueReport.Status.PENDING))
                .thenReturn(false);

        SubmitReportResponse res = service.submitReport(100L, "კითხვაში შეცდომაა, თარიღი არასწორია", "127.0.0.1");

        assertThat(res.status()).isEqualTo("ok");
        assertThat(res.message()).contains("შეცდომა დაფიქსირებულია");
        verify(reports, times(1)).save(any(ClueReport.class));
    }

    @Test
    @DisplayName("description under 5 characters is rejected with 400")
    void rejectsShortDescription() {
        assertThatThrownBy(() -> service.submitReport(100L, "ვაი", "127.0.0.1"))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("მინიმუმ 5 სიმბოლოს");
        verify(reports, never()).save(any());
    }

    @Test
    @DisplayName("duplicate pending report from same IP returns duplicate status and saves nothing")
    void suppressesDuplicatePendingReport() {
        when(clues.findById(100L)).thenReturn(Optional.of(sampleClue));
        when(reports.existsByClueIdAndReporterIpAndStatus(100L, "127.0.0.1", ClueReport.Status.PENDING))
                .thenReturn(true);

        SubmitReportResponse res = service.submitReport(100L, "კითხვაში შეცდომაა, თარიღი არასწორია", "127.0.0.1");

        assertThat(res.status()).isEqualTo("duplicate");
        verify(reports, never()).save(any());
    }

    @Test
    @DisplayName("rapid consecutive reports trigger cooldown 429")
    void enforcesCooldown() {
        when(clues.findById(100L)).thenReturn(Optional.of(sampleClue));
        when(reports.existsByClueIdAndReporterIpAndStatus(100L, "127.0.0.1", ClueReport.Status.PENDING))
                .thenReturn(false);

        // First report passes
        service.submitReport(100L, "პირველი რეპორტი კითხვაზე", "127.0.0.1");

        // Immediate second report fails cooldown
        assertThatThrownBy(() -> service.submitReport(100L, "მეორე რეპორტი მაშინვე", "127.0.0.1"))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("დაიცადოთ რამდენიმე წამი");
    }

    @Test
    @DisplayName("exceeding hourly rate limit triggers 429")
    void enforcesHourlyLimit() {
        // Service with limit of 2, 0 cooldown
        ClueReportService limitedService = new ClueReportService(reports, clues, contentService, 2, 0);
        when(clues.findById(100L)).thenReturn(Optional.of(sampleClue));
        when(reports.existsByClueIdAndReporterIpAndStatus(eq(100L), eq("127.0.0.1"), any()))
                .thenReturn(false);

        limitedService.submitReport(100L, "პირველი რეპორტი", "127.0.0.1");
        limitedService.submitReport(100L, "მეორე რეპორტი", "127.0.0.1");

        assertThatThrownBy(() -> limitedService.submitReport(100L, "მესამე რეპორტი უკვე ბევრია", "127.0.0.1"))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("ძალიან ბევრი რეპორტი გაიგზავნა");
    }

    @Test
    @DisplayName("resolving a report updates clue and invalidates board cache")
    void resolvesReportAndUpdatesClue() {
        ClueReport report = new ClueReport(sampleClue, "პასუხი არასწორია", "1.2.3.4");
        report.setId(1L);

        when(reports.findById(1L)).thenReturn(Optional.of(report));

        ResolveReportRequest req = new ResolveReportRequest(
                "შესწორებული შეკითხვა?",
                "შესწორებული პასუხი",
                "მომხმარებლის რეპორტის საფუძველზე გასწორდა"
        );

        ReportView view = service.resolveReport(1L, req);

        assertThat(view.status()).isEqualTo("RESOLVED");
        assertThat(sampleClue.getQuestion()).isEqualTo("შესწორებული შეკითხვა?");
        assertThat(sampleClue.getAnswer()).isEqualTo("შესწორებული პასუხი");
        assertThat(sampleClue.getQuestionOriginal()).isEqualTo("ძველი შეკითხვა?");
        assertThat(sampleClue.getAnswerOriginal()).isEqualTo("ძველი პასუხი");
        assertThat(sampleClue.getCorrectionNote()).contains("მომხმარებლის რეპორტის საფუძველზე");

        verify(clues).save(sampleClue);
        verify(contentService).invalidateBoard(1L);
        verify(reports).save(report);
    }

    @Test
    @DisplayName("dismissing a report marks it dismissed without touching clue")
    void dismissesReport() {
        ClueReport report = new ClueReport(sampleClue, "არ მომწონს ეს კითხვა", "1.2.3.4");
        report.setId(2L);

        when(reports.findById(2L)).thenReturn(Optional.of(report));

        DismissReportRequest req = new DismissReportRequest("კითხვაში შეცდომა არ არის");
        ReportView view = service.dismissReport(2L, req);

        assertThat(view.status()).isEqualTo("DISMISSED");
        assertThat(view.resolutionNote()).isEqualTo("კითხვაში შეცდომა არ არის");
        verify(clues, never()).save(any());
        verify(contentService, never()).invalidateBoard(any());
        verify(reports).save(report);
    }
}
