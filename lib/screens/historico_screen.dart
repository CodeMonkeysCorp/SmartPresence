// lib/screens/historico_screen.dart

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import '../models/app_models.dart'; // Importa a definição de Rodada

final _log = Logger('HistoricoScreen');

class HistoricoScreen extends StatefulWidget {
  // O mapa de presenças agora é { "matricula": { "Rodada 1": "Presente", ... } }
  final Map<String, Map<String, String>> presencas;
  // O mapa de nomes é { "matricula": "Nome do Aluno" }
  final Map<String, String> alunoNomes;
  // Lista das rodadas configuradas (para garantir que todas apareçam)
  final List<Rodada> rodadas;

  const HistoricoScreen({
    super.key,
    required this.presencas,
    required this.alunoNomes,
    required this.rodadas, // Recebe a lista de rodadas
  });

  @override
  State<HistoricoScreen> createState() => _HistoricoScreenState();
}

// Classe de Estado para a tela de histórico
class _HistoricoScreenState extends State<HistoricoScreen> {
  // Estado para controlar a ordenação da lista
  bool _sortByMatricula = true; // Começa ordenando por matrícula

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
          // Botão para alternar a ordenação (só aparece se houver dados)
          if (!isEmpty)
            IconButton(
              icon: Icon(
                _sortByMatricula ? Icons.sort_by_alpha : Icons.pin_outlined,
              ), // Alterna ícone
              tooltip: _sortByMatricula
                  ? 'Ordenar por Nome'
                  : 'Ordenar por Matrícula',
              onPressed: () {
                setState(() {
                  _sortByMatricula =
                      !_sortByMatricula; // Alterna o estado de ordenação
                });
              },
            ),
        ],
      ),
      body: isEmpty
          ? _buildEmptyView() // Mostra mensagem se não houver dados
          : _buildHistoricoList(), // Mostra a lista de histórico
    );
  }

  /// Widget para exibir quando não há histórico.
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

  /// Widget que constrói a lista de histórico, ordenada conforme _sortByMatricula.
  Widget _buildHistoricoList() {
    // Pega as matrículas (chaves do mapa de presenças ou nomes)
    List<String> matriculas = widget.presencas.keys.toList();
    // Se não houver presenças, tenta usar as chaves do mapa de nomes
    if (matriculas.isEmpty && widget.alunoNomes.isNotEmpty) {
      matriculas = widget.alunoNomes.keys.toList();
    }

    // Ordena a lista de matrículas com base no estado _sortByMatricula
    matriculas.sort((a, b) {
      if (_sortByMatricula) {
        // Ordenação numérica/string da matrícula
        return a.compareTo(b);
      } else {
        // Ordenação alfabética pelo nome do aluno
        final nomeA =
            widget.alunoNomes[a] ??
            a; // Usa matrícula como fallback se nome não existe
        final nomeB = widget.alunoNomes[b] ?? b;
        return nomeA.compareTo(nomeB);
      }
    });

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16), // Padding ajustado
      itemCount: matriculas.length,
      itemBuilder: (context, index) {
        final matricula = matriculas[index];
        // Busca o nome do aluno no mapa, usa matrícula como fallback
        final nomeAluno =
            widget.alunoNomes[matricula] ?? 'Aluno (Mat: $matricula)';
        // Pega os registros de presença para este aluno (pode ser vazio)
        final presencasAluno = widget.presencas[matricula] ?? {};

        // Cria um Card expansível para cada aluno
        return Card(
          // Estilo consistente com os outros cards
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExpansionTile(
            // Cabeçalho com Nome e Matrícula
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
            // Conteúdo expansível com os detalhes das rodadas
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  16.0,
                  0,
                  16.0,
                  16.0,
                ), // Padding interno
                child: _buildRodadasDetail(
                  presencasAluno,
                ), // Chama helper para construir detalhes
              ),
            ],
          ),
        );
      },
    );
  }

  /// Constrói a lista detalhada de status para cada rodada configurada para um aluno.
  Widget _buildRodadasDetail(Map<String, String> presencasAluno) {
    // Usa a lista de rodadas configuradas (widget.rodadas) para garantir
    // que todas as rodadas apareçam na ordem correta, mesmo que o aluno
    // não tenha registro para alguma delas.
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
        // Pega o status do aluno para esta rodada, ou 'Ausente' se não houver registro
        final status = presencasAluno[rodada.nome] ?? 'Ausente';
        Color statusColor = Colors.grey;
        IconData statusIcon = Icons.help_outline;

        // Define a cor e o ícone com base no status
        if (status == 'Presente') {
          statusColor = Colors.green.shade700;
          statusIcon = Icons.check_circle_rounded;
        } else if (status == 'Ausente') {
          statusColor = Colors.red.shade700;
          statusIcon = Icons.highlight_off_rounded;
        } else if (status == 'Falhou PIN' || status == 'Falhou PIN (Rede)') {
          // Trata ambos os casos de falha
          statusColor = Colors.orange.shade800;
          statusIcon = Icons.warning_amber_rounded;
        }

        // Retorna um ListTile compacto para cada rodada
        return ListTile(
          dense: true, // Torna o ListTile mais compacto
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
          ), // Ajusta padding interno
        );
      }).toList(),
    );
  }
}
