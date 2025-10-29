import 'dart:convert'; // Para jsonEncode e jsonDecode
import 'package:flutter/material.dart'; // Para Widgets Flutter
import 'package:shared_preferences/shared_preferences.dart'; // Para persistência de dados
import 'package:logging/logging.dart'; // Para logging (depuração)

// Configuração de logging para depuração
final _log = Logger('ConfiguracoesScreen');

class ConfiguracoesScreen extends StatefulWidget {
  const ConfiguracoesScreen({super.key});

  // Chaves para SharedPreferences
  static const String HORARIOS_KEY = 'horarios_rodadas';
  static const String DURACAO_RODADA_KEY =
      'duracao_rodada_minutos'; // Chave para a duração da rodada

  @override
  State<ConfiguracoesScreen> createState() => _ConfiguracoesScreenState();
}

// Classe de Estado para a tela de configurações
class _ConfiguracoesScreenState extends State<ConfiguracoesScreen> {
  // Lista de horários das rodadas (TimeOfDay do Flutter)
  final List<TimeOfDay> _horarios = [];
  // Chave para o formulário, usada para validação
  final _formKey = GlobalKey<FormState>();

  // Duração padrão da rodada em minutos
  int _duracaoRodadaMinutos = 5;
  // Controller para o campo de texto da duração da rodada
  final TextEditingController _duracaoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadConfiguracoes(); // Carrega as configurações salvas ao iniciar a tela
  }

  @override
  void dispose() {
    _duracaoController
        .dispose(); // Libera o controller quando o widget é descartado
    super.dispose();
  }

  /// Carrega os horários das rodadas e a duração da rodada do SharedPreferences.
  Future<void> _loadConfiguracoes() async {
    final prefs = await SharedPreferences.getInstance();

    // --- Carregar Horários das Rodadas ---
    final String? horariosJson = prefs.getString(
      ConfiguracoesScreen.HORARIOS_KEY,
    );
    if (horariosJson != null && horariosJson.isNotEmpty) {
      try {
        final List<dynamic> loadedHorarios = jsonDecode(horariosJson);
        setState(() {
          _horarios.clear(); // Limpa a lista atual antes de carregar
          for (var h in loadedHorarios) {
            final parts = (h as String).split(':');
            _horarios.add(
              TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
            );
          }
          // Garante que os horários estejam ordenados
          _horarios.sort((a, b) {
            if (a.hour != b.hour) return a.hour.compareTo(b.hour);
            return a.minute.compareTo(b.minute);
          });
        });
        _log.info(
          "Horários carregados: ${_horarios.map((e) => e.format(context)).toList()}",
        );
      } catch (e, s) {
        _log.severe("Erro ao carregar horários salvos", e, s);
        // Em caso de erro, limpa a lista para evitar dados inválidos
        if (mounted) setState(() => _horarios.clear());
      }
    } else {
      _log.info("Nenhum horário salvo encontrado.");
    }

    // --- Carregar Duração da Rodada ---
    _duracaoRodadaMinutos =
        prefs.getInt(ConfiguracoesScreen.DURACAO_RODADA_KEY) ??
        5; // Padrão de 5 minutos
    _duracaoController.text = _duracaoRodadaMinutos
        .toString(); // Atualiza o controller do campo de texto

    _log.info("Duração da rodada carregada: $_duracaoRodadaMinutos minutos");

    // Garante que a UI seja atualizada após o carregamento
    if (mounted) setState(() {});
  }

  /// Salva os horários das rodadas e a duração da rodada no SharedPreferences.
  Future<void> _saveConfiguracoes() async {
    // Valida o formulário antes de salvar
    if (!(_formKey.currentState?.validate() ?? false)) {
      _log.warning("Formulário inválido, não salvando configurações.");
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // Salva horários das rodadas
    final List<String> horariosParaSalvar = _horarios
        .map((h) => '${h.hour}:${h.minute}')
        .toList();
    await prefs.setString(
      ConfiguracoesScreen.HORARIOS_KEY,
      jsonEncode(horariosParaSalvar),
    );
    _log.info("Horários salvos: $horariosParaSalvar");

    // Salva a duração da rodada
    await prefs.setInt(
      ConfiguracoesScreen.DURACAO_RODADA_KEY,
      _duracaoRodadaMinutos,
    );
    _log.info("Duração da rodada salva: $_duracaoRodadaMinutos minutos");

    // Exibe uma SnackBar de sucesso
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurações salvas com sucesso!')),
      );
    }
  }

  /// Abre o seletor de tempo para adicionar um novo horário de rodada.
  void _addHorario() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(alwaysUse24HourFormat: true), // Força formato 24h
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      // Verifica se o widget ainda está montado
      setState(() {
        _horarios.add(picked);
        // Mantém a lista ordenada após adicionar um novo horário
        _horarios.sort((a, b) {
          if (a.hour != b.hour) return a.hour.compareTo(b.hour);
          return a.minute.compareTo(b.minute);
        });
      });
      _saveConfiguracoes(); // Salva as configurações após adicionar o horário
    }
  }

  /// Remove um horário de rodada da lista.
  void _removeHorario(TimeOfDay horario) {
    setState(() {
      _horarios.remove(horario);
    });
    _saveConfiguracoes(); // Salva as configurações após remover o horário
  }

  /// Edita um horário de rodada existente na lista.
  void _editHorario(int index) async {
    if (index < 0 || index >= _horarios.length) {
      _log.warning("Tentativa de editar horário com índice inválido: $index");
      return;
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _horarios[index], // Usa o horário atual como inicial
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(alwaysUse24HourFormat: true), // Força formato 24h
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _horarios[index] = picked; // Atualiza o horário na posição existente
        // Mantém a lista ordenada após a edição
        _horarios.sort((a, b) {
          if (a.hour != b.hour) return a.hour.compareTo(b.hour);
          return a.minute.compareTo(b.minute);
        });
      });
      _saveConfiguracoes(); // Salva as configurações após a edição
      _log.info(
        "Horário na posição $index editado para ${picked.format(context)}",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações do Professor')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Campo para definir a duração da rodada ---
              TextFormField(
                controller: _duracaoController,
                decoration: const InputDecoration(
                  labelText: 'Duração da Rodada (minutos)',
                  border: OutlineInputBorder(),
                  suffixText: 'min',
                  prefixIcon: Icon(Icons.timer),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, insira a duração.';
                  }
                  final int? duracao = int.tryParse(value);
                  if (duracao == null || duracao <= 0) {
                    return 'A duração deve ser um número inteiro positivo.';
                  }
                  return null;
                },
                onChanged: (value) {
                  // Atualiza a variável de estado '_duracaoRodadaMinutos' quando o texto muda
                  final int? duracao = int.tryParse(value);
                  if (duracao != null && duracao > 0) {
                    setState(() {
                      _duracaoRodadaMinutos = duracao;
                    });
                  }
                },
                onFieldSubmitted: (_) => _saveConfiguracoes(),
              ),
              const SizedBox(height: 20), // Espaço entre os elementos
              // --- Cabeçalho e botão para adicionar horários ---
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween, // Mantém o alinhamento
                children: [
                  // Texto à esquerda
                  const Text(
                    'Horários das Rodadas:  ',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  // Botão à direita, envolvido em Flexible(loose)
                  Flexible(
                    fit: FlexFit
                        .loose, // Permite que o botão tenha seu tamanho natural
                    child: ElevatedButton.icon(
                      onPressed: _addHorario,
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar Horário'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // --- Lista de horários de rodadas ---
              Expanded(
                child: _horarios.isEmpty
                    ? const Center(
                        child: Text(
                          'Nenhum horário de rodada programado. Adicione alguns para que o sistema funcione!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _horarios.length,
                        itemBuilder: (context, index) {
                          final horario = _horarios[index];
                          // Gera o título dinamicamente usando o índice
                          final String tituloRodada = 'Rodada ${index + 1}';

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 8,
                            ), // Ajuste a margem se necessário
                            elevation: 1, // Sombra suave
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ), // Bordas arredondadas
                            child: ListTile(
                              leading: Icon(
                                Icons.access_time_filled,
                                color: Theme.of(context).primaryColor,
                              ), // Ícone de relógio
                              title: Text(
                                tituloRodada, // <-- Título "Rodada X"
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                'Horário de início: ${horario.format(context)}', // <-- Subtítulo com o horário
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ), // Ícone de lixeira (outline)
                                onPressed: () => _removeHorario(horario),
                                tooltip: 'Remover Horário',
                              ),
                              onTap: () => _editHorario(index),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 16,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      // Botão flutuante para salvar todas as configurações
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _saveConfiguracoes();
        },
        label: const Text('Salvar Tudo'),
        icon: const Icon(Icons.save),
        tooltip: 'Salvar Horários e Duração da Rodada',
      ),
    );
  }
}
