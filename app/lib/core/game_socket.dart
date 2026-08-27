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
  final _connected = StreamController<bool>.broadcast();

  StompClient? _client;
  StompUnsubscribe? _unsubscribe;
  int _lastSeq = -1;

  Stream<Snapshot> get snapshots => _snapshots.stream;

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
    _connected.add(true);
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
  }

  /// Buzz over the socket -- the lowest-latency path we have.
  void buzz(String playerToken) {
    _client?.send(
      destination: '/app/games/$gameId/buzz',
      body: jsonEncode({'playerToken': playerToken}),
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
    _client?.deactivate();
    _snapshots.close();
    _connected.close();
  }
}
