import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../network/websocket_server.dart';

class ProfessorPage extends StatefulWidget {
  const ProfessorPage({super.key});
  @override
  State<ProfessorPage> createState() => _ProfessorPageState();
}

class _ProfessorPageState extends State<ProfessorPage> {
  WebSocketServer? _server;
  @override
  void dispose() {
    _server?.stopServer();
    super.dispose();
  }

  Future<void> _startServer(SessionProvider session) async {
    _server = WebSocketServer(sessionProvider: session);
    await _server!.startServer();
  }

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('SmartPresence — Professor')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              session.roundActive
                  ? 'Rodada ${session.currentRound} em andamento'
                  : 'Rodada atual: ${session.currentRound}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: session.roundActive ? null : session.startNewRound,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar nova rodada'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: session.roundActive ? session.endRound : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Encerrar rodada'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                if (session.isConnected) {
                  await _server?.stopServer();
                } else {
                  await _startServer(session);
                }
                setState(() {});
              },
              icon: Icon(session.isConnected ? Icons.wifi_off : Icons.wifi),
              label: Text(
                session.isConnected
                    ? 'Parar servidor'
                    : 'Iniciar servidor (porta 4040)',
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: session.students.length,
                itemBuilder: (context, i) {
                  final s = session.students[i];
                  final model = session.studentModelById(s.id);
                  final percent = model == null
                      ? '-'
                      : '${(model.presenceRate * 100).toStringAsFixed(0)}%';
                  return ListTile(
                    title: Text(s.name),
                    subtitle: Text(
                      'Presente: ${s.isPresent ? 'Sim' : 'Não'} • Presença histórica: $percent',
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
