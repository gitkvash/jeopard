import 'dart:async';

import 'package:flutter/widgets.dart';

import 'game_socket.dart';
import 'models.dart';

/// The live game, as the widgets see it.
///
/// [GameSocket] is the transport; this is the state. It exists so a broadcast
/// does not have to rebuild a whole screen: a snapshot arrives roughly once per
/// tap during a game, and every one of them used to call `setState` on a tree
/// holding a 6x5 board, a scoreboard and a clue panel. Widgets instead watch
/// the one field they care about through [SnapshotBuilder].
class GameFeed extends ChangeNotifier {
  GameFeed({required this.gameId, this.onResync})
    : _socket = GameSocket(gameId: gameId) {
    _snapSub = _socket.snapshots.listen(_onSnapshot);
    _connSub = _socket.connectionState.listen((up) {
      if (_connected == up) return;
      _connected = up;
      notifyListeners();
      // The socket carries state changes, not state: whatever happened while
      // this device was away was broadcast to a socket that was not there to
      // hear it, and nothing will say it again until the host next does
      // something. On a phone that slept through a clue that means a buzzer
      // screen showing the wrong clue -- or a closed buzzer while the real one
      // is open. So every time the socket comes up, go and fetch the truth.
      if (up) onResync?.call();
    });
  }

  final String gameId;

  /// Called whenever the socket (re)connects, so the owner can pull a fresh
  /// snapshot over REST. Optional: a screen that does not care may omit it.
  final VoidCallback? onResync;

  final GameSocket _socket;

  StreamSubscription<Snapshot>? _snapSub;
  StreamSubscription<bool>? _connSub;

  Snapshot? _snapshot;
  bool _connected = false;

  Snapshot? get snapshot => _snapshot;

  bool get connected => _connected;

  bool get isSocketConnected => _socket.isConnected;

  void connect() => _socket.connect();

  /// Lets a REST response seed the state so the UI does not wait for a frame
  /// on the socket. Stale frames are dropped by seq inside [GameSocket].
  void push(Snapshot snapshot) => _socket.push(snapshot);

  void buzz(String playerToken) => _socket.buzz(playerToken);

  void _onSnapshot(Snapshot snapshot) {
    _snapshot = snapshot;
    notifyListeners();
  }

  @override
  void dispose() {
    _snapSub?.cancel();
    _connSub?.cancel();
    _socket.dispose();
    super.dispose();
  }
}

/// Rebuilds [builder] only when the value picked by [select] actually changes.
///
/// The board is the reason this exists: it is the most expensive thing on the
/// screen and it changes on maybe one broadcast in six, so selecting on
/// [Snapshot.board] keeps 30-odd tiles out of every other frame.
class SnapshotBuilder<T> extends StatefulWidget {
  const SnapshotBuilder({
    super.key,
    required this.feed,
    required this.select,
    required this.builder,
    this.equals,
  });

  final GameFeed feed;

  /// Null before the first snapshot lands, so implementations must cope.
  final T Function(Snapshot? snapshot) select;

  final Widget Function(BuildContext context, T value) builder;

  /// For values without a useful `==`, such as the board list.
  final bool Function(T previous, T next)? equals;

  @override
  State<SnapshotBuilder<T>> createState() => _SnapshotBuilderState<T>();
}

class _SnapshotBuilderState<T> extends State<SnapshotBuilder<T>> {
  late T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.select(widget.feed.snapshot);
    widget.feed.addListener(_onFeed);
  }

  @override
  void didUpdateWidget(SnapshotBuilder<T> old) {
    super.didUpdateWidget(old);
    if (old.feed != widget.feed) {
      old.feed.removeListener(_onFeed);
      widget.feed.addListener(_onFeed);
      _value = widget.select(widget.feed.snapshot);
    }
  }

  @override
  void dispose() {
    widget.feed.removeListener(_onFeed);
    super.dispose();
  }

  void _onFeed() {
    final next = widget.select(widget.feed.snapshot);
    final same = widget.equals?.call(_value, next) ?? (_value == next);
    if (same) return;
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

/// Value type for the handful of fields a header needs, so the header rebuilds
/// on a round change rather than on every broadcast.
@immutable
class GameHeader {
  const GameHeader({
    required this.title,
    required this.roundIdx,
    required this.finalRound,
    required this.tilesRemaining,
    required this.connected,
  });

  final String? title;
  final int roundIdx;
  final bool finalRound;
  final int tilesRemaining;
  final bool connected;

  @override
  bool operator ==(Object other) =>
      other is GameHeader &&
      other.title == title &&
      other.roundIdx == roundIdx &&
      other.finalRound == finalRound &&
      other.tilesRemaining == tilesRemaining &&
      other.connected == connected;

  @override
  int get hashCode =>
      Object.hash(title, roundIdx, finalRound, tilesRemaining, connected);
}

/// Cheap structural comparison for the board: the grid only has to be rebuilt
/// when a tile's status changes, not when a score does.
bool boardsEqual(List<BoardColumn> a, List<BoardColumn> b) {
  if (a.length != b.length) return false;
  for (var c = 0; c < a.length; c++) {
    final left = a[c];
    final right = b[c];
    if (left.topicId != right.topicId ||
        left.name != right.name ||
        left.tiles.length != right.tiles.length) {
      return false;
    }
    for (var t = 0; t < left.tiles.length; t++) {
      if (left.tiles[t].clueId != right.tiles[t].clueId ||
          left.tiles[t].status != right.tiles[t].status ||
          left.tiles[t].value != right.tiles[t].value) {
        return false;
      }
    }
  }
  return true;
}

/// Same idea for the scoreboard strip.
bool teamsEqual(List<TeamView> a, List<TeamView> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id ||
        a[i].name != b[i].name ||
        a[i].score != b[i].score ||
        a[i].wager != b[i].wager ||
        a[i].lockedOut != b[i].lockedOut ||
        a[i].players.length != b[i].players.length) {
      return false;
    }
  }
  return true;
}
