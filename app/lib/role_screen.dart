import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api_config.dart';
import 'core/models.dart';
import 'core/providers.dart';
import 'core/rest_client.dart';
import 'core/session.dart';
import 'core/session_store.dart';
import 'core/theme.dart';
import 'host/host_game_screen.dart';
import 'host/host_setup_screen.dart';
import 'main.dart' show routeObserver;
import 'practice/practice_screen.dart';
import 'team/buzzer_screen.dart';
import 'team/join_screen.dart';
import 'widgets/stage.dart';
import 'widgets/toast.dart';

/// One binary, two roles: the host drives the board, everyone else buzzes.
///
/// Lives in its own file because leaving a game has to come back here from any
/// navigator state, and the game screens cannot reach into main.dart for it.
class RoleScreen extends ConsumerStatefulWidget {
  const RoleScreen({super.key});

  /// Returns to the start screen and throws the rest of the stack away.
  ///
  /// Popping is not enough: after a reload the resumed game screen *is* the
  /// first route, so `popUntil(isFirst)` has nothing to pop and the button looks
  /// broken. Replacing the whole stack works from anywhere.
  static void replaceAll(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleScreen()),
      (route) => false,
    );
  }

  @override
  ConsumerState<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends ConsumerState<RoleScreen> with RouteAware {
  GameSession? _session;
  bool _resuming = false;

  @override
  void initState() {
    super.initState();
    _refreshSession();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
    _refreshSession();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _refreshSession();
  }

  void _refreshSession() {
    final s = SessionStore.read();
    if (mounted) {
      setState(() => _session = s);
    }
  }

  Future<void> _returnToGame(GameSession session) async {
    setState(() => _resuming = true);
    try {
      final snapshot = await ref
          .read(restClientProvider)
          .snapshot(session.gameId, hostToken: session.hostToken);
      if (!mounted) return;
      if (snapshot.state == GameState.finished) {
        SessionStore.clear();
        showToast(context, L.sessionGone);
        setState(() {
          _resuming = false;
          _session = null;
        });
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => session.isHost
              ? HostGameScreen(session: session)
              : BuzzerScreen(session: session),
        ),
      );
    } on ApiException catch (e) {
      if (e.isNotFound) {
        SessionStore.clear();
        if (mounted) {
          showToast(context, L.sessionGone);
          setState(() {
            _resuming = false;
            _session = null;
          });
        }
        return;
      }
      if (mounted) {
        showToast(context, describeError(e), error: true);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, describeError(e), error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _resuming = false);
      }
    }
  }

  /// A player's ✕ only drops this device's seat. The host's ✕ deletes the whole
  /// game for everyone, so it asks first.
  Future<void> _onCloseTapped(GameSession session) async {
    if (session.isHost) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(L.endGameConfirmTitle),
          content: const Text(L.endGameConfirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(L.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: JColors.wrong,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(L.endGameAction),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    await _dismissSession(session);
  }

  Future<void> _dismissSession(GameSession session) async {
    SessionStore.clear();
    setState(() => _session = null);
    try {
      if (session.isHost) {
        if (session.hostToken != null) {
          await ref
              .read(restClientProvider)
              .deleteGame(session.gameId, session.hostToken!);
        }
      } else {
        if (session.playerToken != null) {
          await ref
              .read(restClientProvider)
              .leavePlayer(session.gameId, session.playerToken!);
        }
      }
    } catch (_) {}
  }

  Widget _buildReturnCard(BuildContext context, GameSession session) {
    final isHost = session.isHost;
    final roleTitle = isHost ? L.host : (session.playerName ?? L.iAmPlayer);
    final subtitleParts = <String>[];
    if (!isHost && session.teamName != null && session.teamName!.isNotEmpty) {
      subtitleParts.add(session.teamName!);
    }
    subtitleParts.add('${L.joinCode}: ${session.joinCode}');
    final subtitle = subtitleParts.join(' · ');

    return Plate(
      lit: true,
      onTap: _resuming ? null : () => _returnToGame(session),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF56E39F),
                  Color(0xFF2E9E67),
                  Color(0xFF1B6B43),
                ],
                stops: [0, 0.4, 1],
              ),
              borderRadius: BorderRadius.circular(JRadius.tile),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x552E9E67),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: _resuming
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  )
                : const Icon(
                    Icons.play_arrow_rounded,
                    size: 30,
                    color: Colors.white,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  L.returnToGame,
                  style: TextStyle(
                    color: JColors.goldBright,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$roleTitle · $subtitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: JColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: L.leaveGame,
            icon: const Icon(Icons.close, size: 18, color: JColors.textFaint),
            onPressed: _resuming ? null : () => _onCloseTapped(session),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A marquee: brass rules above and below, the title lit gold
                  // between them. The app announces a game before it asks
                  // anything.
                  const BrassRule(),
                  const SizedBox(height: 18),
                  Text(
                    L.appTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: JColors.goldBright,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      shadows: const [
                        Shadow(
                          color: Color(0xAA000000),
                          offset: Offset(0, 3),
                          blurRadius: 8,
                        ),
                        Shadow(color: Color(0x66F2C14E), blurRadius: 34),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const BrassRule(),
                  const SizedBox(height: 14),
                  Text(
                    L.tagline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: JColors.textFaint,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (session != null) ...[
                    _buildReturnCard(context, session),
                    const SizedBox(height: 16),
                  ],
                  _RoleCard(
                    icon: Icons.co_present_outlined,
                    label: L.iAmHost,
                    hint: L.iAmHostHint,
                    primary: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HostSetupScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    icon: Icons.touch_app_outlined,
                    label: L.iAmPlayer,
                    hint: L.iAmPlayerHint,
                    primary: false,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const JoinScreen()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    icon: Icons.school_outlined,
                    label: L.practice,
                    hint: L.practiceHint,
                    primary: false,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PracticeScreen()),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    '${L.server}: ${ApiConfig.describe}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: JColors.textFaint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.label,
    required this.hint,
    required this.primary,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;

  /// The host card leads, so it carries the light.
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Plate(
      lit: primary,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: primary
                    ? const [
                        Color(0xFFFFF0C4),
                        JColors.goldBright,
                        Color(0xFFC99A2E),
                      ]
                    : const [
                        Color(0xFF3A56F5),
                        JColors.boardLit,
                        JColors.boardDeep,
                      ],
                stops: const [0, 0.12, 1],
              ),
              borderRadius: BorderRadius.circular(JRadius.tile),
            ),
            child: Icon(
              icon,
              size: 22,
              color: primary ? const Color(0xFF14120A) : Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: JColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hint,
                  style: const TextStyle(
                    color: JColors.textFaint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: JColors.brass),
        ],
      ),
    );
  }
}
