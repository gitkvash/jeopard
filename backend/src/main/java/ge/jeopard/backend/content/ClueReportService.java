package ge.jeopard.backend.content;

import ge.jeopard.backend.content.ReportDtos.DismissReportRequest;
import ge.jeopard.backend.content.ReportDtos.ReportView;
import ge.jeopard.backend.content.ReportDtos.ResolveReportRequest;
import ge.jeopard.backend.content.ReportDtos.SubmitReportResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Duration;
import java.time.Instant;
import java.util.Deque;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedDeque;

@Service
public class ClueReportService {

    private static final Logger log = LoggerFactory.getLogger(ClueReportService.class);
    private static final Duration WINDOW = Duration.ofHours(1);
    private static final int MAX_TRACKED_CLIENTS = 10_000;

    private final ClueReportRepository reports;
    private final ClueRepository clues;
    private final ContentService contentService;

    private final int hourlyLimit;
    private final int cooldownSeconds;

    private final Map<String, Deque<Instant>> clientHistory = new ConcurrentHashMap<>();
    private final Map<String, Instant> lastSubmission = new ConcurrentHashMap<>();

    public ClueReportService(
            ClueReportRepository reports,
            ClueRepository clues,
            ContentService contentService,
            @Value("${jeopard.limits.reports-per-hour-per-ip:10}") int hourlyLimit,
            @Value("${jeopard.limits.report-cooldown-seconds:10}") int cooldownSeconds) {
        this.reports = reports;
        this.clues = clues;
        this.contentService = contentService;
        this.hourlyLimit = hourlyLimit;
        this.cooldownSeconds = cooldownSeconds;
    }

    /**
     * Submits a new report for a clue with abuse protection.
     */
    @Transactional
    public SubmitReportResponse submitReport(Long clueId, String rawDescription, String clientIp) {
        if (rawDescription == null || rawDescription.trim().length() < 5) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "აღწერა უნდა შეიცავდეს მინიმუმ 5 სიმბოლოს.");
        }
        String description = rawDescription.trim();
        if (description.length() > 1000) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "აღწერა არ უნდა აღემატებოდეს 1000 სიმბოლოს.");
        }

        Clue clue = clues.findById(clueId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "შეკითხვა ვერ მოიძებნა"));

        // Anti-spam rate limiting & cooldown
        checkRateLimits(clientIp);

        // Duplicate suppression: if the same client already reported this clue and it's still pending
        if (reports.existsByClueIdAndReporterIpAndStatus(clueId, clientIp, ClueReport.Status.PENDING)) {
            log.info("suppressed duplicate pending report for clue {} from {}", clueId, clientIp);
            return new SubmitReportResponse("duplicate", "ამ შეკითხვაზე თქვენი რეპორტი უკვე მიღებულია.");
        }

        recordSubmission(clientIp);

        ClueReport report = new ClueReport(clue, description, clientIp);
        reports.save(report);
        log.info("saved clue report #{} for clue {} from {}", report.getId(), clueId, clientIp);

        return new SubmitReportResponse("ok", "მადლობა, შეცდომა დაფიქსირებულია!");
    }

    @Transactional(readOnly = true)
    public List<ReportView> listReports(ClueReport.Status status) {
        return reports.findReportsWithDetails(status).stream()
                .map(ReportView::fromEntity)
                .toList();
    }

    @Transactional(readOnly = true)
    public ReportView getReport(Long id) {
        ClueReport report = reports.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "რეპორტი ვერ მოიძებნა"));
        return ReportView.fromEntity(report);
    }

    /**
     * Resolves a report, optionally updating the clue's text or answer.
     */
    @Transactional
    public ReportView resolveReport(Long reportId, ResolveReportRequest req) {
        ClueReport report = reports.findById(reportId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "რეპორტი ვერ მოიძებნა"));

        Clue clue = report.getClue();
        boolean clueChanged = false;

        if (req != null) {
            if (req.updatedQuestion() != null && !req.updatedQuestion().isBlank()) {
                String newQuestion = req.updatedQuestion().trim();
                if (!newQuestion.equals(clue.getQuestion())) {
                    if (clue.getQuestionOriginal() == null) {
                        clue.setQuestionOriginal(clue.getQuestion());
                    }
                    clue.setQuestion(newQuestion);
                    clueChanged = true;
                }
            }

            if (req.updatedAnswer() != null && !req.updatedAnswer().isBlank()) {
                String newAnswer = req.updatedAnswer().trim();
                if (!newAnswer.equals(clue.getAnswer())) {
                    if (clue.getAnswerOriginal() == null) {
                        clue.setAnswerOriginal(clue.getAnswer());
                    }
                    clue.setAnswer(newAnswer);
                    clueChanged = true;
                }
            }

            if (req.resolutionNote() != null && !req.resolutionNote().isBlank()) {
                String note = req.resolutionNote().trim();
                report.setResolutionNote(note);
                String existing = clue.getCorrectionNote();
                if (existing == null || existing.isBlank()) {
                    clue.setCorrectionNote(note);
                } else if (!existing.contains(note)) {
                    clue.setCorrectionNote(existing + "; " + note);
                }
                clueChanged = true;
            }
        }

        if (clueChanged) {
            clues.save(clue);
            if (clue.getTopic() != null && clue.getTopic().getRound() != null) {
                contentService.invalidateBoard(clue.getTopic().getRound().getId());
            }
        }

        report.setStatus(ClueReport.Status.RESOLVED);
        report.setResolvedAt(Instant.now());
        reports.save(report);

        return ReportView.fromEntity(report);
    }

    /**
     * Dismisses a report without altering the clue.
     */
    @Transactional
    public ReportView dismissReport(Long reportId, DismissReportRequest req) {
        ClueReport report = reports.findById(reportId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "რეპორტი ვერ მოიძებნა"));

        if (req != null && req.note() != null && !req.note().isBlank()) {
            report.setResolutionNote(req.note().trim());
        }

        report.setStatus(ClueReport.Status.DISMISSED);
        report.setResolvedAt(Instant.now());
        reports.save(report);

        return ReportView.fromEntity(report);
    }

    private void checkRateLimits(String clientIp) {
        if (hourlyLimit <= 0) {
            return;
        }

        Instant now = Instant.now();

        // 1. Cooldown check
        Instant last = lastSubmission.get(clientIp);
        if (last != null && cooldownSeconds > 0) {
            long elapsed = Duration.between(last, now).toSeconds();
            if (elapsed < cooldownSeconds) {
                log.warn("report cooldown triggered for {}: only {}s elapsed (required {}s)",
                        clientIp, elapsed, cooldownSeconds);
                throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                        "გთხოვთ დაიცადოთ რამდენიმე წამი შემდეგი რეპორტის გაგზავნამდე.");
            }
        }

        // 2. Sliding window check
        if (clientHistory.size() > MAX_TRACKED_CLIENTS) {
            clientHistory.clear();
            lastSubmission.clear();
        }

        Deque<Instant> times = clientHistory.computeIfAbsent(clientIp, k -> new ConcurrentLinkedDeque<>());
        Instant cutoff = now.minus(WINDOW);
        synchronized (times) {
            while (!times.isEmpty() && times.peekFirst().isBefore(cutoff)) {
                times.pollFirst();
            }
            if (times.size() >= hourlyLimit) {
                log.warn("report rate limit exceeded for {}: {} reports in last hour", clientIp, times.size());
                throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                        "ძალიან ბევრი რეპორტი გაიგზავნა. გთხოვთ სცადოთ მოგვიანებით.");
            }
        }
    }

    private void recordSubmission(String clientIp) {
        Instant now = Instant.now();
        lastSubmission.put(clientIp, now);
        Deque<Instant> times = clientHistory.computeIfAbsent(clientIp, k -> new ConcurrentLinkedDeque<>());
        synchronized (times) {
            times.addLast(now);
        }
    }

    /** Clears tracking maps for tests. */
    public void resetLimits() {
        clientHistory.clear();
        lastSubmission.clear();
    }
}
