import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'live_match_state.dart';

abstract class LiveMatchTransport {
  void connect({
    required void Function(Map<String, dynamic>) onMessage,
    required void Function(bool) onConnectionChanged,
  });

  Future<void> send(Map<String, dynamic> message);
  Future<void> dispose();
}

class SupabaseLiveMatchTransport implements LiveMatchTransport {
  final SupabaseClient _client;
  final String _tournamentId;
  RealtimeChannel? _channel;
  bool _disposed = false;

  SupabaseLiveMatchTransport(this._client, this._tournamentId);

  @override
  void connect({
    required void Function(Map<String, dynamic>) onMessage,
    required void Function(bool) onConnectionChanged,
  }) {
    if (_disposed || _channel != null) return;
    final channel = _client.channel(
      'tiska-live:${Uri.encodeComponent(_tournamentId)}',
      opts: const RealtimeChannelConfig(ack: true),
    );
    _channel = channel;
    channel
        .onBroadcast(
          event: 'live-match',
          callback: (message) {
            if (_disposed) return;
            final payload = message['payload'];
            onMessage(
              payload is Map ? Map<String, dynamic>.from(payload) : message,
            );
          },
        )
        .subscribe((status, error) {
          if (!_disposed) {
            onConnectionChanged(status == RealtimeSubscribeStatus.subscribed);
          }
        });
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    final channel = _channel;
    if (_disposed || channel == null) return;
    final result = await channel
        .sendBroadcastMessage(event: 'live-match', payload: message)
        .timeout(const Duration(seconds: 3));
    if (result != ChannelResponse.ok) {
      throw StateError('Live display update was not acknowledged.');
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await _client.removeChannel(channel).timeout(const Duration(seconds: 3));
    }
  }
}

class LiveMatchChannel {
  final LiveMatchTransport transport;
  final String tournamentId;
  final void Function(String tatamiName, LiveMatchState? state) onState;
  final Duration heartbeatInterval;
  final Duration staleAfter;
  final DateTime Function() _now;
  final String _senderId;
  final Map<String, LiveMatchState> _published = {};
  final Map<String, DateTime> _receivedAt = {};
  final Map<String, String> _remoteSources = {};
  final Map<String, int> _sequences = {};
  Timer? _timer;
  int _sequence = 0;
  bool _connected = false;
  bool _started = false;
  bool _disposed = false;

  LiveMatchChannel({
    required this.transport,
    required this.tournamentId,
    required this.onState,
    this.heartbeatInterval = const Duration(seconds: 5),
    this.staleAfter = const Duration(seconds: 20),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _senderId =
           '${DateTime.now().microsecondsSinceEpoch}-'
           '${Random.secure().nextInt(1 << 30)}';

  void start() {
    if (_started || _disposed) return;
    _started = true;
    transport.connect(
      onMessage: _receive,
      onConnectionChanged: _connectionChanged,
    );
    _timer = Timer.periodic(heartbeatInterval, (_) {
      if (_disposed) return;
      for (final tatami in _receivedAt.keys.toList()) {
        if (_now().difference(_receivedAt[tatami]!) >= staleAfter) {
          _forgetRemote(tatami);
        }
      }
      if (_connected) _sendPublished();
    });
  }

  void publish(LiveMatchState state) {
    if (_disposed) return;
    _published[state.tatamiName] = state;
    _receivedAt.remove(state.tatamiName);
    _remoteSources.remove(state.tatamiName);
    onState(state.tatamiName, state);
    _sendState(state);
  }

  void clear(String tatamiName) {
    if (_disposed) return;
    final owned = _published.remove(tatamiName) != null;
    _receivedAt.remove(tatamiName);
    _remoteSources.remove(tatamiName);
    onState(tatamiName, null);
    if (owned) unawaited(_send('clear', tatamiName: tatamiName));
  }

  void _connectionChanged(bool connected) {
    if (_disposed) return;
    final changed = _connected != connected;
    _connected = connected;
    if (!connected) {
      for (final tatami in _receivedAt.keys.toList()) {
        _forgetRemote(tatami);
      }
    } else if (changed) {
      unawaited(_send('request'));
      _sendPublished();
    }
  }

  void _sendPublished() {
    for (final state in _published.values.toList()) {
      _sendState(state);
    }
  }

  void _sendState(LiveMatchState state) {
    unawaited(
      _send('state', tatamiName: state.tatamiName, state: state.toMap()),
    );
  }

  Future<void> _send(
    String kind, {
    String? tatamiName,
    Map<String, dynamic>? state,
  }) {
    if (!_connected || _disposed) return Future<void>.value();
    final message = <String, dynamic>{
      'version': 1,
      'tournamentId': tournamentId,
      'senderId': _senderId,
      'sequence': ++_sequence,
      'kind': kind,
      'tatamiName': ?tatamiName,
      'state': ?state,
    };
    return transport.send(message).catchError((Object error) {});
  }

  void _receive(Map<String, dynamic> message) {
    if (_disposed ||
        !_connected ||
        message['version'] != 1 ||
        message['tournamentId'] != tournamentId) {
      return;
    }
    final sender = message['senderId'];
    if (sender is! String || sender.isEmpty || sender == _senderId) return;
    if (message['kind'] == 'request') {
      _sendPublished();
      return;
    }
    final tatami = message['tatamiName'];
    final sequence = message['sequence'];
    if (tatami is! String ||
        tatami.trim().isEmpty ||
        sequence is! int ||
        sequence <= 0 ||
        _published.containsKey(tatami)) {
      return;
    }
    final key = '$sender:$tatami';
    if (sequence <= (_sequences[key] ?? 0)) return;
    if (message['kind'] == 'clear') {
      _sequences[key] = sequence;
      if (_remoteSources[tatami] == sender) _forgetRemote(tatami);
      return;
    }
    if (message['kind'] != 'state') return;
    try {
      final state = LiveMatchState.fromMap(
        Map<String, dynamic>.from(message['state'] as Map),
      );
      if (state.tatamiName != tatami) return;
      _sequences[key] = sequence;
      _receivedAt[tatami] = _now();
      _remoteSources[tatami] = sender;
      onState(tatami, state);
    } on FormatException {
      return;
    } on TypeError {
      return;
    }
  }

  void _forgetRemote(String tatamiName) {
    _receivedAt.remove(tatamiName);
    _remoteSources.remove(tatamiName);
    onState(tatamiName, null);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    final clears = [
      for (final tatami in _published.keys.toList())
        _send('clear', tatamiName: tatami),
    ];
    _disposed = true;
    _timer?.cancel();
    _published.clear();
    _receivedAt.clear();
    _remoteSources.clear();
    _sequences.clear();
    await Future.wait(clears)
        .timeout(const Duration(seconds: 3), onTimeout: () => []);
    try {
      await transport.dispose();
    } catch (_) {
      return;
    }
  }
}
