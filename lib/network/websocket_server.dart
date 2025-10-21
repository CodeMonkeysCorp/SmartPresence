import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../providers/session_provider.dart';

class WebSocketServer {
  HttpServer? _server;
  final SessionProvider sessionProvider;
  final List<WebSocket> _clients = [];

  WebSocketServer({required this.sessionProvider});

  Future<void> startServer({int port = 4040}) async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      sessionProvider.setConnected(true);
      debugPrint('WS servidor iniciado na porta $port');

      _server!.listen((HttpRequest req) async {
        if (WebSocketTransformer.isUpgradeRequest(req)) {
          final socket = await WebSocketTransformer.upgrade(req);
          _clients.add(socket);
          debugPrint('Aluno conectado. Total clientes: ${_clients.length}');
          socket.listen(
            (data) => _handleMessage(socket, data),
            onDone: () {
              _clients.remove(socket);
              debugPrint('Aluno desconectado. Total: ${_clients.length}');
            },
            onError: (e) => debugPrint('Erro socket: $e'),
          );
        } else {
          req.response
            ..statusCode = HttpStatus.forbidden
            ..write('Acesso negado')
            ..close();
        }
      });
    } catch (e) {
      debugPrint('Erro ao iniciar servidor WS: $e');
      sessionProvider.setConnected(false);
      rethrow;
    }
  }

  void broadcast(Map<String, dynamic> message) {
    final jsonMsg = jsonEncode(message);
    for (final client in List<WebSocket>.from(_clients)) {
      try {
        client.add(jsonMsg);
      } catch (e) {
        debugPrint('Erro ao broadcast para cliente: $e');
      }
    }
  }

  void _handleMessage(WebSocket socket, dynamic raw) {
    try {
      final Map<String, dynamic> msg = jsonDecode(raw as String);
      final type = msg['type'] as String?;
      if (type == 'join') {
        final name = msg['name'] as String? ?? 'Aluno';
        final id = msg['id'] as String? ?? socket.hashCode.toString();
        sessionProvider.addStudent(name, id);
        _broadcastStudents();
      } else if (type == 'presence') {
        final id = msg['id'] as String?;
        final round = (msg['round'] as int?) ?? sessionProvider.currentRound;
        if (id != null) {
          sessionProvider.markPresent(id);
          sessionProvider.addAttendanceToStudent(
            id,
            round,
            'P',
            validationMethod: 'WS',
          );
          _broadcastStudents();
        }
      }
    } catch (e) {
      debugPrint('Erro processando mensagem no servidor WS: $e');
    }
  }

  void _broadcastStudents() {
    broadcast({
      'type': 'update',
      'students': sessionProvider.students
          .map((s) => {'name': s.name, 'id': s.id, 'present': s.isPresent})
          .toList(),
    });
  }

  Future<void> stopServer() async {
    for (final c in _clients) {
      try {
        await c.close();
      } catch (_) {}
    }
    _clients.clear();
    await _server?.close();
    sessionProvider.setConnected(false);
    debugPrint('WS servidor parado');
  }
}
