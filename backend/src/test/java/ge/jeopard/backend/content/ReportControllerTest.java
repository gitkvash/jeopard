package ge.jeopard.backend.content;

import ge.jeopard.backend.content.ReportDtos.ReportView;
import ge.jeopard.backend.content.ReportDtos.SubmitReportRequest;
import ge.jeopard.backend.content.ReportDtos.SubmitReportResponse;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ReportControllerTest {

    @Mock
    private ClueReportService reportService;

    @Mock
    private HttpServletRequest httpRequest;

    @InjectMocks
    private ReportController controller;

    @Test
    @DisplayName("submitReport delegates client IP and returns response")
    void submitsReport() {
        when(httpRequest.getRemoteAddr()).thenReturn("192.168.1.50");
        when(reportService.submitReport(123L, "აღწერა შეცდომის", "192.168.1.50"))
                .thenReturn(new SubmitReportResponse("ok", "მიღებულია"));

        ResponseEntity<SubmitReportResponse> response = controller.submitReport(
                123L,
                new SubmitReportRequest("აღწერა შეცდომის"),
                httpRequest
        );

        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().status()).isEqualTo("ok");
        assertThat(response.getBody().message()).isEqualTo("მიღებულია");
    }

    @Test
    @DisplayName("listReports parses status filter")
    void listsReports() {
        when(reportService.listReports(ClueReport.Status.PENDING))
                .thenReturn(List.of(new ReportView(
                        1L, 10L, "თემა", "ტური 1", "პაკეტი 1", 1,
                        "კითხვა", "პასუხი", 10, "აღწერა", "PENDING",
                        "127.0.0.1", Instant.now(), null, null
                )));

        List<ReportView> list = controller.listReports("PENDING");
        assertThat(list).hasSize(1);
        assertThat(list.get(0).status()).isEqualTo("PENDING");

        controller.listReports("ALL");
        verify(reportService).listReports(null);
    }
}
