import 'package:flutter_test/flutter_test.dart';
import 'package:jeopard_app/core/models.dart';
import 'package:jeopard_app/host/package_search.dart';

void main() {
  PackageSummary pkg(
    int number, {
    String? subtitle,
    bool generated = false,
    String? sourceUrl,
    List<String> topics = const [],
  }) {
    return PackageSummary(
      id: number,
      number: number,
      title: 'პაკეტი #$number',
      subtitle: subtitle ?? (generated ? 'გენერირებული პაკეტი (Gemini) · ზოგადი' : '2008 წელი'),
      sourceUrl: sourceUrl ?? (generated ? 'generated:gemini-pro' : null),
      rounds: [
        RoundSummary(
          id: number * 10 + 1,
          idx: 1,
          finalRound: false,
          playable: true,
          topicCount: topics.length,
          topics: [
            for (var i = 0; i < topics.length; i++)
              TopicSummary(id: number * 100 + i, idx: i + 1, name: topics[i]),
          ],
        ),
      ],
    );
  }

  final testPackages = [
    pkg(1, subtitle: 'შესარჩევი ტური. ავტორები: გაგი გაბრიჭიძე და ვახტანგ ლომჯარია'),
    pkg(2, subtitle: 'ფინალური ტური. ავტორები: გაგი გაბრიჭიძე და ვახტანგ ლომჯარია. 2008 წელი.'),
    pkg(3, subtitle: 'შესარჩევი ტური. ავტორები: სოსო ბერიკაშვილი და მიშა სესიაშვილი. 2008 წელი.'),
    pkg(7, generated: true, subtitle: 'გენერირებული პაკეტი (Gemini) · ზოგადი / შერეული თემატიკა'),
    pkg(8, generated: true, subtitle: 'გენერირებული პაკეტი (Gemini) · მეცნიერება და ბუნება'),
    pkg(12, generated: true, subtitle: 'გენერირებული პაკეტი (Gemini) · მსოფლიო გეოგრაფია და დიდი აღმოჩენები'),
    pkg(22, generated: true, subtitle: 'გენერირებული პაკეტი (Gemini) · ასტრონომია და კოსმოსის კვლევა'),
    pkg(35, generated: true, subtitle: 'გენერირებული პაკეტი (Gemini) · დროშები, გერბები და სიმბოლოები'),
    pkg(43, generated: true, subtitle: 'გენერირებული პაკეტი (Gemini) · არქეოლოგია და დაკარგული ცივილიზაციები'),
    pkg(51, generated: true, sourceUrl: 'generated:argon', subtitle: 'გენერირებული პაკეტი (Argon AI) · ანტიკური სამყარო, კლასიკური ხელოვნება, კინო და მეცნიერება'),
    pkg(55, generated: true, sourceUrl: 'generated:argon', subtitle: 'გენერირებული პაკეტი (Argon AI) · საქართველოს პირველი რესპუბლიკა, სკანდინავიური მითოლოგია და ასტრონომია'),
    pkg(56, generated: true, sourceUrl: 'generated:argon', subtitle: 'გენერირებული პაკეტი (Argon AI) · ანტიკური ფილოსოფია, ანტიუტოპიები, გენეტიკა, ჭადრაკი და შუა საუკუნეები'),
    pkg(57, generated: true, sourceUrl: 'generated:argon', subtitle: 'გენერირებული პაკეტი (Argon AI) · რომის იმპერატორები, როკ-მუსიკა, მედიცინის ნობელი და ასტრონომია'),
  ];

  group('PackageSearch - Smart Searching', () {
    test('Number match jumps to top', () {
      final res = PackageSearch.search(testPackages, '55');
      expect(res.isNotEmpty, isTrue);
      expect(res.first.package.number, 55);

      final resWithHash = PackageSearch.search(testPackages, '#12');
      expect(resWithHash.isNotEmpty, isTrue);
      expect(resWithHash.first.package.number, 12);
    });

    test('Georgian direct search finds packages', () {
      final res = PackageSearch.search(testPackages, 'ჭადრაკი');
      expect(res.length, 1);
      expect(res.first.package.number, 56);

      final resAstro = PackageSearch.search(testPackages, 'ასტრონომია');
      expect(resAstro.length, 3);
      final numbers = resAstro.map((r) => r.package.number).toList();
      expect(numbers, containsAll([22, 55, 57]));
    });

    test('Latin transliteration finds Georgian text', () {
      // "astronomia" -> "ასტრონომია"
      final resAstro = PackageSearch.search(testPackages, 'astronomia');
      expect(resAstro.length, 3);
      expect(resAstro.map((r) => r.package.number), containsAll([22, 55, 57]));

      // "chadraki" -> "ჭადრაკი"
      final resChess = PackageSearch.search(testPackages, 'chadraki');
      expect(resChess.length, 1);
      expect(resChess.first.package.number, 56);

      // "arkeologia" -> "არქეოლოგია"
      final resArch = PackageSearch.search(testPackages, 'arkeologia');
      expect(resArch.length, 1);
      expect(resArch.first.package.number, 43);

      // "arqeologia" -> "არქეოლოგია"
      final resArchQ = PackageSearch.search(testPackages, 'arqeologia');
      expect(resArchQ.length, 1);
      expect(resArchQ.first.package.number, 43);

      // "saqartvelo" / "sakartvelo" -> "საქართველო"
      final resGeoQ = PackageSearch.search(testPackages, 'saqartvelo');
      expect(resGeoQ.length, 1);
      expect(resGeoQ.first.package.number, 55);

      final resGeoK = PackageSearch.search(testPackages, 'sakartvelo');
      expect(resGeoK.length, 1);
      expect(resGeoK.first.package.number, 55);

      // "drosha" -> "დროშები"
      final resFlag = PackageSearch.search(testPackages, 'drosha');
      expect(resFlag.length, 1);
      expect(resFlag.first.package.number, 35);
    });

    test('Author search works', () {
      final res = PackageSearch.search(testPackages, 'გაბრიჭიძე');
      expect(res.length, 2);
      expect(res.map((r) => r.package.number), containsAll([1, 2]));

      final resLatin = PackageSearch.search(testPackages, 'gabrichidze');
      expect(resLatin.length, 2);
      expect(resLatin.map((r) => r.package.number), containsAll([1, 2]));

      final resBerikashvili = PackageSearch.search(testPackages, 'berikashvili');
      expect(resBerikashvili.length, 1);
      expect(resBerikashvili.first.package.number, 3);
    });

    test('Provenance keywords filter and rank', () {
      final resGemini = PackageSearch.search(testPackages, 'gemini');
      expect(resGemini.every((r) => r.package.isGemini), isTrue);

      final resArgon = PackageSearch.search(testPackages, 'argon');
      expect(resArgon.every((r) => r.package.isArgon), isTrue);

      final res2008 = PackageSearch.search(testPackages, '2008');
      expect(res2008.map((r) => r.package.number), containsAll([2, 3]));
    });

    test('Multi-token queries require all tokens to match', () {
      final res = PackageSearch.search(testPackages, 'argon ასტრონომია');
      expect(res.length, 2);
      expect(res.map((r) => r.package.number), containsAll([55, 57]));

      final resGeminiAstro = PackageSearch.search(testPackages, 'gemini astronomia');
      expect(resGeminiAstro.length, 1);
      expect(resGeminiAstro.first.package.number, 22);
    });

    test('Fuzzy matching handles small typos', () {
      // 1-character typo: "ასტრონომა" instead of "ასტრონომია"
      final res = PackageSearch.search(testPackages, 'ასტრონომა');
      expect(res.isNotEmpty, isTrue);
      expect(res.map((r) => r.package.number), contains(22));

      // 1-character typo: "არქელოგია" instead of "არქეოლოგია"
      final resArch = PackageSearch.search(testPackages, 'არქელოგია');
      expect(resArch.isNotEmpty, isTrue);
      expect(resArch.first.package.number, 43);
    });

    test('Random package keyword detection', () {
      expect(PackageSearch.matchesRandom('random'), isTrue);
      expect(PackageSearch.matchesRandom('შემთხვევითი'), isTrue);
      expect(PackageSearch.matchesRandom('რენდომი'), isTrue);
      expect(PackageSearch.matchesRandom('shuffle'), isTrue);
      expect(PackageSearch.matchesRandom('ასტრონომია'), isFalse);
    });

    test('PackageSourceFilter works properly', () {
      final orig = PackageSearch.search(testPackages, '', filter: PackageSourceFilter.original);
      expect(orig.length, 3);
      expect(orig.map((r) => r.package.number), containsAll([1, 2, 3]));

      final gemini = PackageSearch.search(testPackages, '', filter: PackageSourceFilter.gemini);
      expect(gemini.length, 6);

      final argon = PackageSearch.search(testPackages, '', filter: PackageSourceFilter.argon);
      expect(argon.length, 4);
      expect(argon.map((r) => r.package.number), containsAll([51, 55, 56, 57]));
    });

    test('Highlight ranges are properly calculated', () {
      final ranges = PackageSearch.findHighlights(
        'სკანდინავიური მითოლოგია და ასტრონომია',
        ['mitologia'],
      );
      expect(ranges.isNotEmpty, isTrue);
      final (start, end) = ranges.first;
      expect('სკანდინავიური მითოლოგია და ასტრონომია'.substring(start, end), 'მითოლოგია');
    });

    test('Query with no matches returns empty list', () {
      final res = PackageSearch.search(testPackages, 'არარსებულითემა12345');
      expect(res, isEmpty);
    });

    test('Empty search string returns all packages preserving order', () {
      final res = PackageSearch.search(testPackages, '');
      expect(res.length, testPackages.length);
    });

    test('Georgian grammatical suffixes match base topic', () {
      // "საქართველოში" matches "საქართველოს" / "საქართველო"
      final res = PackageSearch.search(testPackages, 'საქართველოში');
      expect(res.isNotEmpty, isTrue);
      expect(res.map((r) => r.package.number), contains(55));

      // "ასტრონომიაზე" matches "ასტრონომია"
      final resAstro = PackageSearch.search(testPackages, 'ასტრონომიაზე');
      expect(resAstro.isNotEmpty, isTrue);
      expect(resAstro.map((r) => r.package.number), contains(22));
    });
  });
}
