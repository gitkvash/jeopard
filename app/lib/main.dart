import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models.dart';
import 'core/providers.dart';
import 'core/rest_client.dart';
import 'core/session.dart';
import 'core/session_store.dart';
import 'core/theme.dart';
import 'host/host_game_screen.dart';
import 'role_screen.dart';
import 'team/buzzer_screen.dart';
import 'team/join_screen.dart';
import 'widgets/stage.dart';

void main() {
  runApp(const ProviderScope(child: JeopardApp()));
}

class JeopardApp extends StatelessWidget {
  const JeopardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: L.appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Every screen is drawn on the stage: pooled light above, vignette at the
      // edges. Doing it here rather than per-screen means nothing can forget.
      builder: (context, child) =>
          Stage(child: child ?? const SizedBox.shrink()),
      home: const _Entry(),
    );
  }
}

/// First decision of the run: are we already in a game?
///
/// [SessionStore.read] is synchronous, so this costs nothing and happens before
/// the first frame -- a reloaded browser tab never flashes the role picker on
/// its way back into the game.
class _Entry extends StatefulWidget {
  const _Entry();

  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> {
  GameSession? _saved;

  @override
  void initState() {
    super.initState();
    _saved = SessionStore.read();
    
    if (_saved == null) {
      final code = Uri.base.queryParameters['code'];
      if (code != null && code.length == 6) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const JoinScreen()),
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    if (saved == null) return const RoleScreen();
    return ResumeScreen(
      session: saved,
      onGiveUp: () => setState(() => _saved = null),
    );
  }
}

/// Rejoins a game that outlived the page it was being played on.
///
/// The server is the only thing that knows the state of a game, so resuming is
/// just: fetch the snapshot, and if the game is still there, walk back into the
/// console this device was using. If it is gone, drop the session rather than
/// leaving a dead resume loop behind.
class ResumeScreen extends ConsumerStatefulWidget {
  const ResumeScreen({
    super.key,
    required this.session,
    required this.onGiveUp,
  });

  final GameSession session;
  final VoidCallback onGiveUp;

  @override
  ConsumerState<ResumeScreen> createState() => _ResumeScreenState();
}

class _ResumeScreenState extends ConsumerState<ResumeScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resume());
  }

  Future<void> _resume() async {
    final session = widget.session;
    try {
      final snapshot = await ref
          .read(restClientProvider)
          .snapshot(session.gameId);
      if (!mounted) return;

      // A finished game is worth remembering only long enough to show the
      // result; there is nothing left to resume into.
      if (snapshot.state == GameState.finished) {
        SessionStore.clear();
        widget.onGiveUp();
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => session.isHost
              ? HostGameScreen(session: session)
              : BuzzerScreen(session: session),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // A failed resume leaves the player staring at a retry button with no way
      // to tell a dropped backend from a bug, so say what happened where it can
      // be read: the browser console.
      debugPrint('resume failed for game ${session.gameId}: $e');
      // Could be a dropped backend rather than a dead game, so offer a retry
      // before throwing the session away.
      setState(() => _error = e is Exception ? describeError(e) : L.sessionGone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: error == null
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      SizedBox(height: 22),
                      Text(
                        L.restoring,
                        style: TextStyle(color: JColors.textMuted),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off,
                        size: 40,
                        color: JColors.textFaint,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '${L.joinCode}: ${widget.session.joinCode}',
                        style: const TextStyle(
                          color: JColors.textMuted,
                          letterSpacing: 3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        error,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: JColors.textFaint,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () {
                          setState(() => _error = null);
                          _resume();
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text(L.retry),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          SessionStore.clear();
                          widget.onGiveUp();
                        },
                        child: const Text(L.leaveGame),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
