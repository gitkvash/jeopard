import 'package:flutter/material.dart';

import 'core/api_config.dart';
import 'core/theme.dart';
import 'host/host_setup_screen.dart';
import 'team/join_screen.dart';
import 'widgets/stage.dart';

/// One binary, two roles: the host drives the board, everyone else buzzes.
///
/// Lives in its own file because leaving a game has to come back here from any
/// navigator state, and the game screens cannot reach into main.dart for it.
class RoleScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                  const SizedBox(height: 36),
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
