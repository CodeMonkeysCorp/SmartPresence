import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';

final _log = Logger('ConfiguracoesScreen');

class ConfiguracoesScreen extends StatefulWidget {
  const ConfiguracoesScreen({super.key});

  static const String HORARIOS_KEY = 'horarios_rodadas';
  static const String DURACAO_RODADA_KEY = 'duracao_rodada_minutos';

  @override
  State<ConfiguracoesScreen> createState() => _ConfiguracoesScreenState();
}

class _ConfiguracoesScreenState extends State<ConfiguracoesScreen> {
  final List<TimeOfDay> _horarios = [];
  final _formKey = GlobalKey<FormState>();

  int _duracaoRodadaMinutos = 5;
  final TextEditingController _duracaoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadConfiguracoes();
  }

  @override
  void dispose() {
    _duracaoController.dispose();
    super.dispose();
  }

  Future<void> _loadConfiguracoes() async {
    final prefs = await SharedPreferences.getInstance();

    final String? horariosJson = prefs.getString(
      ConfiguracoesScreen.HORARIOS_KEY,
    );
    if (horariosJson != null && horariosJson.isNotEmpty) {
      try {
        final List<dynamic> loadedHorarios = jsonDecode(horariosJson);
        setState(() {
          _horarios.clear();
          for (var h in loadedHorarios) {
            final parts = (h as String).split(':');
            _horarios.add(
              TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
            );
          }
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
        if (mounted) setState(() => _horarios.clear());
      }
    } else {
      _log.info("Nenhum horário salvo encontrado.");
    }

    _duracaoRodadaMinutos =
        prefs.getInt(ConfiguracoesScreen.DURACAO_RODADA_KEY) ?? 5;
    _duracaoController.text = _duracaoRodadaMinutos.toString();

    _log.info("Duração da rodada carregada: $_duracaoRodadaMinutos minutos");

    if (mounted) setState(() {});
  }

  Future<void> _saveConfiguracoes() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      _log.warning("Formulário inválido, não salvando configurações.");
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    final List<String> horariosParaSalvar = _horarios
        .map((h) => '${h.hour}:${h.minute}')
        .toList();
    await prefs.setString(
      ConfiguracoesScreen.HORARIOS_KEY,
      jsonEncode(horariosParaSalvar),
    );
    _log.info("Horários salvos: $horariosParaSalvar");

    await prefs.setInt(
      ConfiguracoesScreen.DURACAO_RODADA_KEY,
      _duracaoRodadaMinutos,
    );
    _log.info("Duração da rodada salva: $_duracaoRodadaMinutos minutos");

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurações salvas com sucesso!')),
      );
    }
  }

  void _addHorario() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _horarios.add(picked);
        _horarios.sort((a, b) {
          if (a.hour != b.hour) return a.hour.compareTo(b.hour);
          return a.minute.compareTo(b.minute);
        });
      });
      _saveConfiguracoes();
    }
  }

  void _removeHorario(TimeOfDay horario) {
    setState(() {
      _horarios.remove(horario);
    });
    _saveConfiguracoes();
  }

  void _editHorario(int index) async {
    if (index < 0 || index >= _horarios.length) {
      _log.warning("Tentativa de editar horário com índice inválido: $index");
      return;
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _horarios[index],
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _horarios[index] = picked;
        _horarios.sort((a, b) {
          if (a.hour != b.hour) return a.hour.compareTo(b.hour);
          return a.minute.compareTo(b.minute);
        });
      });
      _saveConfiguracoes();
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
                  final int? duracao = int.tryParse(value);
                  if (duracao != null && duracao > 0) {
                    setState(() {
                      _duracaoRodadaMinutos = duracao;
                    });
                  }
                },
                onFieldSubmitted: (_) => _saveConfiguracoes(),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Horários das Rodadas:  ',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Flexible(
                    fit: FlexFit.loose,
                    child: ElevatedButton.icon(
                      onPressed: _addHorario,
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar Horário'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
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
                          final String tituloRodada = 'Rodada ${index + 1}';

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 8,
                            ),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: Icon(
                                Icons.access_time_filled,
                                color: Theme.of(context).primaryColor,
                              ),
                              title: Text(
                                tituloRodada,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                'Horário de início: ${horario.format(context)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
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
