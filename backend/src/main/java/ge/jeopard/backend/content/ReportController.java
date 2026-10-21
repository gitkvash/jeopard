package ge.jeopard.backend.content;

import ge.jeopard.backend.content.ReportDtos.DismissReportRequest;
import ge.jeopard.backend.content.ReportDtos.ReportView;
import ge.jeopard.backend.content.ReportDtos.ResolveReportRequest;
import ge.jeopard.backend.content.ReportDtos.SubmitReportRequest;
import ge.jeopard.backend.content.ReportDtos.SubmitReportResponse;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api")
public class ReportController {

    private final ClueReportService reportService;

    public ReportController(ClueReportService reportService) {
        this.reportService = reportService;
    }

    /**
     * Submit a report for a specific clue.
     */
    @PostMapping("/clues/{clueId}/report")
    public ResponseEntity<SubmitReportResponse> submitReport(
            @PathVariable Long clueId,
            @RequestBody SubmitReportRequest request,
            HttpServletRequest httpRequest) {
        String clientIp = httpRequest.getRemoteAddr();
        SubmitReportResponse response = reportService.submitReport(
                clueId,
                request != null ? request.description() : null,
                clientIp
        );
        return ResponseEntity.ok(response);
    }

    /**
     * List clue reports. Optional filter by status (PENDING, RESOLVED, DISMISSED, or ALL).
     */
    @GetMapping("/reports")
    public List<ReportView> listReports(
            @RequestParam(required = false) String status) {
        ClueReport.Status filter = null;
        if (status != null && !status.isBlank() && !"ALL".equalsIgnoreCase(status)) {
            try {
                filter = ClueReport.Status.valueOf(status.toUpperCase());
            } catch (IllegalArgumentException ignored) {
            }
        }
        return reportService.listReports(filter);
    }

    /**
     * Get details of a single report.
     */
    @GetMapping("/reports/{id}")
    public ReportView getReport(@PathVariable Long id) {
        return reportService.getReport(id);
    }

    /**
     * Resolve a report and optionally update the clue text or answer.
     */
    @PostMapping("/reports/{id}/resolve")
    public ReportView resolveReport(
            @PathVariable Long id,
            @RequestBody(required = false) ResolveReportRequest request) {
        return reportService.resolveReport(id, request);
    }

    /**
     * Dismiss a report without modifying the clue.
     */
    @PostMapping("/reports/{id}/dismiss")
    public ReportView dismissReport(
            @PathVariable Long id,
            @RequestBody(required = false) DismissReportRequest request) {
        return reportService.dismissReport(id, request);
    }
}
