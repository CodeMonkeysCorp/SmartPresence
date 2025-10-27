import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

final _log = Logger('HistoricoScreen');

class HistoricoScreen extends StatelessWidget {
  // O mapa de presenças agora é { "matricula": { "Rodada 1": "Presente", ... } }
  final Map<String, Map<String, String>> presencas;
  // O mapa de nomes é { "matricula": "Nome do Aluno" }
  final Map<String, String> alunoNomes;

  const HistoricoScreen({
    super.key,
    required this.presencas,
    required this.alunoNomes,
  });

  @override
  Widget build(BuildContext context) {
    _log.info(
      "Construindo tela de histórico com ${presencas.length} registros.",
    );
    List<Widget> historicoWidgets = [];

    if (presencas.isEmpty) {
      historicoWidgets.add(
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 64.0,
              horizontal: 32.0,
            ),
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
        ),
      );
    } else {
      // Pega as matrículas (chaves) e as ordena
      // Você pode querer ordenar pelo nome do aluno depois, se preferir
      List<String> matriculasOrdenadas = presencas.keys.toList()..sort();

      for (var matricula in matriculasOrdenadas) {
        // Busca o nome do aluno no mapa _alunoNomes
        // Se não encontrar (improvável), usa a matrícula como fallback
        final nomeAluno = alunoNomes[matricula] ?? 'Aluno (Mat: $matricula)';
        final presencasRodadas = presencas[matricula]!;

        // Adiciona um cabeçalho para o aluno
        historicoWidgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            // Mostra Nome e Matrícula
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nomeAluno,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  'Matrícula: $matricula', // Mostra a matrícula abaixo do nome
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        );

        // Se não houver registros de rodadas para este aluno
        if (presencasRodadas.isEmpty) {
          historicoWidgets.add(
            const ListTile(
              dense: true,
              leading: Icon(Icons.info_outline, color: Colors.grey),
              title: Text('Nenhuma rodada registrada para este aluno.'),
            ),
          );
        } else {
          // Cria uma lista ordenada das rodadas
          List<String> rodadasOrdenadas = presencasRodadas.keys.toList()
            ..sort((a, b) {
              int numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              int numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              return numA.compareTo(numB);
            });

          // Itera sobre as rodadas ordenadas
          for (var nomeRodada in rodadasOrdenadas) {
            final status = presencasRodadas[nomeRodada] ?? 'Desconhecido';

            Color statusColor = Colors.grey;
            IconData statusIcon = Icons.help_outline;
            if (status == 'Presente') {
              statusColor = Colors.green.shade700;
              statusIcon = Icons.check_circle_outline_rounded;
            } else if (status == 'Ausente') {
              statusColor = Colors.red.shade700;
              statusIcon = Icons.highlight_off_rounded;
            } else if (status == 'Falhou PIN') {
              statusColor = Colors.orange.shade800;
              statusIcon = Icons.warning_amber_rounded;
            }

            historicoWidgets.add(
              Card(
                // Usa o tema do card definido no main.dart
                margin: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 4.0,
                ),
                child: ListTile(
                  leading: Icon(statusIcon, color: statusColor, size: 28),
                  title: Text(
                    nomeRodada,
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
                  dense: true,
                ),
              ),
            );
          }
        }
        // Adiciona um divisor visual entre os alunos
        historicoWidgets.add(
          const Divider(height: 24, thickness: 1, indent: 16, endIndent: 16),
        );
      }
      // Remove o último divisor
      if (historicoWidgets.isNotEmpty && historicoWidgets.last is Divider) {
        historicoWidgets.removeLast();
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de Presença')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16.0),
        children: historicoWidgets,
      ),
    );
  }
}
