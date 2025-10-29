import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'aluno_join_screen.dart';
import 'configuracoes_screen.dart';
import 'professor_host_screen.dart';

final _log = Logger('RoleSelectionScreen');

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  void _navigateToProfessorHost(BuildContext context) {
    _log.info('Navegando para ProfessorHostScreen');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfessorHostScreen()),
    );
  }

  void _navigateToAlunoJoin(BuildContext context) {
    _log.info('Navegando para AlunoJoinScreen');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AlunoJoinScreen()),
    );
  }

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
        title: const Text('SmartPresence'),
        actions: [
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset(
                'assets/logo/logo.png',
                height: 300,
                semanticLabel: 'Logo do SmartPresence',
              ),
              const SizedBox(height: 48),
              _RoleButton(
                text: 'Sou Professor',
                icon: Icons.school_rounded,
                color: Theme.of(context).primaryColor,
                textColor: Colors.white,
                onPressed: () => _navigateToProfessorHost(context),
              ),
              const SizedBox(height: 24),

              _RoleButton(
                text: 'Sou Aluno',
                icon: Icons.person_rounded,
                color: Colors.white,
                textColor: Theme.of(context).primaryColor,
                borderColor: Theme.of(context).primaryColor,
                onPressed: () => _navigateToAlunoJoin(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final Color textColor;
  final VoidCallback onPressed;
  final Color? borderColor;

  const _RoleButton({
    required this.text,
    required this.icon,
    required this.color,
    required this.textColor,
    required this.onPressed,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 28),
      label: Text(text),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor,
        minimumSize: const Size(double.infinity, 65),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: borderColor != null
              ? BorderSide(color: borderColor!, width: 2)
              : BorderSide.none,
        ),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        elevation: 5,
        shadowColor: Colors.black.withOpacity(0.2),
      ),
    );
  }
}
