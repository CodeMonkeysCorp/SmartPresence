import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../providers/session_provider.dart';

class WebSocketClient {
  WebSocket? _socket;
  final SessionProvider sessionProvider;

  WebSocketClient({required this.sessionProvider});

  Future<void> connect(String serverIp, {int port = 4040}) async {
    final uri = 'ws://$serverIp:$port';
    try {
      _socket = await WebSocket.connect(uri);
      sessionProvider.setConnected(true);
      debugPrint('WS cliente conectado: $uri');

      _socket!.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: (e) {
          debugPrint('WS cliente erro: $e');
          sessionProvider.setConnected(false);
        },
      );
    } catch (e) {
      debugPrint('Erro ao conectar WS cliente: $e');
      sessionProvider.setConnected(false);
      rethrow;
    }
  }

  void send(Map<String, dynamic> message) {
    if (_socket != null && _socket!.readyState == WebSocket.open) {
      _socket!.add(jsonEncode(message));
    } else {
      debugPrint('WS não pronto, não enviou: $message');
    }
  }

  void sendJoin(String name, String id) {
    send({'type': 'join', 'name': name, 'id': id});
  }

  void sendPresence(String id, {int round = 1}) {
    send({'type': 'presence', 'id': id, 'round': round});
  }

  void _onMessage(dynamic raw) {
    try {
      final Map<String, dynamic> msg = jsonDecode(raw as String);
      final type = msg['type'] as String?;
      if (type == 'update') {
        final list = (msg['students'] as List?);
        final students =
            list?.map((s) => Map<String, dynamic>.from(s as Map)).toList() ??
            [];
        sessionProvider.syncStudents(students);
      } else if (type == 'round') {
        sessionProvider.setRoundActive(msg['active'] == true);
        if (msg.containsKey('currentRound')) {
          sessionProvider.setCurrentRound(msg['currentRound'] as int);
        }
      }
    } catch (e) {
      debugPrint('Erro processando mensagem WS client: $e');
    }
  }

  void _onDisconnected() {
    debugPrint('WS cliente desconectado');
    sessionProvider.setConnected(false);
  }

  Future<void> disconnect() async {
    await _socket?.close();
    sessionProvider.setConnected(false);
  }
}
