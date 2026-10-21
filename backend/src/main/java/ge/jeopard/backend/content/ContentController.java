package ge.jeopard.backend.content;

import ge.jeopard.backend.content.ContentDtos.AvailableTopic;
import ge.jeopard.backend.content.ContentDtos.BoardView;
import ge.jeopard.backend.content.ContentDtos.BuildPackageRequest;
import ge.jeopard.backend.content.ContentDtos.PackageSummary;
import ge.jeopard.backend.content.ContentDtos.ReplaceTopicRequest;
import ge.jeopard.backend.content.ContentDtos.TopicSummary;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.List;

@RestController
@RequestMapping("/api")
public class ContentController {

    /**
     * How long a browser may reuse the package list without asking.
     *
     * <p>Short enough that a reseed reaches an open tab within a minute, long
     * enough that walking back into the picker -- which a host does repeatedly
     * while setting a game up -- costs no request at all.
     */
    private static final Duration PACKAGES_MAX_AGE = Duration.ofMinutes(1);

    private final ContentService content;

    ContentController(ContentService content) {
        this.content = content;
    }

    @GetMapping("/packages")
    public ResponseEntity<List<PackageSummary>> packages(
            @RequestHeader(value = HttpHeaders.IF_NONE_MATCH, required = false) String ifNoneMatch) {
        List<PackageSummary> list = content.listPackages();
        if (list.isEmpty()) {
            return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(list);
        }
        String tag = content.packagesTag();
        if (matches(ifNoneMatch, tag)) {
            return ResponseEntity.status(HttpStatus.NOT_MODIFIED).eTag(tag).build();
        }
        return ResponseEntity.ok()
                .eTag(tag)
                .cacheControl(CacheControl.maxAge(PACKAGES_MAX_AGE).cachePublic())
                .body(list);
    }

    @GetMapping("/packages/{packageId}")
    public PackageSummary getPackage(@PathVariable Long packageId) {
        return content.getPackage(packageId);
    }

    @PostMapping("/packages/random")
    public PackageSummary randomPackage() {
        return content.generateRandomPackage();
    }

    @PostMapping("/packages/build")
    public PackageSummary buildCustomPackage(@RequestBody(required = false) BuildPackageRequest request) {
        return content.buildCustomPackage(request);
    }

    @PostMapping("/packages/{packageId}/topics/{topicId}/reroll")
    public TopicSummary rerollTopic(
            @PathVariable Long packageId,
            @PathVariable Long topicId) {
        return content.rerollTopic(packageId, topicId);
    }

    @PostMapping("/packages/{packageId}/topics/{topicId}/replace")
    public TopicSummary replaceTopic(
            @PathVariable Long packageId,
            @PathVariable Long topicId,
            @RequestBody ReplaceTopicRequest request) {
        return content.replaceTopic(packageId, topicId, request != null ? request.sourceTopicId() : null);
    }

    @GetMapping("/topics/available")
    public List<AvailableTopic> availableTopics(
            @RequestParam(required = false) Integer roundIdx,
            @RequestParam(required = false) String query) {
        return content.availableTopics(roundIdx, query);
    }

    @GetMapping("/rounds/{roundId}/board")
    public BoardView board(@PathVariable Long roundId) {
        return content.board(roundId);
    }

    /**
     * If-None-Match is a comma-separated list, and a proxy is entitled to have
     * weakened the tag on the way out, so neither the count nor the {@code W/}
     * prefix can be assumed.
     */
    private static boolean matches(String ifNoneMatch, String tag) {
        if (ifNoneMatch == null || ifNoneMatch.isBlank()) return false;
        for (String candidate : ifNoneMatch.split(",")) {
            String trimmed = candidate.trim();
            if (trimmed.startsWith("W/")) trimmed = trimmed.substring(2);
            if (trimmed.equals("*") || trimmed.equals(tag)) return true;
        }
        return false;
    }
}
