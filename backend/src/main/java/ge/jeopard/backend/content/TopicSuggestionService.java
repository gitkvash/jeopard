package ge.jeopard.backend.content;

import ge.jeopard.backend.content.TopicSuggestionDtos.ReviewTopicSuggestionRequest;
import ge.jeopard.backend.content.TopicSuggestionDtos.SubmitTopicSuggestionRequest;
import ge.jeopard.backend.content.TopicSuggestionDtos.SubmitTopicSuggestionResponse;
import ge.jeopard.backend.content.TopicSuggestionDtos.TopicSuggestionView;
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
public class TopicSuggestionService {

    private static final Logger log = LoggerFactory.getLogger(TopicSuggestionService.class);
    private static final Duration WINDOW = Duration.ofHours(1);
    private static final int MAX_TRACKED_CLIENTS = 10_000;

    private final TopicSuggestionRepository suggestions;
    private final int hourlyLimit;
    private final int cooldownSeconds;

    private final Map<String, Deque<Instant>> clientHistory = new ConcurrentHashMap<>();
    private final Map<String, Instant> lastSubmission = new ConcurrentHashMap<>();

    public TopicSuggestionService(
            TopicSuggestionRepository suggestions,
            @Value("${jeopard.limits.topic-suggestions-per-hour-per-ip:10}") int hourlyLimit,
            @Value("${jeopard.limits.topic-suggestion-cooldown-seconds:10}") int cooldownSeconds) {
        this.suggestions = suggestions;
        this.hourlyLimit = hourlyLimit;
        this.cooldownSeconds = cooldownSeconds;
    }

    @Transactional
    public SubmitTopicSuggestionResponse submitSuggestion(SubmitTopicSuggestionRequest req, String clientIp) {
        if (req == null || req.topicName() == null || req.topicName().trim().length() < 2) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "თემის სახელწოდება უნდა შეიცავდეს მინიმუმ 2 სიმბოლოს.");
        }
        String topicName = req.topicName().trim();
        if (topicName.length() > 100) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "თემის სახელწოდება არ უნდა აღემატებოდეს 100 სიმბოლოს.");
        }

        String description = req.description() != null ? req.description().trim() : null;
        if (description != null && description.length() > 1000) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "აღწერა არ უნდა აღემატებოდეს 1000 სიმბოლოს.");
        }

        String authorName = req.authorName() != null ? req.authorName().trim() : null;
        if (authorName != null && authorName.length() > 128) {
            authorName = authorName.substring(0, 128);
        }

        checkRateLimits(clientIp);

        // Check if pending suggestion for the same topic already exists
        if (suggestions.existsByTopicNameIgnoreCaseAndStatus(topicName, TopicSuggestion.Status.PENDING)) {
            log.info("suppressed duplicate pending topic suggestion '{}' from {}", topicName, clientIp);
            return new SubmitTopicSuggestionResponse("duplicate", "ეს თემა უკვე შემოთავაზებულია და განხილვის პროცესშია.");
        }

        recordSubmission(clientIp);

        TopicSuggestion entity = new TopicSuggestion(topicName, description, authorName, clientIp);
        suggestions.save(entity);
        log.info("saved topic suggestion #{} ('{}') from {}", entity.getId(), topicName, clientIp);

        return new SubmitTopicSuggestionResponse("ok", "მადლობა! თემის შემოთავაზება მიღებულია.");
    }

    @Transactional(readOnly = true)
    public List<TopicSuggestionView> listSuggestions(TopicSuggestion.Status status) {
        return suggestions.findSuggestions(status).stream()
                .map(TopicSuggestionView::fromEntity)
                .toList();
    }

    @Transactional(readOnly = true)
    public TopicSuggestionView getSuggestion(Long id) {
        TopicSuggestion entity = suggestions.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "შემოთავაზება ვერ მოიძებნა"));
        return TopicSuggestionView.fromEntity(entity);
    }

    @Transactional
    public TopicSuggestionView approveSuggestion(Long id, ReviewTopicSuggestionRequest req) {
        TopicSuggestion entity = suggestions.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "შემოთავაზება ვერ მოიძებნა"));

        entity.setStatus(TopicSuggestion.Status.APPROVED);
        entity.setReviewedAt(Instant.now());
        if (req != null && req.reviewNote() != null && !req.reviewNote().isBlank()) {
            entity.setReviewNote(req.reviewNote().trim());
        }
        suggestions.save(entity);
        return TopicSuggestionView.fromEntity(entity);
    }

    @Transactional
    public TopicSuggestionView rejectSuggestion(Long id, ReviewTopicSuggestionRequest req) {
        TopicSuggestion entity = suggestions.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "შემოთავაზება ვერ მოიძებნა"));

        entity.setStatus(TopicSuggestion.Status.REJECTED);
        entity.setReviewedAt(Instant.now());
        if (req != null && req.reviewNote() != null && !req.reviewNote().isBlank()) {
            entity.setReviewNote(req.reviewNote().trim());
        }
        suggestions.save(entity);
        return TopicSuggestionView.fromEntity(entity);
    }

    private void checkRateLimits(String clientIp) {
        if (hourlyLimit <= 0) return;

        Instant now = Instant.now();

        Instant last = lastSubmission.get(clientIp);
        if (last != null && cooldownSeconds > 0) {
            long elapsed = Duration.between(last, now).toSeconds();
            if (elapsed < cooldownSeconds) {
                log.warn("topic suggestion cooldown triggered for {}: only {}s elapsed", clientIp, elapsed);
                throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                        "გთხოვთ დაიცადოთ რამდენიმე წამი შემდეგი შემოთავაზების გაგზავნამდე.");
            }
        }

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
                log.warn("topic suggestion rate limit exceeded for {}: {} submissions in last hour", clientIp, times.size());
                throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                        "ძალიან ბევრი შემოთავაზება გაიგზავნა. გთხოვთ სცადოთ მოგვიანებით.");
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

    public void resetLimits() {
        clientHistory.clear();
        lastSubmission.clear();
    }
}
