import 'package:flutter/material.dart';
import 'package:logging/logging.dart'; // Importa o logging
// Importa as telas que serão navegadas
import 'aluno_join_screen.dart';
import 'configuracoes_screen.dart';
import 'professor_host_screen.dart';

// Instância do Logger para esta tela
final _log = Logger('RoleSelectionScreen');

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  // Função para navegar para a tela do Professor
  void _navigateToProfessorHost(BuildContext context) {
    _log.info('Navegando para ProfessorHostScreen');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfessorHostScreen()),
    );
  }

  // Função para navegar para a tela do Aluno
  void _navigateToAlunoJoin(BuildContext context) {
    _log.info('Navegando para AlunoJoinScreen');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AlunoJoinScreen()),
    );
  }

  // Função para navegar para a tela de Configurações
  void _navigateToConfiguracoes(BuildContext context) {
    _log.info('Navegando para ConfiguracoesScreen');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ConfiguracoesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SmartPresence',
        ), // Usa o estilo definido no main.dart
        // --- ATUALIZAÇÃO VISUAL ---
        // Removido 'backgroundColor' e 'elevation'
        // Agora usa o appBarTheme global (branco, com sombra)
        // -------------------------
        actions: [
          // Botão para o professor programar os horários
          IconButton(
            icon: Icon(
              Icons.settings_rounded,
              color: Theme.of(context).primaryColor,
              size: 28,
            ),
            tooltip: 'Programar Horários das Rodadas',
            onPressed: () => _navigateToConfiguracoes(context),
          ),
        ],
      ),
      // --- ATUALIZAÇÃO VISUAL ---
      // O Container com gradiente foi removido.
      // O body agora é o Center, e o fundo usará o
      // 'scaffoldBackgroundColor' (cinza claro) do main.dart.
      // -------------------------
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment:
                CrossAxisAlignment.stretch, // Faz os botões ocuparem a largura
            children: [
              // Botão "Sou Professor"
              _RoleButton(
                text: 'Sou Professor',
                icon: Icons.school_rounded,
                color: Colors.white, // Fundo branco
                textColor: Theme.of(
                  context,
                ).primaryColor, // Texto na cor do tema
                onPressed: () => _navigateToProfessorHost(context),
              ),
              const SizedBox(height: 24), // Espaçamento entre botões
              // Botão "Sou Aluno"
              _RoleButton(
                text: 'Sou Aluno',
                icon: Icons.person_rounded,
                // --- ATUALIZAÇÃO VISUAL ---
                // Cor do botão alterada para ser visível no fundo claro
                color: Theme.of(context).primaryColor,
                textColor: Colors.white, // Texto branco
                // -------------------------
                onPressed: () => _navigateToAlunoJoin(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Widget de botão reutilizável para manter o estilo consistente
class _RoleButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final Color textColor;
  final VoidCallback onPressed;

  const _RoleButton({
    required this.text,
    required this.icon,
    required this.color,
    required this.textColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 28), // Ícone um pouco maior
      label: Text(text),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color, // Cor de fundo
        foregroundColor: textColor, // Cor do texto e ícone
        minimumSize: const Size(double.infinity, 65), // Botão alto
        shape: RoundedRectangleBorder(
          // Bordas arredondadas
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          // Estilo do texto
          fontSize: 20,
          fontWeight: FontWeight.w600, // Semi-bold
        ),
        elevation: 5, // Sombra
        shadowColor: Colors.black.withOpacity(0.2), // Cor da sombra
      ),
    );
  }
}
