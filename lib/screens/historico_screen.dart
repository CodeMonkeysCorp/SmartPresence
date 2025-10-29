import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import '../models/app_models.dart';

final _log = Logger('HistoricoScreen');

class HistoricoScreen extends StatefulWidget {
  final Map<String, Map<String, String>>
  presencas; // Matrícula -> Rodada -> Status
  final Map<String, String> alunoNomes; // Matrícula -> Nome
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
  // ... (o restante da sua classe HistoricoScreen) ...

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de Presença')),
      body: widget.presencas.isEmpty && widget.alunoNomes.isEmpty
          ? const Center(
              child: Text(
                'Nenhum registro de presença ainda.',
                style: TextStyle(fontSize: 18, color: Colors.black54),
              ),
            )
          : _buildHistoricoList(),
    );
  }

  Widget _buildHistoricoList() {
    // Ordena as matrículas para exibição consistente
    final sortedMatriculas = widget.presencas.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedMatriculas.length,
      itemBuilder: (context, index) {
        final matricula = sortedMatriculas[index];
        final nomeAluno = widget.alunoNomes[matricula] ?? 'Nome Desconhecido';
        final presencasAluno = widget.presencas[matricula] ?? {};

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ExpansionTile(
            title: Text(
              '$nomeAluno ($matricula)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Exibe o status para cada rodada configurada
                    // Usamos widget.rodadas para garantir a ordem e todas as rodadas
                    ...widget.rodadas.map((rodada) {
                      final status = presencasAluno[rodada.nome] ?? 'Ausente';
                      Color statusColor = Colors.grey;
                      if (status == 'Presente') {
                        statusColor = Colors.green;
                      } else if (status == 'Ausente') {
                        statusColor = Colors.red;
                      } else if (status == 'Falhou PIN') {
                        statusColor = Colors.orange;
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Text(
                              '${rodada.nome}: ',
                              style: const TextStyle(fontSize: 16),
                            ),
                            Text(
                              status,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
