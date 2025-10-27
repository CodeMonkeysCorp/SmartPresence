// lib/screens/configuracoes_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConfiguracoesScreen extends StatefulWidget {
  const ConfiguracoesScreen({super.key});

  // Chaves públicas para salvar/carregar os horários
  static const String R1_KEY = 'rodada1_time';
  static const String R2_KEY = 'rodada2_time';
  static const String R3_KEY = 'rodada3_time';
  static const String R4_KEY = 'rodada4_time';

  @override
  State<ConfiguracoesScreen> createState() => _ConfiguracoesScreenState();
}

class _ConfiguracoesScreenState extends State<ConfiguracoesScreen> {
  // Horários padrão ou carregados
  TimeOfDay _r1 = const TimeOfDay(hour: 19, minute: 10);
  TimeOfDay _r2 = const TimeOfDay(hour: 20, minute: 0);
  TimeOfDay _r3 = const TimeOfDay(hour: 20, minute: 50);
  TimeOfDay _r4 = const TimeOfDay(hour: 21, minute: 40);

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHorarios();
  }

  // Carrega os horários salvos do SharedPreferences
  Future<void> _loadHorarios() async {
    final prefs = await SharedPreferences.getInstance();
    // Usa setState para atualizar a UI após carregar
    setState(() {
      // Usa as chaves da classe pública e o helper _timeFromPrefs
      // Se não encontrar valor salvo, usa o valor padrão
      _r1 = _timeFromPrefs(prefs.getString(ConfiguracoesScreen.R1_KEY)) ?? _r1;
      _r2 = _timeFromPrefs(prefs.getString(ConfiguracoesScreen.R2_KEY)) ?? _r2;
      _r3 = _timeFromPrefs(prefs.getString(ConfiguracoesScreen.R3_KEY)) ?? _r3;
      _r4 = _timeFromPrefs(prefs.getString(ConfiguracoesScreen.R4_KEY)) ?? _r4;
      _isLoading = false; // Indica que o carregamento terminou
    });
  }

  // Salva todos os horários no SharedPreferences
  Future<void> _saveHorarios() async {
    final prefs = await SharedPreferences.getInstance();
    // Usa as chaves da classe pública e o helper _timeToString
    await prefs.setString(ConfiguracoesScreen.R1_KEY, _timeToString(_r1));
    await prefs.setString(ConfiguracoesScreen.R2_KEY, _timeToString(_r2));
    await prefs.setString(ConfiguracoesScreen.R3_KEY, _timeToString(_r3));
    await prefs.setString(ConfiguracoesScreen.R4_KEY, _timeToString(_r4));

    // Verifica se o widget ainda está montado antes de usar o context
    if (!mounted) return;
    // Mostra feedback para o usuário
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Horários salvos com sucesso!'),
        backgroundColor: Colors.green, // Cor de sucesso
      ),
    );
    // Volta para a tela anterior após salvar
    Navigator.of(context).pop();
  }

  // Helper para mostrar o seletor de hora nativo do Flutter
  Future<void> _selectTime(
    BuildContext context,
    TimeOfDay initialTime,
    ValueChanged<TimeOfDay> onTimeChanged,
  ) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: 'Selecione o horário de início da rodada', // Texto de ajuda
      builder: (context, child) {
        // Opcional: Aplica tema específico ao picker
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Theme.of(context).primaryColor, // Cor principal
              onPrimary: Colors.white, // Cor do texto sobre a cor principal
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(
                  context,
                ).primaryColor, // Cor dos botões OK/Cancelar
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    // Atualiza o estado se um novo horário foi selecionado
    if (picked != null && picked != initialTime) {
      setState(() {
        onTimeChanged(picked);
      });
    }
  }

  // --- Helpers de conversão TimeOfDay <-> String ---
  // Converte TimeOfDay para uma string simples "HH:MM"
  String _timeToString(TimeOfDay time) => '${time.hour}:${time.minute}';

  // Converte a string "HH:MM" de volta para TimeOfDay
  TimeOfDay? _timeFromPrefs(String? prefsString) {
    if (prefsString == null) return null;
    try {
      final parts = prefsString.split(':');
      if (parts.length != 2) return null; // Validação básica do formato
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      // Validação básica dos valores
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      print("Erro ao converter string '$prefsString' para TimeOfDay: $e");
      return null; // Retorna nulo se a string estiver mal formatada ou inválida
    }
  }
  // --- Fim dos Helpers ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Programar Horários das Rodadas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoading
                ? null
                : _saveHorarios, // Desabilita salvar enquanto carrega
            tooltip: 'Salvar Horários',
          ),
        ],
      ),
      // Mostra um indicador de progresso enquanto os horários são carregados
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          // Mostra a lista de seletores de horário após carregar
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildTimePickerTile(
                  "Rodada 1",
                  _r1,
                  (newTime) => _r1 = newTime,
                ),
                const SizedBox(height: 8), // Pequeno espaço
                _buildTimePickerTile(
                  "Rodada 2",
                  _r2,
                  (newTime) => _r2 = newTime,
                ),
                const SizedBox(height: 8),
                _buildTimePickerTile(
                  "Rodada 3",
                  _r3,
                  (newTime) => _r3 = newTime,
                ),
                const SizedBox(height: 8),
                _buildTimePickerTile(
                  "Rodada 4",
                  _r4,
                  (newTime) => _r4 = newTime,
                ),
                const SizedBox(
                  height: 32,
                ), // Espaço maior antes do botão salvar
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_alt_rounded), // Ícone de salvar
                  label: const Text('Salvar e Voltar'),
                  onPressed: _saveHorarios,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                    ), // Botão mais alto
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    backgroundColor: Theme.of(
                      context,
                    ).primaryColor, // Cor primária do tema
                    foregroundColor: Colors.white, // Texto branco
                    shape: RoundedRectangleBorder(
                      // Bordas arredondadas
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // Widget helper para criar cada linha de seleção de horário na lista
  Widget _buildTimePickerTile(
    String title,
    TimeOfDay time,
    ValueChanged<TimeOfDay> onChanged,
  ) {
    return Card(
      elevation: 2, // Sombra sutil
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ), // Bordas arredondadas
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          vertical: 10,
          horizontal: 16,
        ), // Padding interno
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        subtitle: Text(
          // Usa o formatador do context para exibir a hora corretamente (ex: 19:10)
          'Horário de início: ${time.format(context)}',
          style: const TextStyle(fontSize: 16, color: Colors.black54),
        ),
        trailing: Icon(
          // Ícone à direita
          Icons.edit_calendar_outlined,
          color: Theme.of(context).primaryColor,
          size: 28,
        ),
        // Chama o helper para mostrar o TimePicker ao tocar na linha
        onTap: () => _selectTime(context, time, onChanged),
      ),
    );
  }
}
