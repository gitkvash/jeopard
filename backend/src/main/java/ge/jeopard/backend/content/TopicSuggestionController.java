package ge.jeopard.backend.content;

import ge.jeopard.backend.content.TopicSuggestionDtos.ReviewTopicSuggestionRequest;
import ge.jeopard.backend.content.TopicSuggestionDtos.SubmitTopicSuggestionRequest;
import ge.jeopard.backend.content.TopicSuggestionDtos.SubmitTopicSuggestionResponse;
import ge.jeopard.backend.content.TopicSuggestionDtos.TopicSuggestionView;
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
@RequestMapping("/api/topics")
public class TopicSuggestionController {

    private final TopicSuggestionService suggestionService;

    public TopicSuggestionController(TopicSuggestionService suggestionService) {
        this.suggestionService = suggestionService;
    }

    @PostMapping("/suggest")
    public ResponseEntity<SubmitTopicSuggestionResponse> submitSuggestion(
            @RequestBody SubmitTopicSuggestionRequest request,
            HttpServletRequest httpRequest) {
        String clientIp = httpRequest.getRemoteAddr();
        SubmitTopicSuggestionResponse response = suggestionService.submitSuggestion(request, clientIp);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/suggestions")
    public List<TopicSuggestionView> listSuggestions(
            @RequestParam(required = false) String status) {
        TopicSuggestion.Status filter = null;
        if (status != null && !status.isBlank() && !"ALL".equalsIgnoreCase(status)) {
            try {
                filter = TopicSuggestion.Status.valueOf(status.toUpperCase());
            } catch (IllegalArgumentException ignored) {
            }
        }
        return suggestionService.listSuggestions(filter);
    }

    @GetMapping("/suggestions/{id}")
    public TopicSuggestionView getSuggestion(@PathVariable Long id) {
        return suggestionService.getSuggestion(id);
    }

    @PostMapping("/suggestions/{id}/approve")
    public TopicSuggestionView approveSuggestion(
            @PathVariable Long id,
            @RequestBody(required = false) ReviewTopicSuggestionRequest request) {
        return suggestionService.approveSuggestion(id, request);
    }

    @PostMapping("/suggestions/{id}/reject")
    public TopicSuggestionView rejectSuggestion(
            @PathVariable Long id,
            @RequestBody(required = false) ReviewTopicSuggestionRequest request) {
        return suggestionService.rejectSuggestion(id, request);
    }
}
