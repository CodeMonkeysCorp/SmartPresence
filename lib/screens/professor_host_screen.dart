// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:nsd/nsd.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

import 'configuracoes_screen.dart';
import 'historico_screen.dart';
import '../models/app_models.dart';

final _log = Logger('ProfessorHostScreen');

class ProfessorHostScreen extends StatefulWidget {
  const ProfessorHostScreen({super.key});
  @override
  State<ProfessorHostScreen> createState() => _ProfessorHostScreenState();
}

class _ProfessorHostScreenState extends State<ProfessorHostScreen> {
  HttpServer? _server;
  final List<AlunoConectado> _clients = [];
  String _serverStatus = 'Iniciando servidor...';
  bool _isServerRunning = false;
  int _port = 0;
  String _serverIp = "Aguardando IP...";
  Registration? _registration;

  Timer? _gameLoopTimer;
  List<Rodada> _rodadas = [];
  bool _isLoading = true;

  Map<String, Map<String, String>> _presencas = {};
  Map<String, String> _alunoNomes = {};
  static const String _historicoKey = 'historico_geral_presencas';

  int _duracaoRodadaMinutos = 5;
  final Map<String, DateTime> _rodadaEndTimes = {};
  Timer? _uiUpdateTimer;

  final Map<String, Map<String, int>> _pinAttempts = {};
  static const int _maxPinAttempts = 3;
  static const int _pinWindowMinutesDefault = 10;
  static const int _millisPerMinute = 60 * 1000;
  int _pinWindowMillis = _pinWindowMinutesDefault * _millisPerMinute;

  static const String _pinAttemptsKey = 'pin_attempts_v1';
  static const String _pinWindowMinutesKey = 'pin_window_minutes';

  static const double _cardOpacity = 0.05;
  static const double _pinContainerOpacity = 0.1;
  static const double _pinBorderOpacity = 0.5;

  @override
  void initState() {
    super.initState();
    _initializeServer();
  }

  @override
  void dispose() {
    _stopServer();
    _uiUpdateTimer?.cancel();
    super.dispose();
  }

  /// Inicializa o servidor WebSocket, carrega configurações e define o estado inicial das rodadas.
  Future<void> _initializeServer() async {
    if (_isServerRunning) {
      _log.info("Servidor já está rodando. Ignorando _initializeServer.");
      return;
    }

    setState(() {
      _isLoading = true;
      _serverStatus = 'Carregando configurações e iniciando servidor...';
      _serverIp = "Aguardando IP...";
      _port = 0;
      _rodadaEndTimes.clear();
    });

    await _loadConfiguracoesGerais();
    await _loadPinAttempts();
    await _loadRodadasFromPrefs();
    await _loadHistorico();

    if (!mounted) return;

    if (_rodadas.isEmpty) {
      setState(() {
        _serverStatus =
            'Erro! Programe os horários das rodadas primeiro nas configurações.';
        _isLoading = false;
        _isServerRunning = false;
      });
      return;
    }

    final now = DateTime.now();
    for (var rodada in _rodadas) {
      final rodadaStartTimeToday = DateTime(
        now.year,
        now.month,
        now.day,
        rodada.horaInicio.hour,
        rodada.horaInicio.minute,
      );
      final rodadaEndTimeToday = rodadaStartTimeToday.add(
        Duration(minutes: _duracaoRodadaMinutos),
      );

      if (now.isAfter(rodadaEndTimeToday)) {
        rodada.status = "Encerrada";
        rodada.pin = null;
        _rodadaEndTimes.remove(rodada.nome);
      } else if (now.isAfter(rodadaStartTimeToday)) {
        rodada.status = "Em Andamento";
        rodada.pin = _generatePin();
        _rodadaEndTimes[rodada.nome] = rodadaEndTimeToday;
      } else {
        rodada.status = "Aguardando";
        rodada.pin = null;
        _rodadaEndTimes.remove(rodada.nome);
      }
    }

    await _startServer();

    if (_isServerRunning) {
      _startGameLoop();
      _startUiUpdateTimer();
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Carrega configurações gerais, como a duração padrão de uma rodada, do SharedPreferences.
  Future<void> _loadConfiguracoesGerais() async {
    final prefs = await SharedPreferences.getInstance();
    _duracaoRodadaMinutos =
        prefs.getInt(ConfiguracoesScreen.DURACAO_RODADA_KEY) ?? 5;
    final pinWindowMinutes = prefs.getInt(_pinWindowMinutesKey);
    if (pinWindowMinutes != null && pinWindowMinutes > 0) {
      _pinWindowMillis = pinWindowMinutes * _millisPerMinute;
      _log.info('Janela de PIN configurada para $pinWindowMinutes minutos.');
    }
    _log.info("Duração da rodada configurada: $_duracaoRodadaMinutos minutos.");
  }

  /// Carrega tentativas de PIN salvas e remove entradas expiradas.
  Future<void> _loadPinAttempts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_pinAttemptsKey);
      if (raw == null || raw.isEmpty) return;
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      final now = DateTime.now().millisecondsSinceEpoch;
      decoded.forEach((key, value) {
        try {
          if (value is Map) {
            final count = (value['count'] ?? 0) as int;
            final firstAt = (value['firstAt'] ?? 0) as int;
            if (now - firstAt <= _pinWindowMillis) {
              _pinAttempts[key] = {'count': count, 'firstAt': firstAt};
            }
          }
        } catch (_) {}
      });
      if (_pinAttempts.isNotEmpty) {
        _log.info(
          'Carregadas ${_pinAttempts.length} entradas de tentativas de PIN.',
        );
      }
    } catch (e, s) {
      _log.warning('Erro ao carregar tentativas de PIN persistidas', e, s);
    }
  }

  /// Persiste as tentativas de PIN no SharedPreferences (assíncrono).
  Future<void> _savePinAttempts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> toSave = {};
      _pinAttempts.forEach((k, v) {
        toSave[k] = {'count': v['count'] ?? 0, 'firstAt': v['firstAt'] ?? 0};
      });
      await prefs.setString(_pinAttemptsKey, jsonEncode(toSave));
    } catch (e, s) {
      _log.warning('Erro ao salvar tentativas de PIN', e, s);
    }
  }

  /// Carrega o histórico de presenças e nomes dos alunos do SharedPreferences.
  Future<void> _loadHistorico() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? historicoJson = prefs.getString(_historicoKey);

      if (historicoJson != null && historicoJson.isNotEmpty) {
        final decodedData = jsonDecode(historicoJson) as Map<String, dynamic>;

        _alunoNomes = Map<String, String>.from(
          decodedData['nomes'] as Map? ?? {},
        );

        final presencasBruto =
            decodedData['presencas'] as Map<String, dynamic>? ?? {};
        _presencas = presencasBruto.map(
          (matricula, rodadasMap) =>
              MapEntry(matricula, Map<String, String>.from(rodadasMap as Map)),
        );

        _log.info(
          "Histórico carregado com ${_alunoNomes.length} alunos e ${_presencas.length} registros de presença.",
        );
      } else {
        _log.info("Nenhum histórico salvo encontrado. Iniciando vazio.");
        _presencas = {};
        _alunoNomes = {};
      }
    } catch (e, s) {
      _log.warning(
        "Erro ao carregar histórico salvo: $e. Iniciando vazio.",
        e,
        s,
      );
      _presencas = {};
      _alunoNomes = {};
    }
    if (mounted) setState(() {});
  }

  /// Salva o histórico de presenças e nomes dos alunos no SharedPreferences.
  Future<void> _saveHistorico() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> historicoData = {
        'nomes': _alunoNomes,
        'presencas': _presencas,
      };
      final String historicoJson = jsonEncode(historicoData);
      await prefs.setString(_historicoKey, historicoJson);
      _log.info(
        "Histórico salvo (${_alunoNomes.length} alunos, ${_presencas.length} presenças).",
      );
    } catch (e, s) {
      _log.severe("Erro ao salvar histórico", e, s);
      _showSnackBar("Erro ao salvar histórico.", isError: true);
    }
  }

  /// Carrega os horários das rodadas do SharedPreferences, definidas na tela de configurações.
  Future<void> _loadRodadasFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    TimeOfDay? timeFromPrefs(String? prefsString) {
      if (prefsString == null) return null;
      try {
        final parts = prefsString.split(':');
        if (parts.length != 2) return null;
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
        return TimeOfDay(hour: hour, minute: minute);
      } catch (e) {
        return null;
      }
    }

    final String? horariosJson = prefs.getString(
      ConfiguracoesScreen.HORARIOS_KEY,
    );

    if (horariosJson == null || horariosJson.isEmpty) {
      _log.warning("Nenhuma lista de horários encontrada (HORARIOS_KEY).");
      _rodadas = [];
    } else {
      _log.info("Carregando lista dinâmica de horários...");
      try {
        final List<dynamic> horariosListaStrings = jsonDecode(horariosJson);
        List<TimeOfDay> horarios = horariosListaStrings
            .map((timeStr) => timeFromPrefs(timeStr as String))
            .whereType<TimeOfDay>()
            .toList();

        horarios.sort((a, b) {
          if (a.hour != b.hour) return a.hour.compareTo(b.hour);
          return a.minute.compareTo(b.minute);
        });

        _rodadas = horarios.asMap().entries.map((entry) {
          int index = entry.key;
          TimeOfDay time = entry.value;
          return Rodada(nome: "Rodada ${index + 1}", horaInicio: time);
        }).toList();
        _log.info("Carregadas ${_rodadas.length} rodadas dinâmicas.");
      } catch (e, s) {
        _log.severe("Erro ao decodificar JSON de horários", e, s);
        _rodadas = [];
      }
    }
    if (mounted) setState(() {});
  }

  /// Inicia o servidor HTTP e WebSocket e anuncia o serviço via NSD.
  Future<void> _startServer() async {
    try {
      final info = NetworkInfo();
      _serverIp = (await info.getWifiIP()) ?? "127.0.0.1";

      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _port = _server!.port;

      _server!.listen(_handleWebSocketRequest);

      final Map<String, Uint8List?> txtData = {'ip': utf8.encode(_serverIp)};

      _registration = await register(
        Service(
          name: 'SmartPresence-${_serverIp.split('.').last}',
          type: '_smartpresence._tcp',
          port: _port,
          txt: txtData,
        ),
      );
      _log.info('Serviço SmartPresence anunciado na rede local (NSD).');

      if (mounted) {
        setState(() {
          _isServerRunning = true;
          _serverStatus = 'Servidor rodando em: $_serverIp:$_port';
          _isLoading = false;
        });
      }
      _log.info('Servidor iniciado em: $_serverIp:$_port');
    } catch (e, s) {
      _log.severe('Erro crítico ao iniciar o servidor ou anunciar NSD', e, s);
      if (mounted) {
        setState(() {
          _serverStatus =
              'Falha ao iniciar servidor: $e. Verifique permissões/rede.';
          _isServerRunning = false;
          _isLoading = false;
        });
      }
      await _stopServer(log: false);
    }
  }

  /// Inicia o loop de verificação periódica do estado das rodadas (a cada 10 segundos).
  void _startGameLoop() {
    _gameLoopTimer?.cancel();
    _log.info("Iniciando game loop (verificação de rodadas a cada 10s)...");
    _gameLoopTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted || !_isServerRunning) {
        timer.cancel();
        _gameLoopTimer = null;
        _log.info("Game loop parado.");
        return;
      }
      _verificarRodadas();
    });
  }

  /// Inicia um timer para atualizar a interface a cada segundo, mostrando o tempo restante nas rodadas ativas.
  void _startUiUpdateTimer() {
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_rodadaEndTimes.isNotEmpty) {
        setState(() {});
      }
    });
  }

  /// Função centralizada para verificar o estado das rodadas e atualizar a interface.
  void _verificarRodadas() {
    final now = DateTime.now();
    _log.fine(
      'Verificando rodadas... Hora atual: ${DateFormat('HH:mm:ss').format(now)}',
    );

    bool changed = false;
    for (var rodada in _rodadas) {
      final rodadaStartTimeToday = DateTime(
        now.year,
        now.month,
        now.day,
        rodada.horaInicio.hour,
        rodada.horaInicio.minute,
      );
      final rodadaEndTimeToday = rodadaStartTimeToday.add(
        Duration(minutes: _duracaoRodadaMinutos),
      );

      if (rodada.status == "Aguardando" &&
          now.isAfter(rodadaStartTimeToday) &&
          now.isBefore(rodadaEndTimeToday)) {
        _log.info('--> Hora de INICIAR ${rodada.nome}');
        _startRodada(rodada, rodadaEndTimeToday);
        changed = true;
      } else if (rodada.status == "Em Andamento" &&
          now.isAfter(rodadaEndTimeToday)) {
        _log.info('--> Hora de ENCERRAR ${rodada.nome} (por tempo)');
        _endRodada(rodada);
        changed = true;
      } else if (rodada.status == "Aguardando" &&
          now.isAfter(rodadaEndTimeToday)) {
        if (mounted) {
          setState(() {
            rodada.status = "Encerrada";
            rodada.pin = null;
            _rodadaEndTimes.remove(rodada.nome);
            _log.info(
              '--> Rodada ${rodada.nome} já expirou ao ser verificada. Marcando como Encerrada.',
            );
          });
        }
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  /// Gera um PIN aleatório de 4 dígitos.
  static const int _pinMin = 1000;
  static const int _pinMax = 9999;
  static const int _pinRange = _pinMax - _pinMin + 1;
  String _generatePin() => (_pinMin + Random().nextInt(_pinRange)).toString();

  /// Verifica se o IP do cliente está na mesma sub-rede do servidor (antifraude).
  bool _isSameSubnet(String clientIp, String serverIp) {
    if (clientIp == "127.0.0.1" || serverIp == "127.0.0.1") {
      _log.fine('Verificação de sub-rede: Permitindo localhost.');
      return true;
    }
    try {
      final serverAddr = InternetAddress.tryParse(serverIp);
      final clientAddr = InternetAddress.tryParse(clientIp);
      if (serverAddr == null || clientAddr == null) {
        _log.warning(
          'Verificação de sub-rede: IPs inválidos ($serverIp, $clientIp). Rejeitando.',
        );
        return false;
      }
      if (serverAddr.type == InternetAddressType.IPv4 &&
          clientAddr.type == InternetAddressType.IPv4) {
        final serverParts = serverIp.split('.');
        final clientParts = clientIp.split('.');
        if (serverParts.length != 4 || clientParts.length != 4) {
          _log.warning(
            'Verificação de sub-rede: formatos inesperados. Rejeitando.',
          );
          return false;
        }
        bool isSame =
            serverParts[0] == clientParts[0] &&
            serverParts[1] == clientParts[1] &&
            serverParts[2] == clientParts[2];
        _log.fine(
          'Verificação de sub-rede: $serverIp vs $clientIp -> ${isSame ? "OK" : "REJEITADO"}',
        );
        return isSame;
      }
      _log.fine(
        'Verificação de sub-rede: Detectado não-IPv4; pulando checagem rígida e permitindo (IPv6/Misto).',
      );
      return true;
    } catch (e, s) {
      _log.severe('Erro ao verificar sub-rede', e, s);
      return false;
    }
  }

  /// Retorna o número de tentativas registradas para a chave, considerando a janela temporal.
  int _getPinAttempts(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = _pinAttempts[key];
    if (entry == null) return 0;
    final firstAt = entry['firstAt'] ?? 0;
    if (now - firstAt > _pinWindowMillis) {
      _pinAttempts.remove(key);
      return 0;
    }
    return entry['count'] ?? 0;
  }

  /// Registra uma tentativa de PIN (cria entrada com data/hora se for a primeira).
  void _registerPinAttempt(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = _pinAttempts[key];
    if (entry == null) {
      _pinAttempts[key] = {'count': 1, 'firstAt': now};
      _savePinAttempts();
      return;
    }
    final firstAt = entry['firstAt'] ?? now;
    if (now - firstAt > _pinWindowMillis) {
      _pinAttempts[key] = {'count': 1, 'firstAt': now};
      _savePinAttempts();
    } else {
      entry['count'] = (entry['count'] ?? 0) + 1;
      _pinAttempts[key] = entry;
      _savePinAttempts();
    }
  }

  /// Limpa o contador de tentativas para a chave.
  void _clearPinAttempts(String key) {
    _pinAttempts.remove(key);
    _savePinAttempts();
  }

  /// Inicia uma rodada específica (manual ou automática).
  /// Recebe um `forcedEndTime` para garantir que o tempo de término seja consistente.
  void _startRodada(Rodada rodada, DateTime? forcedEndTime) {
    if (!_isServerRunning) {
      _showSnackBar(
        "Servidor não está rodando. Não é possível iniciar rodada.",
        isError: true,
      );
      _log.warning(
        "Tentativa de iniciar rodada '${rodada.nome}' com servidor parado.",
      );
      return;
    }
    if (rodada.status != "Aguardando") {
      _log.warning(
        "Tentativa de iniciar ${rodada.nome} que não está 'Aguardando' (status=${rodada.status}). Ignorando.",
      );
      return;
    }
    _log.info("Iniciando ${rodada.nome}...");
    if (mounted) {
      setState(() {
        rodada.status = "Em Andamento";
        rodada.pin = _generatePin();

        final endTime =
            forcedEndTime ??
            DateTime.now().add(Duration(minutes: _duracaoRodadaMinutos));
        _rodadaEndTimes[rodada.nome] = endTime;

        _broadcastMessage({
          'command': 'RODADA_ABERTA',
          'nome': rodada.nome,
          'message': 'A ${rodada.nome} está aberta! Insira o PIN.',
          'endTimeMillis': endTime.millisecondsSinceEpoch,
        });
      });
    }
    _showSnackBar("Rodada ${rodada.nome} iniciada.", isError: false);
  }

  /// Encerra uma rodada específica (manual ou automática).
  void _endRodada(Rodada rodada) {
    if (!_isServerRunning) {
      _log.warning(
        "Tentativa de encerrar rodada '${rodada.nome}' com servidor parado.",
      );
      return;
    }
    if (rodada.status != "Em Andamento") {
      _log.warning(
        "Tentativa de encerrar ${rodada.nome} que não está 'Em Andamento' (status=${rodada.status}). Ignorando.",
      );
      return;
    }
    _log.info("Encerrando ${rodada.nome}...");
    if (mounted) {
      setState(() {
        rodada.status = "Encerrada";
        rodada.pin = null;
        _rodadaEndTimes.remove(rodada.nome);

        final List<AlunoConectado> currentClients = List.from(_clients);
        for (var aluno in currentClients) {
          final matricula = aluno.matricula;
          _presencas[matricula] ??= {};
          if (!_presencas[matricula]!.containsKey(rodada.nome)) {
            _presencas[matricula]![rodada.nome] = 'Ausente';
            _log.info(
              "Aluno ${aluno.nome} ($matricula) marcado como Ausente para ${rodada.nome}.",
            );
          }
        }
        _saveHistorico();
      });
    }
    _broadcastMessage({'command': 'RODADA_FECHADA', 'nome': rodada.nome});
    _showSnackBar("Rodada ${rodada.nome} encerrada.", isError: false);
  }

  /// Lida com novas solicitações HTTP, fazendo atualização para WebSocket se for o caso.
  Future<void> _handleWebSocketRequest(HttpRequest request) async {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final String clientIp =
          request.connectionInfo?.remoteAddress.address ?? 'IP.Desconhecido';
      _log.info("Nova conexão WebSocket recebida de: $clientIp");

      try {
        WebSocket socket = await WebSocketTransformer.upgrade(request);
        socket.listen(
          (message) => _handleClientMessage(socket, message, clientIp),
          onDone: () {
            _log.info("Conexão WebSocket fechada (onDone) de: $clientIp");
            _removeClient(socket);
          },
          onError: (error, s) {
            _log.warning(
              'Erro na conexão WebSocket (onError) de: $clientIp',
              error,
              s,
            );
            _removeClient(socket);
          },
          cancelOnError: true,
        );
      } catch (e, s) {
        _log.severe("Erro ao fazer upgrade para WebSocket", e, s);
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.close();
      }
    } else {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write(
          'Servidor SmartPresence - Apenas conexões WebSocket são permitidas.',
        )
        ..close();
    }
  }

  /// Lida com mensagens recebidas dos clientes WebSocket.
  void _handleClientMessage(WebSocket socket, dynamic message, String alunoIp) {
    _log.fine('Mensagem recebida de $alunoIp: $message');
    try {
      final data = jsonDecode(message as String);
      if (data is! Map<String, dynamic> ||
          data['command'] == null ||
          data['command'] is! String) {
        _log.warning('Mensagem JSON inválida de $alunoIp: $message');
        if (socket.readyState == WebSocket.open) {
          socket.add(
            jsonEncode({
              'command': 'ERROR',
              'message': 'Mensagem JSON inválida.',
            }),
          );
        }
        return;
      }
      final String command = data['command'];

      int clientIndex = _clients.indexWhere((c) => c.socket == socket);
      AlunoConectado? aluno = (clientIndex != -1)
          ? _clients[clientIndex]
          : null;

      if (command == 'JOIN') {
        final String nome = data['nome'] ?? 'Aluno Desconhecido';
        final String matricula = data['matricula'] ?? 'MATRICULA_INVALIDA';

        if (matricula == 'MATRICULA_INVALIDA') {
          _log.warning(
            "Aluno $nome tentou conectar sem matrícula ($alunoIp). Rejeitando.",
          );
          socket.add(
            jsonEncode({
              'command': 'ERROR',
              'message': "Matrícula é obrigatória.",
            }),
          );
          socket.close(
            WebSocketStatus.policyViolation,
            "Matrícula é obrigatória.",
          );
          return;
        }

        int existingMatriculaIndex = _clients.indexWhere(
          (c) => c.matricula == matricula && c.socket != socket,
        );
        if (existingMatriculaIndex != -1) {
          _log.warning(
            "Matrícula $matricula já conectada por outro dispositivo. Desconectando nova tentativa de $alunoIp.",
          );
          socket.add(
            jsonEncode({
              'command': 'ERROR',
              'message':
                  "❌ Matrícula '$matricula' já está conectada em outro dispositivo. Desconecte o outro primeiro.",
            }),
          );
          socket.close(
            WebSocketStatus.policyViolation,
            "Matrícula já conectada.",
          );
          return;
        }

        aluno = AlunoConectado(
          socket: socket,
          nome: nome,
          matricula: matricula,
          ip: alunoIp,
          connectedAt: DateTime.now(),
        );

        if (clientIndex == -1) {
          if (mounted) {
            setState(() {
              _clients.add(aluno!);
              _presencas[matricula] ??= {};
              _alunoNomes[matricula] = nome;
            });
            _saveHistorico();
            _log.info(
              "Aluno $nome ($matricula) conectado ($alunoIp) e adicionado.",
            );
          }
        } else {
          if (mounted) {
            setState(() {
              _clients[clientIndex] = aluno!;
              _alunoNomes[matricula] = nome;
            });
            _saveHistorico();
            _log.info(
              "Aluno $nome ($matricula) reconectado/atualizado ($alunoIp).",
            );
          }
        }
        socket.add(
          jsonEncode({
            'command': 'JOIN_SUCCESS',
            'message': 'Bem-vindo, $nome!',
          }),
        );
      } else if (command == 'SUBMIT_PIN') {
        if (aluno == null) {
          _log.warning(
            "Recebido SUBMIT_PIN de socket não associado ($alunoIp). Rejeitando.",
          );
          socket.close(
            WebSocketStatus.policyViolation,
            "Identifique-se com JOIN primeiro.",
          );
          return;
        }

        final String pinEnviado = data['pin'] ?? '';
        final String rodadaNome = data['rodada'] ?? '';
        final matricula = aluno.matricula;

        final rodadaAtiva = _rodadas.firstWhereOrNull(
          (r) => r.nome == rodadaNome && r.status == "Em Andamento",
        );

        _presencas[matricula] ??= {};

        final attemptKey = "${matricula}_$rodadaNome";
        final int currentAttempts = _getPinAttempts(attemptKey);
        if (currentAttempts >= _maxPinAttempts) {
          _log.warning(
            'BLOQUEADO (RATE LIMIT): Aluno ${aluno.nome} ($matricula) excedeu $_maxPinAttempts tentativas para $rodadaNome',
          );
          _presencas[matricula]![rodadaNome] = 'Falhou PIN';
          _saveHistorico();
          socket.add(
            jsonEncode({
              'command': 'PRESENCA_FALHA',
              'message':
                  'Você excedeu o número máximo de tentativas ($_maxPinAttempts) na janela de ${_pinWindowMillis / _millisPerMinute} minutos. Tente novamente mais tarde.',
            }),
          );
          return;
        }

        if (!_isSameSubnet(alunoIp, _serverIp)) {
          _log.warning(
            'REJEITADO (ANTIFRAUDE): Aluno ${aluno.nome} ($matricula) de $alunoIp fora da sub-rede ($_serverIp).',
          );
          _presencas[matricula]![rodadaNome] = 'Falhou PIN (Rede)';
          _saveHistorico();
          socket.add(
            jsonEncode({
              'command': 'PRESENCA_FALHA',
              'message':
                  'Falha na verificação de rede. Use o mesmo Wi-Fi do professor.',
            }),
          );
          return;
        }
        _log.fine(
          'APROVADO (ANTIFRAUDE): Aluno ${aluno.nome} ($matricula) de $alunoIp na mesma sub-rede.',
        );

        if (rodadaAtiva != null && pinEnviado == rodadaAtiva.pin) {
          _log.info(
            'PIN Correto do aluno ${aluno.nome} ($matricula) para ${rodadaAtiva.nome}',
          );
          _presencas[matricula]![rodadaAtiva.nome] = 'Presente';
          _clearPinAttempts(attemptKey);
          _saveHistorico();
          socket.add(
            jsonEncode({'command': 'PRESENCA_OK', 'rodada': rodadaAtiva.nome}),
          );
        } else {
          String motivoFalha = rodadaAtiva == null
              ? "Rodada não ativa ou nome inválido"
              : "PIN incorreto";
          _log.info(
            'PIN Incorreto ou $motivoFalha do aluno ${aluno.nome} ($matricula) para $rodadaNome',
          );
          _registerPinAttempt(attemptKey);
          _presencas[matricula]![rodadaNome] = 'Falhou PIN';
          _saveHistorico();
          final tentativasRestantes = _maxPinAttempts - (currentAttempts + 1);
          socket.add(
            jsonEncode({
              'command': 'PRESENCA_FALHA',
              'message':
                  'PIN incorreto. Tentativas restantes: $tentativasRestantes',
            }),
          );
        }
      } else {
        _log.warning("Comando desconhecido recebido: $command de $alunoIp");
        socket.add(
          jsonEncode({'command': 'ERROR', 'message': 'Comando desconhecido.'}),
        );
      }
    } catch (e, s) {
      _log.severe(
        'Erro ao processar mensagem JSON ou lógica de $alunoIp',
        e,
        s,
      );
      if (socket.readyState == WebSocket.open) {
        socket.add(
          jsonEncode({
            'command': 'ERROR',
            'message': 'Erro interno no servidor.',
          }),
        );
      }
    }
  }

  /// Remove um cliente da lista de clientes conectados.
  void _removeClient(WebSocket socket) {
    final index = _clients.indexWhere((c) => c.socket == socket);
    if (index != -1) {
      final nomeAluno = _clients[index].nome;
      _log.info('Aluno $nomeAluno desconectado.');
      if (mounted) {
        setState(() {
          _clients.removeAt(index);
        });
      }
    } else {
      _log.fine(
        "Tentativa de remover um socket desconhecido (pode ser normal).",
      );
    }
  }

  /// Envia uma mensagem JSON para todos os clientes conectados.
  void _broadcastMessage(Map<String, dynamic> message) {
    final jsonMessage = jsonEncode(message);
    _log.fine("Enviando broadcast: $jsonMessage");
    final List<AlunoConectado> clientsCopy = List.from(_clients);
    int sentCount = 0;
    for (var client in clientsCopy) {
      try {
        if (client.socket.readyState == WebSocket.open) {
          client.socket.add(jsonMessage);
          sentCount++;
        } else {
          _log.fine(
            "Socket para ${client.nome} não estava aberto. Removendo silenciosamente.",
          );
          _removeClient(client.socket);
        }
      } catch (e, s) {
        _log.warning(
          "Erro ao enviar broadcast para ${client.nome}: $e. Removendo.",
          e,
          s,
        );
        _removeClient(client.socket);
      }
    }
    if (sentCount > 0 || clientsCopy.isEmpty) {
      _log.info("Broadcast enviado para $sentCount clientes ativos.");
    } else {
      _log.info("Nenhum cliente ativo para receber broadcast.");
    }
  }

  /// Desliga completamente o servidor, incluindo WebSocket, NSD e clientes conectados.
  Future<void> _stopServer({bool log = true}) async {
    if (!_isServerRunning && log) {
      _log.info("Tentativa de parar servidor que já está parado.");
      return;
    }
    if (log) _log.info("Iniciando processo de parada do servidor...");

    _gameLoopTimer?.cancel();
    _gameLoopTimer = null;
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;

    if (_registration != null) {
      try {
        await unregister(_registration!);
        if (log) _log.info("Serviço NSD cancelado com sucesso.");
      } catch (e, s) {
        if (log) _log.warning("Erro ao cancelar registro NSD", e, s);
      }
      _registration = null;
    }

    if (log) _log.info("Fechando conexões de ${_clients.length} clientes...");
    final List<AlunoConectado> clientsToClose = List.from(_clients);
    _clients.clear();

    for (var client in clientsToClose) {
      try {
        await client.socket.close(
          WebSocketStatus.goingAway,
          "Servidor encerrando.",
        );
        if (log) {
          _log.info(
            "Conexão com ${client.nome} (${client.matricula}) fechada.",
          );
        }
      } catch (e, s) {
        if (log) {
          _log.warning("Erro ao fechar socket do cliente ${client.nome}", e, s);
        }
      }
    }

    if (log) _log.info("Parando o servidor HTTP...");
    try {
      await _server?.close(force: true);
      if (log) _log.info("Servidor HTTP/WebSocket parado com sucesso.");
    } catch (e, s) {
      if (log) _log.warning("Erro ao fechar servidor HTTP", e, s);
    }
    _server = null;

    if (mounted) {
      setState(() {
        _isServerRunning = false;
        _serverStatus = "Servidor parado.";
        _port = 0;
        _serverIp = "Aguardando IP...";
        _isLoading = false;
        _rodadaEndTimes.clear();
      });
    }
    if (log) _log.info('Processo de parada do servidor concluído.');
  }

  /// Navega para a tela de histórico de presenças.
  void _navigateToHistorico(BuildContext context) {
    _log.info('Navegando para HistoricoScreen');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistoricoScreen(
          presencas: _presencas,
          alunoNomes: _alunoNomes,
          rodadas: _rodadas,
        ),
      ),
    );
  }

  /// Exibe uma SnackBar na parte inferior da tela.
  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
        ),
      );
    }
  }

  /// Exporta o histórico de presenças para um arquivo CSV.
  Future<void> _exportarCSV() async {
    _log.info("Iniciando exportação de CSV...");
    var status = await Permission.storage.request();
    if (!status.isGranted) {
      _showSnackBar('Permissão de armazenamento negada.', isError: true);
      _log.warning('Permissão de armazenamento negada ao tentar exportar CSV.');
      return;
    }

    List<List<String>> rows = [];
    rows.add([
      'matricula',
      'nome',
      'data',
      'rodada',
      'status',
      'gravado_em',
      'notas',
      'metodo_validacao',
    ]);
    final dateFormat = DateFormat('yyyy-MM-dd');
    final timeFormat = DateFormat('HH:mm:ss');
    final now = DateTime.now();
    final dataAtual = dateFormat.format(now);

    List<String> matriculas = _presencas.keys.toList()..sort();

    for (var matricula in matriculas) {
      final presencasRodadas = _presencas[matricula]!;
      final nomeAluno = _alunoNomes[matricula] ?? 'Nome Desconhecido';
      for (var rodada in _rodadas) {
        final status = presencasRodadas[rodada.nome] ?? 'Ausente';
        final gravadoEm = timeFormat.format(now);
        final metodoValidacao = _serverIp == "127.0.0.1"
            ? "Localhost"
            : "SubnetCheck";
        rows.add([
          matricula,
          nomeAluno,
          dataAtual,
          rodada.nome,
          status,
          gravadoEm,
          '',
          metodoValidacao,
        ]);
      }
    }

    String csvContent = rows
        .map(
          (row) =>
              row.map((item) => '"${item.replaceAll('"', '""')}"').join(','),
        )
        .join('\n');

    try {
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        throw Exception('Não foi possível acessar o diretório de downloads.');
      }
      final path =
          '${directory.path}/smartpresence_presencas_${DateFormat('yyyyMMdd_HHmmss').format(now)}.csv';
      final file = File(path);
      await file.writeAsString(csvContent, encoding: utf8);
      _showSnackBar('CSV exportado para: ${file.path}');
      _log.info('CSV exportado com sucesso para: ${file.path}');
    } catch (e, s) {
      _showSnackBar('Erro ao exportar CSV: $e', isError: true);
      _log.severe('Erro ao exportar CSV', e, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isServerRunning) {
          bool? sair = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Encerrar Sessão?'),
              content: const Text(
                'Parar o servidor e voltar para a tela inicial? Os alunos serão desconectados.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _stopServer();
                    if (mounted) Navigator.of(context).pop(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Encerrar'),
                ),
              ],
            ),
          );
          return sair ?? false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Navigator.canPop(context) ? const BackButton() : null,
          centerTitle: false,
          titleSpacing: NavigationToolbar.kMiddleSpacing / 2,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Expanded(
                child: const Text(
                  'Painel do Professor',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Ver Histórico',
              onPressed:
                  !_isLoading &&
                      (_presencas.isNotEmpty || _alunoNomes.isNotEmpty)
                  ? () => _navigateToHistorico(context)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Exportar CSV',
              onPressed:
                  _isServerRunning &&
                      (_presencas.isNotEmpty || _alunoNomes.isNotEmpty)
                  ? _exportarCSV
                  : null,
            ),
            if (_isServerRunning)
              IconButton(
                icon: const Icon(Icons.stop_circle_outlined),
                tooltip: 'Parar Servidor',
                onPressed: _stopServer,
                color: Colors.red,
              )
            else if (!_isLoading && !_isServerRunning && _rodadas.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.play_circle_outline),
                tooltip: 'Reiniciar Servidor',
                onPressed: _initializeServer,
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  /// Constrói o corpo principal da tela, mostrando o estado de carregamento, erro ou o painel principal.
  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(_serverStatus, style: const TextStyle(fontSize: 16)),
          ],
        ),
      );
    }
    if (_rodadas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 60,
                color: Colors.orange,
              ),
              const SizedBox(height: 16),
              Text(
                _serverStatus,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Colors.black87),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings),
                label: const Text('Configurar Horários'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ConfiguracoesScreen(),
                  ),
                ).then((_) => _initializeServer()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _initializeServer,
      child: ListView.builder(
        itemCount: _rodadas.length + 1,
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildClientList();
          }
          final rodada = _rodadas[index - 1];
          return _buildRodadaCard(rodada);
        },
      ),
    );
  }

  /// Widget que exibe o número de alunos conectados e o IP do servidor.
  Widget _buildClientList() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        leading: Icon(
          Icons.people_alt_rounded,
          color: Theme.of(context).primaryColor,
          size: 30,
        ),
        title: Text(
          "${_clients.length} Alunos Conectados",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        subtitle: Text(
          _isServerRunning
              ? 'Servidor em: $_serverIp:$_port'
              : 'Servidor parado ou não iniciado.',
          style: const TextStyle(fontSize: 14, color: Colors.black54),
        ),
        initiallyExpanded: _clients.isNotEmpty || _isLoading,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        tilePadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 8.0,
        ),
        children: _clients.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: const Text(
                    "Nenhum aluno conectado no momento.",
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ]
            : _clients
                  .map(
                    (aluno) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline, size: 20),
                      title: Text('${aluno.nome} (${aluno.matricula})'),
                      subtitle: Text('IP: ${aluno.ip}'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                  .toList(),
      ),
    );
  }

  /// Widget que exibe um card para cada rodada, com status, PIN e botões de ação.
  Widget _buildRodadaCard(Rodada rodada) {
    Color cardColor = Colors.white;
    Color accentColor = Colors.grey[600]!;
    IconData iconData = Icons.schedule;
    String statusDisplay = rodada.status;

    String? timeLeftFormatted;
    DateTime? endTime = _rodadaEndTimes[rodada.nome];
    Duration? remainingDuration;

    if (rodada.status == "Em Andamento") {
      cardColor = Theme.of(
        context,
      ).primaryColor.withAlpha((_cardOpacity * 255).round());
      accentColor = Theme.of(context).primaryColor;
      iconData = Icons.timer; // Ícone de timer quando em andamento

      if (endTime != null) {
        remainingDuration = endTime.difference(DateTime.now());
        if (!remainingDuration.isNegative && remainingDuration.inSeconds > 0) {
          final int minutes = remainingDuration.inMinutes;
          final int seconds = remainingDuration.inSeconds % 60;
          timeLeftFormatted =
              '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        } else {
          statusDisplay = 'Encerrando...';
          timeLeftFormatted = '00:00';
        }
      }
    } else if (rodada.status == "Encerrada") {
      cardColor = Colors.grey[100]!;
      accentColor = Colors.green[700]!;
      iconData = Icons.check_circle_outline;
    }
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: rodada.status == "Em Andamento"
              ? accentColor
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(iconData, color: accentColor, size: 35),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rodada.nome,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Início: ${rodada.horaInicio.format(context)}',
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 6),
                  if (rodada.status == "Em Andamento" &&
                      timeLeftFormatted != null)
                    Row(
                      children: [
                        Icon(
                          Icons.hourglass_bottom_rounded,
                          size: 18,
                          color: accentColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeLeftFormatted,
                          style: TextStyle(
                            fontSize: 16,
                            color: accentColor,
                            fontWeight: FontWeight.bold,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  Text(
                    'Status: $statusDisplay',
                    style: TextStyle(
                      fontSize: 14,
                      color: rodada.status == "Encerrada"
                          ? accentColor
                          : Colors.black54,
                      fontWeight: rodada.status == "Encerrada"
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              alignment: Alignment.centerRight,
              child: _buildRodadaActions(
                rodada,
                accentColor,
                timeLeftFormatted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Widget auxiliar para construir a seção de ações/PIN à direita do Card.
  Widget _buildRodadaActions(
    Rodada rodada,
    Color accentColor,
    String? timeLeftFormatted,
  ) {
    if (_isServerRunning && rodada.status == "Aguardando") {
      return IconButton(
        icon: Icon(
          Icons.play_arrow_rounded,
          color: Theme.of(context).primaryColor,
          size: 30,
        ),
        tooltip: 'Iniciar ${rodada.nome} Manualmente',
        onPressed: () => _startRodada(rodada, null),
      );
    } else if (_isServerRunning &&
        rodada.status == "Em Andamento" &&
        rodada.pin != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accentColor.withAlpha(
                (_pinContainerOpacity * 255).round(),
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: accentColor.withAlpha((_pinBorderOpacity * 255).round()),
                width: 1,
              ),
            ),
            child: Text(
              rodada.pin!,
              style: TextStyle(
                color: accentColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              Icons.stop_circle_outlined,
              color: Colors.red[700],
              size: 30,
            ),
            tooltip: 'Encerrar ${rodada.nome} Manualmente',
            onPressed: () => _endRodada(rodada),
          ),
        ],
      );
    } else {
      return const SizedBox(width: 40);
    }
  }
}

extension IterableExtension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
