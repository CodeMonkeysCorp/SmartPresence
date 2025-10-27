import 'package:flutter/material.dart';
import 'package:logging/logging.dart'; // 1. Importar o logging
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // Para JSON

// 2. Criar a instância do Logger
final _log = Logger('ConfiguracoesScreen');

class ConfiguracoesScreen extends StatefulWidget {
  const ConfiguracoesScreen({super.key});

  // Chave pública única para salvar a LISTA de horários
  static const String HORARIOS_KEY = 'horarios_rodadas_lista';

  @override
  State<ConfiguracoesScreen> createState() => _ConfiguracoesScreenState();
}

class _ConfiguracoesScreenState extends State<ConfiguracoesScreen> {
  // A UI agora é controlada por uma lista dinâmica
  List<TimeOfDay> _horarios = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHorarios();
  }

  // Ordena a lista de horários
  void _sortHorarios() {
    _horarios.sort((a, b) {
      if (a.hour != b.hour) return a.hour.compareTo(b.hour);
      return a.minute.compareTo(b.minute);
    });
  }

  // Carrega a LISTA de horários salvos do SharedPreferences
  Future<void> _loadHorarios() async {
    _log.info('Carregando lista de horários do SharedPreferences...');
    try {
      final prefs = await SharedPreferences.getInstance();
      // Lê a string JSON que contém a lista
      final String? horariosJson = prefs.getString(
        ConfiguracoesScreen.HORARIOS_KEY,
      );

      if (horariosJson != null && horariosJson.isNotEmpty) {
        // Decodifica o JSON para uma lista de Strings (ex: ["19:10", "20:00"])
        final List<dynamic> horariosListaStrings = jsonDecode(horariosJson);
        // Converte as strings de volta para TimeOfDay
        _horarios = horariosListaStrings
            .map((timeStr) => _timeFromPrefs(timeStr as String))
            .whereType<TimeOfDay>() // Filtra qualquer valor nulo (inválido)
            .toList();
        _log.info(
          'Lista de horários carregada com ${_horarios.length} rodadas.',
        );
      } else {
        _log.info('Nenhuma lista de horários salva. Usando valores padrão.');
        // Se for a primeira vez, usa os 4 horários padrão
        _horarios = [
          const TimeOfDay(hour: 19, minute: 10),
          const TimeOfDay(hour: 20, minute: 0),
          const TimeOfDay(hour: 20, minute: 50),
          const TimeOfDay(hour: 21, minute: 40),
        ];
      }
      _sortHorarios(); // Garante que estejam ordenados
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e, s) {
      _log.severe(
        'Falha ao carregar SharedPreferences ou decodificar JSON',
        e,
        s,
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
          _horarios = []; // Reseta em caso de erro
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao carregar configurações salvas.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Salva a LISTA de horários no SharedPreferences
  Future<void> _saveHorarios() async {
    _log.info('Salvando lista de horários...');
    try {
      final prefs = await SharedPreferences.getInstance();
      // Converte a lista de TimeOfDay em uma lista de Strings "HH:MM"
      final List<String> horariosListaStrings = _horarios
          .map(_timeToString)
          .toList();
      // Codifica a lista de strings em uma única string JSON
      final String horariosJson = jsonEncode(horariosListaStrings);

      // Salva a string JSON no SharedPreferences
      await prefs.setString(ConfiguracoesScreen.HORARIOS_KEY, horariosJson);

      _log.info('Lista de horários salva com ${_horarios.length} rodadas.');
      if (!mounted) return;
      // Mostra feedback para o usuário
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Horários salvos com sucesso!'),
          backgroundColor: Colors.green, // Cor de sucesso
        ),
      );
      Navigator.of(context).pop();
    } catch (e, s) {
      _log.severe('Falha ao salvar horários no SharedPreferences', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao salvar configurações.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Helper para mostrar o seletor de hora (para Adicionar ou Editar)
  Future<void> _selectTime(
    BuildContext context,
    TimeOfDay initialTime,
    ValueChanged<TimeOfDay> onTimeChanged,
  ) async {
    _log.fine('Abrindo seletor de horário. Valor inicial: $initialTime');
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
      _log.info('Novo horário selecionado: $picked');
      setState(() {
        onTimeChanged(picked);
        _sortHorarios(); // Ordena a lista após qualquer alteração
      });
    } else {
      _log.fine('Seletor de horário fechado sem alterações.');
    }
  }

  // --- Helpers de conversão TimeOfDay <-> String (Sem alteração) ---
  String _timeToString(TimeOfDay time) => '${time.hour}:${time.minute}';

  TimeOfDay? _timeFromPrefs(String? prefsString) {
    if (prefsString == null) return null;
    try {
      final parts = prefsString.split(':');
      if (parts.length != 2) {
        _log.warning(
          'String de horário mal formatada (partes != 2): "$prefsString"',
        );
        return null;
      }
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        _log.warning('String de horário com valores inválidos: "$prefsString"');
        return null;
      }
      return TimeOfDay(hour: hour, minute: minute);
    } catch (e, stackTrace) {
      _log.warning(
        "Erro ao converter string '$prefsString' para TimeOfDay.",
        e,
        stackTrace,
      );
      return null;
    }
  }
  // --- Fim dos Helpers ---

  // --- NOVAS FUNÇÕES DE UI ---

  // Chamado pelo botão '+' na AppBar
  void _addNewHorario() {
    _log.info('Tentando adicionar novo horário...');
    // Abre o seletor de horário com o horário atual
    _selectTime(context, TimeOfDay.now(), (newTime) {
      // Esta é a função onTimeChanged
      _horarios.add(newTime); // Adiciona o novo horário à lista
      _log.info('Novo horário $newTime adicionado à lista.');
    });
    // _selectTime já chama setState e _sortHorarios
  }

  // Chamado pelo ícone de lixeira no ListTile
  void _removeHorario(int index) {
    if (index < 0 || index >= _horarios.length) return;
    final removedTime = _horarios[index];
    _log.info('Removendo horário: $removedTime');
    setState(() {
      _horarios.removeAt(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Horário ${removedTime.format(context)} removido.'),
        backgroundColor: Colors.orange,
      ),
    );
  }
  // --- FIM DAS NOVAS FUNÇÕES ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Programar Horários'),
        actions: [
          // Botão para Adicionar novo horário
          IconButton(
            icon: const Icon(Icons.add_alarm_rounded),
            onPressed: _addNewHorario,
            tooltip: 'Adicionar Novo Horário',
          ),
          // Botão Salvar
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoading
                ? null
                : _saveHorarios, // Desabilita salvar enquanto carrega
            tooltip: 'Salvar Horários',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          // A UI principal agora é um ListView.builder
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _horarios.length,
                    itemBuilder: (context, index) {
                      final time = _horarios[index];
                      // Gera o título da rodada dinamicamente
                      final title = 'Rodada ${index + 1}';
                      return _buildTimePickerTile(
                        title,
                        time,
                        index, // Passa o índice para remoção
                        (newTime) {
                          // Função de onChanged (para editar)
                          _horarios[index] = newTime;
                        },
                      );
                    },
                  ),
                ),
                // Botão Salvar na parte inferior
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('Salvar e Voltar'),
                    onPressed: _saveHorarios,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(
                        double.infinity,
                        50,
                      ), // Ocupa largura
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // Widget helper MODIFICADO para incluir o botão de deletar
  Widget _buildTimePickerTile(
    String title,
    TimeOfDay time,
    int index, // Índice para saber qual remover
    ValueChanged<TimeOfDay> onChanged,
  ) {
    return Card(
      // Não usa mais a margem do tema, pois o padding está no ListView
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          vertical: 10,
          horizontal: 16,
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        subtitle: Text(
          'Horário de início: ${time.format(context)}',
          style: const TextStyle(fontSize: 16, color: Colors.black54),
        ),
        // O trailing agora é um botão de deletar
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: Colors.red[700], size: 28),
          tooltip: 'Remover $title',
          onPressed: () => _removeHorario(index),
        ),
        // O onTap agora é usado para EDITAR
        onTap: () => _selectTime(context, time, onChanged),
      ),
    );
  }
}
