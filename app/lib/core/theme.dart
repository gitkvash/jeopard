import 'package:flutter/material.dart';

/// The palette of a dark hall with pooled light, rather than a bright studio.
///
/// Jeopardy's board grammar -- blue tiles, gold values -- set in the register of
/// "რა? სად? როდის?": brass instead of yellow, crimson instead of red, and a
/// backdrop that falls away to almost black at the edges so the board reads as
/// lit rather than drawn.
class JColors {
  const JColors._();

  /// Far edge of the hall, and the colour behind everything.
  static const stage = Color(0xFF05070F);

  /// The pool of light the stage gradient opens up towards the top.
  static const stageLit = Color(0xFF0B1024);

  /// Raised things: score plates, cards, sheets.
  static const surface = Color(0xFF121728);
  static const surfaceHigh = Color(0xFF1A2138);

  /// Hairlines, used sparingly now that depth carries the work.
  static const line = Color(0xFF242C48);

  /// The board. [boardLit] is the top of a tile's bevel, [boardDeep] the bottom.
  static const board = Color(0xFF0A1CB4);
  static const boardLit = Color(0xFF1730D8);
  static const boardDeep = Color(0xFF050C56);

  /// A played tile: part of the grid, visibly out of it.
  static const spent = Color(0xFF0A0D18);

  /// Brass for rules and frames, gold for anything that scores.
  static const brass = Color(0xFF8A6A2A);
  static const gold = Color(0xFFF2C14E);
  static const goldBright = Color(0xFFFFE29A);

  static const correct = Color(0xFF2FBF71);
  static const wrong = Color(0xFFC4162C);
  static const wrongBright = Color(0xFFFF3B4E);
  static const buzz = Color(0xFFC4162C);
  static const buzzBright = Color(0xFFFF3B4E);

  static const text = Color(0xFFF4F5FA);
  static const textMuted = Color(0xFF93A0C0);
  static const textFaint = Color(0xFF5A6584);

  /// Bevel highlight and shadow, for tiles and plates.
  static const bevelTop = Color(0x38FFFFFF);
  static const bevelBottom = Color(0x73000000);

  // Kept so older call sites keep compiling with the new palette.
  static const backdrop = stage;
}

/// Corner radii, in one place so nothing drifts.
class JRadius {
  const JRadius._();

  /// Board tiles are nearly square-cornered: the grid should read as panels of
  /// light separated by black gutters, which rounding softens away.
  static const tile = 3.0;
  static const control = 6.0;
  static const card = 5.0;
  static const panel = 5.0;
}

/// The gap between board tiles. Black, and wide enough to read across a room.
const double kGutter = 7.0;

/// Numerals: condensed, heavy, gold, with a hard shadow under them so they look
/// struck into the tile rather than printed on it.
TextStyle engraved(
  double size, {
  Color color = JColors.gold,
  bool glow = true,
}) => TextStyle(
  fontFamily: 'Condensed',
  fontSize: size,
  fontWeight: FontWeight.w700,
  color: color,
  letterSpacing: -0.5,
  height: 1,
  shadows: [
    Shadow(
      color: Colors.black.withValues(alpha: 0.55),
      offset: const Offset(0, 3),
    ),
    if (glow) Shadow(color: color.withValues(alpha: 0.22), blurRadius: 24),
  ],
);

/// Small all-caps label, the typographic counterweight to [engraved].
const TextStyle kTicker = TextStyle(
  fontFamily: 'Condensed',
  fontSize: 10,
  fontWeight: FontWeight.w700,
  letterSpacing: 2.2,
  color: JColors.brass,
);

/// Every string in this app is Georgian, so the font is a functional
/// requirement rather than styling. Noto Sans Georgian is bundled as an asset
/// so Android, iOS and web render identically instead of falling back to three
/// different system faces -- and so the first launch works with no network.
const String kFontFamily = 'NotoSansGeorgian';

/// The Georgian face carries no digits, Latin letters or punctuation, and this
/// app is full of all three (scores, values, join codes). Naming the fallback
/// explicitly keeps that resolution local instead of letting the web engine
/// fetch a font mid-frame.
const List<String> kFontFallback = <String>['RobotoLatin'];

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: kFontFamily,
    fontFamilyFallback: kFontFallback,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: JColors.goldBright,
      onPrimary: JColors.backdrop,
      secondary: JColors.board,
      onSecondary: Colors.white,
      surface: JColors.surface,
      onSurface: JColors.text,
      surfaceContainerHighest: JColors.surfaceHigh,
      error: JColors.wrong,
      onError: Colors.white,
      outline: JColors.line,
    ),
    scaffoldBackgroundColor: Colors.transparent,
    splashFactory: InkSparkle.splashFactory,
  );

  final text = base.textTheme.apply(
    fontFamily: kFontFamily,
    fontFamilyFallback: kFontFallback,
    bodyColor: JColors.text,
    displayColor: JColors.text,
  );

  return base.copyWith(
    textTheme: text.copyWith(
      displaySmall: text.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.1,
      ),
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: text.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: JColors.textMuted,
      ),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
      labelSmall: text.labelSmall?.copyWith(
        color: JColors.textFaint,
        letterSpacing: 0.8,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: JColors.text,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: JColors.text,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: JColors.line,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: JColors.gold,
        foregroundColor: const Color(0xFF14120A),
        disabledBackgroundColor: JColors.surface,
        disabledForegroundColor: JColors.textFaint,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JRadius.control),
        ),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontFamilyFallback: kFontFallback,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: JColors.text,
        side: const BorderSide(color: JColors.brass),
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JRadius.control),
        ),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontFamilyFallback: kFontFallback,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: JColors.gold,
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontFamilyFallback: kFontFallback,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: JColors.surface,
      hintStyle: const TextStyle(color: JColors.textFaint),
      labelStyle: const TextStyle(color: JColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(JRadius.control),
        borderSide: const BorderSide(color: JColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(JRadius.control),
        borderSide: const BorderSide(color: JColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(JRadius.control),
        borderSide: const BorderSide(color: JColors.goldBright, width: 1.5),
      ),
    ),
    cardTheme: CardThemeData(
      color: JColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JRadius.card),
        side: const BorderSide(color: JColors.line),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      titleTextStyle: TextStyle(
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: JColors.text,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
        fontSize: 12,
        color: JColors.textMuted,
      ),
      iconColor: JColors.textMuted,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? JColors.backdrop
            : JColors.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? JColors.goldBright
            : JColors.surfaceHigh,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(JColors.line),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: JColors.surface,
      selectedColor: JColors.goldBright,
      side: const BorderSide(color: JColors.line),
      labelStyle: const TextStyle(
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JRadius.control),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: JColors.goldBright,
      linearTrackColor: JColors.surfaceHigh,
      circularTrackColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: JColors.surfaceHigh,
      contentTextStyle: const TextStyle(
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
        color: JColors.text,
        fontSize: 14,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JRadius.control),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: JColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JRadius.panel),
        side: const BorderSide(color: JColors.line),
      ),
    ),
    iconTheme: const IconThemeData(color: JColors.textMuted, size: 20),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        // The default zoom transition on web renders a full-screen animation on
        // every push; a fade is cheaper and reads as faster.
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// Georgian UI strings, kept together so they are easy to review and adjust.
class L {
  const L._();

  // roles / setup
  static const appTitle = 'ჯეოპარდი';
  static const tagline = 'ღილაკზე დაჭერით ნათამაშები ვიქტორინა';
  static const host = 'მასპინძელი';
  static const team = 'გუნდი';
  static const iAmHost = 'მასპინძელი ვარ';
  static const iAmHostHint = 'ვირჩევ პაკეტს და ვუძღვები თამაშს';
  static const iAmPlayer = 'ვთამაშობ';
  static const iAmPlayerHint = 'კოდით შევდივარ და ღილაკს ვაჭერ';
  static const chooseRole = 'აირჩიეთ როლი';
  static const newGame = 'ახალი თამაში';
  static const packageLabel = 'პაკეტი';
  static const originalPackages = 'ორიგინალური პაკეტები (2008)';
  static const generatedPackages = 'გენერირებული პაკეტები';
  static const randomPackage = 'შემთხვევითი პაკეტი';
  static const randomPackageHint = 'თემები შემთხვევითობით აირჩევა ყველა პაკეტიდან';
  static const randomPackageError = 'ვერ მოხერხდა შემთხვევითი პაკეტის შექმნა';
  static const choosePackage = 'აირჩიეთ პაკეტი';
  static const choosePackageHint =
      'აირჩიეთ პაკეტი მარცხნივ, პარამეტრები აქ გამოჩნდება';
  static const changePackage = 'პაკეტის შეცვლა';
  static const gameOptions = 'პარამეტრები';
  static const roundLabel = 'ტური';
  static const finalRound = 'ფინალი';
  static const wholePackage = 'სრული პაკეტი';
  static const wholePackageHint = 'სამი ტური და ფინალი, ქულები გროვდება';
  static const hostPlaysToo = 'მასპინძელიც თამაშობს';
  static const hostTeamName = 'მასპინძლის გუნდის სახელი';

  // how the buzzer opens
  static const buzzModeLabel = 'ღილაკის გახსნა';
  static const buzzModeHost = 'მასპინძელი ხსნის';
  static const buzzModeHostHint =
      'შეკითხვის წაკითხვის შემდეგ ღილაკს თქვენ აჭერთ';
  static const buzzModeInstant = 'მაშინვე';
  static const buzzModeInstantHint = 'ღილაკი შეკითხვასთან ერთად იხსნება';
  static const buzzModeTimer = 'ავტომატურად';
  static const buzzModeTimerHint =
      'ღილაკი თავად იხსნება მითითებული წამების შემდეგ';
  static const buzzDelayLabel = 'დაყოვნება';
  static const seconds = 'წმ';
  static const customDelay = 'სხვა';
  static const customDelayField = 'წამები';
  static const buzzDelayRange = 'აირჩიეთ 1-დან 120 წამამდე';
  static const buzzOpensIn = 'ღილაკი იხსნება';
  static const openNow = 'ახლავე გახსნა';
  static const create = 'შექმნა';
  static const server = 'სერვერი';
  static const clues = 'შეკითხვა';

  // lobby / join
  static const joinCode = 'კოდი';
  static const enterCode = 'შეიყვანეთ კოდი';
  static const teamName = 'გუნდის სახელი';
  static const yourName = 'თქვენი სახელი';
  static const chooseTeam = 'აირჩიეთ გუნდი';
  static const createTeam = 'ახალი გუნდის შექმნა';
  static const newTeamName = 'ახალი გუნდის სახელი';
  static const members = 'წევრები';
  static const joinThisTeam = 'შეუერთდი';
  static const next2 = 'გაგრძელება';
  static const joinGame = 'შესვლა';
  static const waitingForHost = 'ველოდებით მასპინძელს';
  static const teamsJoined = 'შემოსული გუნდები';
  static const startGame = 'თამაშის დაწყება';
  static const noTeamsYet = 'ჯერ არავინ შემოსულა';
  static const shareCode = 'უთხარით მოთამაშეებს ეს კოდი';
  static const shareLink = 'ბმულის კოპირება';
  static const qrCode = 'QR კოდი';
  static const linkCopied = 'ბმული დაკოპირდა';
  static const copied = 'კოდი დაკოპირდა';

  // board / clue
  static const chooseTile = 'აირჩიეთ შეკითხვა';
  static const hostIsChoosing = 'მასპინძელი ირჩევს შეკითხვას';
  static const points = 'ქულა';
  static const nowPlaying = 'თამაშში';
  static const remaining = 'დარჩენილია';
  static const openBuzzer = 'ღილაკის გახსნა';
  static const buzzerOpen = 'ღილაკი გახსნილია';
  static const buzzerClosed = 'ღილაკი დახურულია';
  static const waitingForBuzz = 'ველოდებით პასუხს';
  static const buzz = 'ვიცი!';
  static const youBuzzed = 'თქვენ დააჭირეთ! უპასუხეთ';
  static const buzzedIn = 'დააჭირა';
  static const correct = 'სწორი';
  static const wrong = 'არასწორი';
  static const showAnswer = 'პასუხის ნახვა';
  static const answer = 'პასუხი';
  static const next = 'შემდეგი';
  static const pass = 'გამოტოვება';
  static const lockedOut = 'დაბლოკილია';
  static const correctionNote = 'შესწორება';
  static const score = 'ქულა';
  static const readAloud = 'წაიკითხეთ ხმამაღლა';
  static const peekWarning =
      'პასუხის ნახვა ამ შეკითხვაზე თქვენს ღილაკს გათიშავს';

  // final round
  static const wager = 'ფსონი';
  static const yourWager = 'თქვენი ფსონი';
  static const submitWager = 'ფსონის დადება';
  static const waitingForWagers = 'ველოდებით ფსონებს';
  static const openFinalClue = 'ფინალური შეკითხვის გახსნა';
  static const finalResults = 'ფინალური შედეგი';
  static const maxWager = 'მაქსიმუმ';

  // end
  static const gameOver = 'თამაში დასრულდა';
  static const winner = 'გამარჯვებული';
  static const backToStart = 'თავიდან';

  // session / connection
  static const connecting = 'ვუკავშირდებით...';
  static const offline = 'კავშირი გაწყდა';
  static const online = 'ხაზზეა';
  static const retry = 'ხელახლა';
  static const restoring = 'თამაშს ვაბრუნებთ...';
  static const resume = 'თამაშის გაგრძელება';
  static const resumeHint = 'დაწყებული თამაში გაქვთ';
  static const leaveGame = 'თამაშიდან გასვლა';
  static const leaveGameHint =
      'ამ მოწყობილობაზე შენახული სესია წაიშლება. თამაში სხვებისთვის გაგრძელდება.';
  static const sessionGone = 'შენახული თამაში ვერ მოიძებნა';
  static const cancel = 'გაუქმება';
  static const ok = 'კარგი';

  // errors
  static const connectionError =
      'სერვერთან დაკავშირება ვერ მოხერხდა. დარწმუნდით, რომ იმავე Wi-Fi ქსელში ხართ.';
  static const unexpectedError = 'დაფიქსირდა შეცდომა. სცადეთ თავიდან.';
}
