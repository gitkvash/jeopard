import '../core/models.dart';

/// Provenance filter for packages.
enum PackageSourceFilter {
  all,
  original,
  gemini,
  argon,
  ai;

  bool matches(PackageSummary p) {
    return switch (this) {
      PackageSourceFilter.all => true,
      PackageSourceFilter.original => !p.generated,
      PackageSourceFilter.gemini => p.isGemini,
      PackageSourceFilter.argon => p.isArgon,
      PackageSourceFilter.ai => p.isAi,
    };
  }
}

/// A search hit with relevance score and highlight ranges for UI rendering.
class PackageSearchResult {
  const PackageSearchResult({
    required this.package,
    required this.score,
    this.titleHighlights = const [],
    this.subtitleHighlights = const [],
  });

  final PackageSummary package;
  final double score;
  final List<(int, int)> titleHighlights;
  final List<(int, int)> subtitleHighlights;
}

/// Subtitle formatter that strips standard generated packet prefixes for display.
String? cardSubtitle(String? raw) {
  if (raw == null) return null;
  final dot = raw.indexOf(' · ');
  if (dot != -1 && raw.startsWith('გენერირებული პაკეტი')) {
    return raw.substring(dot + 3).trim();
  }
  return raw;
}

/// Smart search and phonetic transliteration for Georgian Jeopardy packages.
class PackageSearch {
  const PackageSearch._();

  /// Converts English keyboard Shift-keys to Georgian uppercase equivalents.
  static String preprocessGeoLayout(String input) {
    final sb = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      final mapped = switch (ch) {
        'T' => 'თ',
        'W' => 'ჭ',
        'R' => 'ღ',
        'S' => 'შ',
        'C' => 'ჩ',
        'Z' => 'ძ',
        'J' => 'ჟ',
        _ => ch,
      };
      sb.write(mapped);
    }
    return sb.toString();
  }

  /// Converts Latin characters / digraphs to standard Georgian phonetic layout.
  static String latinToGeorgian(String input) {
    var s = preprocessGeoLayout(input);
    s = s
        .replaceAll("ch'", 'ჭ')
        .replaceAll('tch', 'ჭ')
        .replaceAll('ch', 'ჩ')
        .replaceAll('sh', 'შ')
        .replaceAll('zh', 'ჟ')
        .replaceAll('ts', 'ც')
        .replaceAll('dz', 'ძ')
        .replaceAll('kh', 'ხ')
        .replaceAll('gh', 'ღ');

    final sb = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      final mapped = switch (ch) {
        'a' || 'A' => 'ა',
        'b' || 'B' => 'ბ',
        'g' || 'G' => 'გ',
        'd' || 'D' => 'დ',
        'e' || 'E' => 'ე',
        'v' || 'V' => 'ვ',
        'z' => 'ზ',
        't' => 'თ',
        'i' || 'I' => 'ი',
        'k' || 'K' => 'კ',
        'l' || 'L' => 'ლ',
        'm' || 'M' => 'მ',
        'n' || 'N' => 'ნ',
        'o' || 'O' => 'ო',
        'p' || 'P' => 'პ',
        'r' => 'რ',
        's' => 'ს',
        'u' || 'U' => 'უ',
        'f' || 'F' => 'ფ',
        'q' || 'Q' => 'ქ',
        'y' || 'Y' => 'ყ',
        'w' => 'წ',
        'x' || 'X' => 'ხ',
        'j' => 'ჯ',
        'h' || 'H' => 'ჰ',
        'c' => 'ც',
        _ => ch,
      };
      sb.write(mapped);
    }
    return sb.toString();
  }

  /// Reduces a string to a canonical phonetic key, grouping acoustically similar
  /// consonants (e.g. k/q/კ/ქ/ყ, t/თ/ტ, p/f/პ/ფ, ch/ჩ/ჭ, ts/c/w/ც/წ, j/zh/ძ/ჯ/ჟ, kh/gh/x/ხ/ღ).
  static String toCanonicalPhonetic(String input) {
    if (input.isEmpty) return '';
    var s = preprocessGeoLayout(input);
    s = s.toLowerCase();

    s = s
        .replaceAll("ch'", 'C')
        .replaceAll('tch', 'C')
        .replaceAll('ch', 'C')
        .replaceAll('sh', 'S')
        .replaceAll('zh', 'J')
        .replaceAll('ts', 'Z')
        .replaceAll('dz', 'J')
        .replaceAll('kh', 'X')
        .replaceAll('gh', 'X');

    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      final mapped = switch (ch) {
        'კ' || 'ქ' || 'ყ' || 'k' || 'q' => 'K',
        'ტ' || 'თ' || 't' => 'T',
        'პ' || 'ფ' || 'p' || 'f' => 'P',
        'ჩ' || 'ჭ' || 'C' || 'w' || 'W' => 'C',
        'ც' || 'წ' || 'c' || 'Z' => 'Z',
        'ძ' || 'ჯ' || 'ჟ' || 'j' || 'J' => 'J',
        'ხ' || 'ღ' || 'x' || 'X' || 'R' => 'X',
        'შ' || 'S' => 'S',
        'ს' || 's' => 's',
        'ზ' || 'z' => 'z',
        'ბ' || 'b' => 'b',
        'გ' || 'g' => 'g',
        'დ' || 'd' => 'd',
        'ე' || 'e' => 'e',
        'ვ' || 'v' => 'v',
        'ი' || 'i' => 'i',
        'ლ' || 'l' => 'l',
        'მ' || 'm' => 'm',
        'ნ' || 'n' => 'n',
        'ო' || 'o' => 'o',
        'რ' || 'r' => 'r',
        'უ' || 'u' => 'u',
        'ჰ' || 'h' => 'h',
        'ა' || 'a' => 'a',
        _ => ch,
      };
      buf.write(mapped);
    }
    return buf.toString();
  }

  /// Calculates the Levenshtein edit distance between two strings.
  static int levenshtein(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    var v0 = List<int>.generate(s2.length + 1, (i) => i);
    var v1 = List<int>.filled(s2.length + 1, 0);

    for (var i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (var j = 0; j < s2.length; j++) {
        final cost = s1[i] == s2[j] ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce(
          (a, b) => a < b ? a : b,
        );
      }
      final temp = v0;
      v0 = v1;
      v1 = temp;
    }

    return v0[s2.length];
  }

  /// Checks if the query matches the random package card.
  static bool matchesRandom(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    final canonical = toCanonicalPhonetic(q);
    const keywords = [
      'random',
      'shuffle',
      'შემთხვევითი',
      'რენდომი',
      'რენდომ',
      'არევა',
    ];
    for (final kw in keywords) {
      if (kw.contains(q) || q.contains(kw)) return true;
      if (toCanonicalPhonetic(kw).contains(canonical)) return true;
    }
    return false;
  }

  /// Extracts integer package number if the query contains one (e.g. "#5", "5", "პაკეტი 12").
  static int? extractTargetNumber(String query) {
    final match = RegExp(r'(?:^|[^\d])#?(\d+)(?:$|[^\d])').firstMatch(query);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Splits query into non-empty tokens.
  static List<String> tokenize(String query) {
    return query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && t != '#' && t != '№')
        .toList();
  }

  /// Filters and scores packages according to query and provenance filter.
  static List<PackageSearchResult> search(
    List<PackageSummary> packages,
    String rawQuery, {
    PackageSourceFilter filter = PackageSourceFilter.all,
  }) {
    // 1. Filter by provenance
    final candidatePackages = packages.where(filter.matches).toList();

    final query = rawQuery.trim();
    if (query.isEmpty) {
      return candidatePackages
          .map((p) => PackageSearchResult(package: p, score: 0))
          .toList();
    }

    final tokens = tokenize(query);
    final targetNumber = extractTargetNumber(query);
    final results = <PackageSearchResult>[];

    for (final p in candidatePackages) {
      final dispSubtitle = cardSubtitle(p.subtitle) ?? '';
      final title = p.title;
      final fullText = '$title $dispSubtitle ${p.subtitle ?? ''}'.toLowerCase();
      final canonicalFull = toCanonicalPhonetic(fullText);

      double score = 0;
      var allTokensMatched = true;

      // Check number match
      if (targetNumber != null) {
        if (p.number == targetNumber) {
          score += 2000;
        } else if ('${p.number}'.contains('$targetNumber')) {
          score += 250;
        }
      }

      // Check provenance matches (Gemini, Argon, AI, 2008 archive)
      for (final t in tokens) {
        final canT = toCanonicalPhonetic(t);
        if ((t == 'gemini' || t == 'გემინი' || canT == 'Jemini') && p.isGemini) {
          score += 400;
        } else if ((t == 'argon' || t == 'არგონი' || canT == 'arGoni') &&
            p.isArgon) {
          score += 400;
        } else if ((t == 'ai' ||
                t == 'აი' ||
                t == 'claude' ||
                t == 'ქლოდი' ||
                canT == 'klodi') &&
            p.isAi) {
          score += 400;
        } else if ((t == '2008' ||
                t == 'არქივი' ||
                t == 'ორიგინალი' ||
                t == 'original' ||
                t == 'archive') &&
            !p.generated &&
            !p.isArgon) {
          score += 400;
        }
      }

      // Token matching across title and subtitle
      for (final rawToken in tokens) {
        final token = rawToken.replaceAll(RegExp(r'^#+'), '');
        if (token.isEmpty) continue;

        final geoToken = latinToGeorgian(token).toLowerCase();
        final canToken = toCanonicalPhonetic(token);
        var tokenMatched = false;

        // 1. Direct substring in title
        if (title.toLowerCase().contains(token)) {
          score += 200;
          tokenMatched = true;
        } else if (geoToken.isNotEmpty &&
            title.toLowerCase().contains(geoToken)) {
          score += 180;
          tokenMatched = true;
        }

        // 2. Direct substring in subtitle
        if (dispSubtitle.toLowerCase().contains(token)) {
          score += 150;
          tokenMatched = true;
        } else if (geoToken.isNotEmpty &&
            dispSubtitle.toLowerCase().contains(geoToken)) {
          score += 140;
          tokenMatched = true;
        }

        // 3. Canonical phonetic match
        if (!tokenMatched && canonicalFull.contains(canToken)) {
          score += 100;
          tokenMatched = true;
        }

        // Provenance keyword match
        if (!tokenMatched) {
          if ((token == 'gemini' || token == 'გემინი' || canToken == 'Jemini') && p.isGemini) {
            tokenMatched = true;
          } else if ((token == 'argon' || token == 'არგონი' || canToken == 'arGoni') && p.isArgon) {
            tokenMatched = true;
          } else if ((token == 'ai' || token == 'აი' || token == 'claude' || token == 'ქლოდი' || canToken == 'klodi') && p.isAi) {
            tokenMatched = true;
          }
        }

        // 3b. Vowel-stripped stem match (e.g. "drosha" -> "drosh" matches "droshebi / დროშები")
        if (!tokenMatched && token.length >= 4) {
          final lastChar = token[token.length - 1];
          if ('aeiouაეიოუ'.contains(lastChar)) {
            final stem = token.substring(0, token.length - 1);
            final geoStem = latinToGeorgian(stem).toLowerCase();
            final canStem = toCanonicalPhonetic(stem);
            if (dispSubtitle.toLowerCase().contains(stem) ||
                (geoStem.isNotEmpty && dispSubtitle.toLowerCase().contains(geoStem)) ||
                canonicalFull.contains(canStem)) {
              score += 90;
              tokenMatched = true;
            }
          }
        }

        // 4. Topic names match (if available in rounds)
        if (!tokenMatched && p.rounds.isNotEmpty) {
          for (final round in p.rounds) {
            for (final topic in round.topics) {
              final topicLower = topic.name.toLowerCase();
              if (topicLower.contains(token) ||
                  (geoToken.isNotEmpty && topicLower.contains(geoToken)) ||
                  toCanonicalPhonetic(topicLower).contains(canToken)) {
                score += 90;
                tokenMatched = true;
                break;
              }
            }
            if (tokenMatched) break;
          }
        }

        // 5. Fuzzy typo tolerance (Levenshtein) on words
        if (!tokenMatched && token.length >= 4) {
          final words = _extractWords(fullText);
          for (final word in words) {
            final maxDist = token.length >= 7 ? 2 : 1;
            final canWord = toCanonicalPhonetic(word);
            if (levenshtein(canToken, canWord) <= maxDist ||
                levenshtein(token, word) <= maxDist ||
                (geoToken.isNotEmpty &&
                    levenshtein(geoToken, word) <= maxDist)) {
              score += 40;
              tokenMatched = true;
              break;
            }
          }
        }

        // Allow single number token match to count
        if (!tokenMatched && targetNumber != null && p.number == targetNumber) {
          tokenMatched = true;
        }

        if (!tokenMatched) {
          allTokensMatched = false;
        }
      }

      if (score > 0 && allTokensMatched) {
        score += 300; // Multi-token conjunction bonus
      }

      // If at least one strong match or direct number match
      if (score > 0 && (allTokensMatched || targetNumber == p.number)) {
        final titleHighlights = findHighlights(title, tokens);
        final subtitleHighlights = findHighlights(dispSubtitle, tokens);
        results.add(
          PackageSearchResult(
            package: p,
            score: score,
            titleHighlights: titleHighlights,
            subtitleHighlights: subtitleHighlights,
          ),
        );
      }
    }

    // Sort: score descending, number ascending
    results.sort((a, b) {
      final sc = b.score.compareTo(a.score);
      if (sc != 0) return sc;
      return a.package.number.compareTo(b.package.number);
    });

    return results;
  }

  /// Finds highlight ranges within [text] for [tokens].
  static List<(int, int)> findHighlights(String text, List<String> tokens) {
    if (text.isEmpty || tokens.isEmpty) return const [];

    final ranges = <(int, int)>[];
    final lower = text.toLowerCase();
    final words = _extractWordsWithRanges(text);

    for (final rawToken in tokens) {
      final token = rawToken.replaceAll(RegExp(r'^#+'), '').trim().toLowerCase();
      if (token.isEmpty) continue;

      // 1. Direct substring
      var searchStart = 0;
      while (searchStart < lower.length) {
        final idx = lower.indexOf(token, searchStart);
        if (idx == -1) break;
        ranges.add((idx, idx + token.length));
        searchStart = idx + token.length;
      }

      // 2. Transliterated Georgian substring
      final geoToken = latinToGeorgian(token).toLowerCase();
      if (geoToken != token && geoToken.isNotEmpty) {
        searchStart = 0;
        while (searchStart < lower.length) {
          final idx = lower.indexOf(geoToken, searchStart);
          if (idx == -1) break;
          ranges.add((idx, idx + geoToken.length));
          searchStart = idx + geoToken.length;
        }
      }

      // 3. Canonical phonetic / fuzzy word matching
      final canToken = toCanonicalPhonetic(token);
      final canStem = token.length >= 4 && 'aeiouაეიოუ'.contains(token[token.length - 1])
          ? toCanonicalPhonetic(token.substring(0, token.length - 1))
          : null;

      for (final w in words) {
        final canWord = toCanonicalPhonetic(w.text);
        if (canToken.length >= 2 && canWord.contains(canToken)) {
          ranges.add((w.start, w.end));
        } else if (canStem != null && canStem.length >= 2 && canWord.contains(canStem)) {
          ranges.add((w.start, w.end));
        } else if (token.length >= 4) {
          final maxDist = token.length >= 7 ? 2 : 1;
          if (levenshtein(canToken, canWord) <= maxDist) {
            ranges.add((w.start, w.end));
          }
        }
      }
    }

    return _mergeRanges(ranges);
  }

  static List<String> _extractWords(String text) {
    return RegExp(r'[^\s,·—\(\)\[\]\.\:\#]+')
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toList();
  }

  static List<({String text, int start, int end})> _extractWordsWithRanges(
    String text,
  ) {
    final result = <({String text, int start, int end})>[];
    final matches = RegExp(r'[^\s,·—\(\)\[\]\.\:\#]+').allMatches(text);
    for (final m in matches) {
      result.add((text: m.group(0)!, start: m.start, end: m.end));
    }
    return result;
  }

  static List<(int, int)> _mergeRanges(List<(int, int)> raw) {
    if (raw.isEmpty) return const [];
    raw.sort(
      (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
    );

    final merged = <(int, int)>[];
    var currentStart = raw.first.$1;
    var currentEnd = raw.first.$2;

    for (var i = 1; i < raw.length; i++) {
      final next = raw[i];
      if (next.$1 <= currentEnd) {
        if (next.$2 > currentEnd) {
          currentEnd = next.$2;
        }
      } else {
        merged.add((currentStart, currentEnd));
        currentStart = next.$1;
        currentEnd = next.$2;
      }
    }
    merged.add((currentStart, currentEnd));
    return merged;
  }
}
