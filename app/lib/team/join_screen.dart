import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../core/rest_client.dart';
import '../core/session.dart';
import '../core/session_store.dart';
import '../core/theme.dart';
import 'buzzer_screen.dart';

/// Joining is two steps, because a team can hold several people:
///   1. enter the game code and your own name
///   2. sit with an existing team, or start a new one
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _newTeam = TextEditingController();

  /// Non-null once the code is accepted; holds the teams already in the game.
  LobbyView? _lobby;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _newTeam.dispose();
    super.dispose();
  }

  String get _codeText => _code.text.trim().toUpperCase();
  String get _nameText => _name.text.trim();

  Future<void> _lookUpGame() async {
    if (_codeText.length != 6 || _nameText.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final lobby = await ref.read(restClientProvider).lobby(_codeText);
      if (!mounted) return;
      setState(() => _lobby = lobby);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join({String? teamId, String? newTeamName}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final joined = await ref
          .read(restClientProvider)
          .joinPlayer(
            joinCode: _codeText,
            name: _nameText,
            teamId: teamId,
            newTeamName: newTeamName,
          );
      if (!mounted) return;
      // Written before the buzzer screen opens: a player who reloads mid-game
      // comes back onto the same team with the same token, rather than joining
      // twice under the same name.
      final session = GameSession.fromJoined(joined, joinCode: _codeText);
      SessionStore.write(session);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => BuzzerScreen(session: session)),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
        // The team list may have moved on since we fetched it.
        _refreshLobby();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeError(e);
        });
      }
    }
  }

  Future<void> _refreshLobby() async {
    try {
      final lobby = await ref.read(restClientProvider).lobby(_codeText);
      if (mounted) setState(() => _lobby = lobby);
    } catch (_) {
      // Keep whatever list we already have.
    }
  }

  @override
  Widget build(BuildContext context) {
    final lobby = _lobby;
    return Scaffold(
      appBar: AppBar(
        title: Text(lobby == null ? L.joinGame : L.chooseTeam),
        leading: lobby == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _lobby = null;
                  _error = null;
                }),
              ),
      ),
      body: SafeArea(child: lobby == null ? _identityStep() : _teamStep(lobby)),
    );
  }

  // ---------------- step 1: code + your own name ----------------

  Widget _identityStep() {
    final ready = _codeText.length == 6 && _nameText.isNotEmpty;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                L.enterCode,
                textAlign: TextAlign.center,
                style: const TextStyle(color: JColors.textFaint, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                textAlign: TextAlign.center,
                autofocus: true,
                inputFormatters: [
                  UpperCaseFormatter(),
                  FilteringTextInputFormatter.allow(RegExp('[A-Z0-9]')),
                ],
                style: const TextStyle(
                  fontSize: 34,
                  letterSpacing: 10,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '------',
                  hintStyle: TextStyle(
                    color: JColors.line,
                    fontSize: 34,
                    letterSpacing: 10,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _name,
                textInputAction: TextInputAction.go,
                decoration: const InputDecoration(labelText: L.yourName),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _lookUpGame(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _ErrorText(_error!),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: (_busy || !ready) ? null : _lookUpGame,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: JColors.textFaint,
                        ),
                      )
                    : const Icon(Icons.arrow_forward, size: 20),
                label: const Text(L.next2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- step 2: pick or create a team ----------------

  Widget _teamStep(LobbyView lobby) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Row(
          children: [
            const Icon(
              Icons.person_outline,
              size: 16,
              color: JColors.textFaint,
            ),
            const SizedBox(width: 8),
            Text(
              _nameText,
              style: const TextStyle(
                color: JColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              lobby.joinCode,
              style: const TextStyle(
                color: JColors.textFaint,
                letterSpacing: 2,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (lobby.teams.isNotEmpty) ...[
          Text(L.chooseTeam, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final t in lobby.teams)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TeamOptionCard(
                option: t,
                onTap: _busy ? null : () => _join(teamId: t.id),
              ),
            ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  L.createTeam.toUpperCase(),
                  style: const TextStyle(
                    color: JColors.textFaint,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 18),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              L.createTeam,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        TextField(
          controller: _newTeam,
          textInputAction: TextInputAction.go,
          decoration: const InputDecoration(labelText: L.newTeamName),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _newTeam.text.trim().isEmpty
              ? null
              : _join(newTeamName: _newTeam.text.trim()),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _ErrorText(_error!),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (_busy || _newTeam.text.trim().isEmpty)
                ? null
                : () => _join(newTeamName: _newTeam.text.trim()),
            icon: const Icon(Icons.group_add_outlined, size: 20),
            label: const Text(L.createTeam),
          ),
        ),
      ],
    );
  }
}

/// Join codes are read out loud and typed in a hurry, so the field fixes the
/// case rather than rejecting it.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

class _TeamOptionCard extends StatelessWidget {
  const _TeamOptionCard({required this.option, this.onTap});

  final TeamOption option;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: JColors.surface,
      borderRadius: BorderRadius.circular(JRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(JRadius.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(JRadius.card),
            border: Border.all(color: JColors.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      option.memberNames.isEmpty
                          ? L.noTeamsYet
                          : '${L.members}: ${option.memberNames.join(', ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: JColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                L.joinThisTeam,
                style: const TextStyle(
                  color: JColors.goldBright,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Icon(Icons.chevron_right, color: JColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JColors.wrong.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(JRadius.control),
        border: Border.all(color: JColors.wrong.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 17, color: JColors.wrong),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
