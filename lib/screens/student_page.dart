import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../network/websocket_client.dart';
import '../widgets/attendance_status.dart';

class StudentPage extends StatefulWidget {
  final String studentId;
  final String studentName;
  const StudentPage({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentPage> createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentPage> {
  WebSocketClient? _client;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _client = WebSocketClient(
      sessionProvider: Provider.of<SessionProvider>(context, listen: false),
    );
  }

  Future<void> _connectDialog() async {
    final ipController = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('IP do professor'),
        content: TextField(
          controller: ipController,
          decoration: const InputDecoration(hintText: 'ex: 192.168.0.100'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ipController.text.trim()),
            child: const Text('Conectar'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await _client!.connect(result);
        _client!.sendJoin(widget.studentName, widget.studentId);
        setState(() => _connected = true);
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Erro ao conectar')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context);
    final round = session.currentRound;
    final active = session.roundActive;
    final info = session.students.firstWhere(
      (s) => s.id == widget.studentId,
      orElse: () => StudentInfo(name: widget.studentName, id: widget.studentId),
    );
    final model = session.studentModelById(widget.studentId);
    final status = info.isPresent ? 'P' : (model?.statusForRound(round) ?? '-');

    return Scaffold(
      appBar: AppBar(title: Text('Aluno: ${widget.studentName}')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                active
                    ? 'Rodada $round ativa!'
                    : 'Aguardando próxima chamada...',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: !_connected ? _connectDialog : null,
                icon: const Icon(Icons.wifi),
                label: Text(_connected ? 'Conectado' : 'Conectar ao professor'),
              ),
              const SizedBox(height: 12),
              if (active)
                ElevatedButton.icon(
                  onPressed: info.isPresent
                      ? null
                      : () {
                          _client?.sendPresence(widget.studentId, round: round);
                        },
                  icon: const Icon(Icons.check),
                  label: const Text('Confirmar Presença'),
                ),
              const SizedBox(height: 18),
              AttendanceStatus(status: status, round: round),
              const SizedBox(height: 8),
              Text(
                'Status atual: $status',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
