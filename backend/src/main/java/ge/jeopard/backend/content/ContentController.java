package ge.jeopard.backend.content;

import ge.jeopard.backend.content.ContentDtos.BoardView;
import ge.jeopard.backend.content.ContentDtos.PackageSummary;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api")
public class ContentController {

    private final ContentService content;

    ContentController(ContentService content) {
        this.content = content;
    }

    @GetMapping("/packages")
    public List<PackageSummary> packages() {
        return content.listPackages();
    }

    @PostMapping("/packages/random")
    public PackageSummary randomPackage() {
        return content.generateRandomPackage();
    }

    @GetMapping("/rounds/{roundId}/board")
    public BoardView board(@PathVariable Long roundId) {
        return content.board(roundId);
    }
}
