import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import '../models/app_models.dart';

final _log = Logger('HistoricoScreen');

class HistoricoScreen extends StatefulWidget {
  final Map<String, Map<String, String>> presencas;
  final Map<String, String> alunoNomes;
  final List<Rodada> rodadas;

  const HistoricoScreen({
    super.key,
    required this.presencas,
    required this.alunoNomes,
    required this.rodadas,
  });

  @override
  State<HistoricoScreen> createState() => _HistoricoScreenState();
}

class _HistoricoScreenState extends State<HistoricoScreen> {
  bool _sortByMatricula = true;

  @override
  Widget build(BuildContext context) {
    _log.info(
      "Construindo tela de histórico com ${widget.presencas.length} registros.",
    );

    // Verifica se há dados para exibir
    bool isEmpty = widget.presencas.isEmpty && widget.alunoNomes.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Presença'),
        actions: [
          if (!isEmpty)
            IconButton(
              icon: Icon(
                _sortByMatricula ? Icons.sort_by_alpha : Icons.pin_outlined,
              ),
              tooltip: _sortByMatricula
                  ? 'Ordenar por Nome'
                  : 'Ordenar por Matrícula',
              onPressed: () {
                setState(() {
                  _sortByMatricula = !_sortByMatricula;
                });
              },
            ),
        ],
      ),
      body: isEmpty ? _buildEmptyView() : _buildHistoricoList(),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64.0, horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history_toggle_off_rounded,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'Nenhum registro de presença encontrado ainda.',
              style: TextStyle(fontSize: 18, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoricoList() {
    List<String> matriculas = widget.presencas.keys.toList();
    if (matriculas.isEmpty && widget.alunoNomes.isNotEmpty) {
      matriculas = widget.alunoNomes.keys.toList();
    }

    matriculas.sort((a, b) {
      if (_sortByMatricula) {
        return a.compareTo(b);
      } else {
        final nomeA = widget.alunoNomes[a] ?? a;
        final nomeB = widget.alunoNomes[b] ?? b;
        return nomeA.compareTo(nomeB);
      }
    });

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16), // Padding ajustado
      itemCount: matriculas.length,
      itemBuilder: (context, index) {
        final matricula = matriculas[index];
        final nomeAluno =
            widget.alunoNomes[matricula] ?? 'Aluno (Mat: $matricula)';
        final presencasAluno = widget.presencas[matricula] ?? {};

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExpansionTile(
            leading: Icon(
              Icons.person_rounded,
              color: Theme.of(context).primaryColor,
              size: 30,
            ),
            title: Text(
              nomeAluno,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            subtitle: Text('Matrícula: $matricula'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                child: _buildRodadasDetail(presencasAluno),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRodadasDetail(Map<String, String> presencasAluno) {
    if (widget.rodadas.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          'Nenhuma rodada configurada no sistema.',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    }

    return Column(
      children: widget.rodadas.map((rodada) {
        final status = presencasAluno[rodada.nome] ?? 'Ausente';
        Color statusColor = Colors.grey;
        IconData statusIcon = Icons.help_outline;

        if (status == 'Presente') {
          statusColor = Colors.green.shade700;
          statusIcon = Icons.check_circle_rounded;
        } else if (status == 'Ausente') {
          statusColor = Colors.red.shade700;
          statusIcon = Icons.highlight_off_rounded;
        } else if (status == 'Falhou PIN' || status == 'Falhou PIN (Rede)') {
          statusColor = Colors.orange.shade800;
          statusIcon = Icons.warning_amber_rounded;
        }

        return ListTile(
          dense: true,
          leading: Icon(statusIcon, color: statusColor, size: 22),
          title: Text(
            rodada.nome,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          trailing: Text(
            status,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 0,
            vertical: 0,
          ),
        );
      }).toList(),
    );
  }
}
