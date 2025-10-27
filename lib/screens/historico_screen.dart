import 'package:flutter/material.dart';
import 'package:logging/logging.dart'; // 1. Importar o logging

// 2. Criar a instância do Logger
final _log = Logger('HistoricoScreen');

class HistoricoScreen extends StatelessWidget {
  // Recebe o mapa de presenças do ProfessorHostScreen
  // Estrutura: { 'Nome Aluno': { 'Rodada 1': 'Presente', 'Rodada 2': 'Ausente', ... }, ... }
  final Map<String, Map<String, String>> presencas;

  const HistoricoScreen({super.key, required this.presencas});

  @override
  Widget build(BuildContext context) {
    // 3. Adicionar log de informação
    _log.info(
      'Construindo tela de histórico com ${presencas.length} registros de alunos.',
    );

    // Cria a lista de Widgets a serem exibidos na ListView
    List<Widget> historicoWidgets = [];

    // Se o mapa de presenças estiver vazio
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
      // Ordena os nomes dos alunos alfabeticamente para exibição consistente
      List<String> nomesAlunosOrdenados = presencas.keys.toList()..sort();

      // Itera sobre cada aluno no mapa de presenças
      for (var nomeAluno in nomesAlunosOrdenados) {
        final presencasRodadas = presencas[nomeAluno]!;

        // Adiciona um cabeçalho para o aluno
        historicoWidgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: Text(
              nomeAluno,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        );

        // Se não houver registros de rodadas para este aluno (improvável, mas seguro)
        if (presencasRodadas.isEmpty) {
          historicoWidgets.add(
            const ListTile(
              leading: Icon(Icons.info_outline, color: Colors.grey),
              title: Text('Nenhuma rodada registrada para este aluno.'),
            ),
          );
        } else {
          // Cria uma lista ordenada das rodadas (ex: "Rodada 1", "Rodada 2", ...)
          List<String> rodadasOrdenadas = presencasRodadas.keys.toList()
            ..sort((a, b) {
              // Extrai o número da rodada para ordenação numérica
              int numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              int numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              return numA.compareTo(numB);
            });

          // Itera sobre as rodadas ordenadas para este aluno
          for (var nomeRodada in rodadasOrdenadas) {
            final status =
                presencasRodadas[nomeRodada] ?? 'Desconhecido'; // Status padrão

            // Define cor e ícone com base no status da presença
            Color statusColor = Colors.grey;
            IconData statusIcon = Icons.help_outline; // Ícone padrão (?)
            if (status == 'Presente') {
              statusColor = Colors.green.shade700; // Verde mais escuro
              statusIcon = Icons.check_circle_outline_rounded; // Check
            } else if (status == 'Ausente') {
              statusColor = Colors.red.shade700; // Vermelho mais escuro
              statusIcon = Icons.highlight_off_rounded; // X
            } else if (status == 'Falhou PIN') {
              statusColor = Colors.orange.shade800; // Laranja mais escuro
              statusIcon = Icons.warning_amber_rounded; // Alerta
            }

            // Adiciona um Card para cada registro de rodada
            historicoWidgets.add(
              Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 4.0,
                ), // Margens
                elevation: 1, // Sombra leve
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  leading: Icon(
                    statusIcon,
                    color: statusColor,
                    size: 28,
                  ), // Ícone de status
                  title: Text(
                    nomeRodada,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ), // Nome da rodada
                  trailing: Text(
                    // Status à direita
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  dense: true, // Torna o ListTile um pouco mais compacto
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
      // Remove o último divisor para não ficar sobrando espaço no final
      if (historicoWidgets.isNotEmpty && historicoWidgets.last is Divider) {
        historicoWidgets.removeLast();
      }
    }

    // Retorna o Scaffold com la AppBar e a ListView contendo os widgets criados
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de Presença')),
      body: ListView(
        // Usa ListView para permitir rolagem se houver muitos registros
        padding: const EdgeInsets.only(
          bottom: 16.0,
        ), // Padding na parte inferior
        children: historicoWidgets, // Adiciona a lista de widgets criada
      ),
    );
  }
}
