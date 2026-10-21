package ge.jeopard.backend.content;

import java.time.Instant;

public class ReportDtos {

    public record SubmitReportRequest(String description) {
    }

    public record SubmitReportResponse(String status, String message) {
    }

    public record ReportView(
            Long id,
            Long clueId,
            String topicName,
            String roundHeader,
            String packageTitle,
            Integer packageNumber,
            String question,
            String answer,
            Integer value,
            String description,
            String status,
            String reporterIp,
            Instant reportedAt,
            String resolutionNote,
            Instant resolvedAt) {

        public static ReportView fromEntity(ClueReport report) {
            Clue clue = report.getClue();
            Topic topic = clue.getTopic();
            GameRound round = topic != null ? topic.getRound() : null;
            QuizPackage pkg = round != null ? round.getQuizPackage() : null;

            return new ReportView(
                    report.getId(),
                    clue.getId(),
                    topic != null ? topic.getName() : null,
                    round != null ? round.getHeader() : null,
                    pkg != null ? pkg.getTitle() : null,
                    pkg != null ? pkg.getNumber() : null,
                    clue.getQuestion(),
                    clue.getAnswer(),
                    clue.getValue(),
                    report.getDescription(),
                    report.getStatus().name(),
                    report.getReporterIp(),
                    report.getReportedAt(),
                    report.getResolutionNote(),
                    report.getResolvedAt()
            );
        }
    }

    public record ResolveReportRequest(
            String updatedQuestion,
            String updatedAnswer,
            String resolutionNote) {
    }

    public record DismissReportRequest(String note) {
    }
}
