import 'dart:async';
import 'dart:convert';

import 'package:stomp_dart_client/stomp_dart_client.dart';

import 'api_config.dart';
import 'models.dart';

/// Live game feed.
///
/// The server broadcasts a whole [Snapshot] on every state change rather than
/// deltas, so a reconnecting client is correct the moment its first frame
/// arrives -- no replay needed.
class GameSocket {
  GameSocket({required this.gameId});

  final String gameId;

  final _snapshots = StreamController<Snapshot>.broadcast();
  final _notices = StreamController<Notice>.broadcast();
  final _connected = StreamController<bool>.broadcast();

  StompClient? _client;
  StompUnsubscribe? _unsubscribe;
  StompUnsubscribe? _unsubscribeNotices;
  int _lastSeq = -1;

  Stream<Snapshot> get snapshots => _snapshots.stream;

  /// What the host did that everyone should hear about. Events rather than
  /// state: nothing replays these to a device that was not listening.
  Stream<Notice> get notices => _notices.stream;

  Stream<bool> get connectionState => _connected.stream;

  bool get isConnected => _client?.connected ?? false;

  void connect() {
    _client?.deactivate();
    final client = StompClient(
      config: StompConfig(
        url: ApiConfig.wsUrl,
        reconnectDelay: const Duration(seconds: 2),
        heartbeatIncoming: const Duration(seconds: 10),
        heartbeatOutgoing: const Duration(seconds: 10),
        onConnect: _onConnect,
        onWebSocketError: (dynamic error) {
          _connected.add(false);
        },
        onDisconnect: (_) => _connected.add(false),
        onWebSocketDone: () => _connected.add(false),
      ),
    );
    _client = client;
    client.activate();
  }

  void _onConnect(StompFrame frame) {
    // A reconnect brings a new subscription; drop the handle to the old one
    // rather than leaving it to be overwritten and never called.
    _unsubscribe?.call();
    _unsubscribeNotices?.call();
    _unsubscribeNotices = _client?.subscribe(
      destination: '/topic/games/$gameId/notices',
      callback: (StompFrame message) {
        final body = message.body;
        if (body == null || body.isEmpty) return;
        try {
          _notices.add(
            Notice.fromJson(jsonDecode(body) as Map<String, dynamic>),
          );
        } catch (_) {
          // A notice is a courtesy; the scores on screen are the truth.
        }
      },
    );
    _unsubscribe = _client?.subscribe(
      destination: '/topic/games/$gameId',
      callback: (StompFrame message) {
        final body = message.body;
        if (body == null || body.isEmpty) return;
        try {
          final snap = Snapshot.fromJson(
            jsonDecode(body) as Map<String, dynamic>,
          );
          // Broadcasts can in principle arrive out of order; seq is monotonic
          // per game, so anything older than what we have is dropped.
          if (snap.seq >= _lastSeq) {
            _lastSeq = snap.seq;
            _snapshots.add(snap);
          }
        } catch (_) {
          // A malformed frame should not take the game down; the next
          // broadcast (or a REST refresh) will resync us.
        }
      },
    );
    // Announced only once the topic is really subscribed. Listeners treat this
    // as "you may have missed something, go and look", and a frame broadcast
    // between the socket opening and the subscription landing is exactly what
    // they would have missed.
    _connected.add(true);
  }

  /// Buzz over the socket -- the lowest-latency path we have.
  ///
  /// [reactionMs] is how long this device had been showing the open buzzer
  /// when the player pressed. The server ranks presses by it, so a phone on a
  /// slow connection is not beaten by a slower finger on a fast one.
  void buzz(String playerToken, {int? reactionMs}) {
    _client?.send(
      destination: '/app/games/$gameId/buzz',
      body: jsonEncode({
        'playerToken': playerToken,
        'reactionMs': ?reactionMs,
      }),
    );
  }

  /// Lets a REST response seed the stream so the UI does not wait for a frame.
  void push(Snapshot snapshot) {
    if (snapshot.seq >= _lastSeq) {
      _lastSeq = snapshot.seq;
      _snapshots.add(snapshot);
    }
  }

  void dispose() {
    _unsubscribe?.call();
    _unsubscribeNotices?.call();
    _client?.deactivate();
    _snapshots.close();
    _notices.close();
    _connected.close();
  }
}
