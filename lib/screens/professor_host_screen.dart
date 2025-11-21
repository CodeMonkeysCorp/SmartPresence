// ignore_for_file: use_build_context_synchronously

import 'dart:async'; // Para Timer e Future
import 'dart:convert'; // Para jsonEncode, jsonDecode e utf8
import 'dart:io'; // Para HttpServer, WebSocket, HttpRequest, InternetAddress, HttpStatus
import 'dart:math'; // Para Random (geração de PIN)
import 'dart:typed_data'; // Para Uint8List (necessário para NSD txt records)
import 'package:flutter/material.dart'; // Para Widgets Flutter
import 'package:nsd/nsd.dart'; // Para Network Service Discovery (publicação do serviço)
import 'package:shared_preferences/shared_preferences.dart'; // Para persistência de dados
import 'package:network_info_plus/network_info_plus.dart'; // Para obter o IP da rede local
import 'package:intl/intl.dart'; // Para formatação de datas (exportação CSV)
import 'package:logging/logging.dart'; // Para logging (depuração)
import 'package:permission_handler/permission_handler.dart'; // Para permissões (exportação CSV)
import 'package:path_provider/path_provider.dart'; // Para obter diretórios (exportação CSV)

// Telas e modelos relacionados
import 'configuracoes_screen.dart'; // Importa a tela de configurações para usar suas chaves
import 'historico_screen.dart'; // Importa a tela de histórico
import '../models/app_models.dart'; // Importa os modelos Rodada e AlunoConectado

// Configuração de logging para depuração
final _log = Logger('ProfessorHostScreen');

class ProfessorHostScreen extends StatefulWidget {
  const ProfessorHostScreen({super.key});
  @override
  State<ProfessorHostScreen> createState() => _ProfessorHostScreenState();
}

class _ProfessorHostScreenState extends State<ProfessorHostScreen> {
  // --- Estados do Servidor e da Aplicação ---
  HttpServer?
  _server; // Instância do servidor HTTP que gerencia as conexões WebSocket
  final List<AlunoConectado> _clients =
      []; // Lista de alunos conectados atualmente
  String _serverStatus =
      'Iniciando servidor...'; // Mensagem de status para a UI
  bool _isServerRunning = false; // Indica se o servidor está ativo
  int _port = 0; // Porta em que o servidor está escutando
  String _serverIp =
      "Aguardando IP..."; // Endereço IP do servidor na rede local
  Registration? _registration; // Objeto para o registro do serviço NSD

  Timer?
  _gameLoopTimer; // Timer para verificar periodicamente o estado das rodadas
  List<Rodada> _rodadas = []; // Lista das rodadas de presença configuradas
  bool _isLoading =
      true; // Indica se a tela está em processo de inicialização/carregamento

  Map<String, Map<String, String>> _presencas =
      {}; // Mapa de presença: Matrícula -> Rodada -> Status
  Map<String, String> _alunoNomes =
      {}; // Mapa para armazenar o nome de cada aluno pela matrícula
  static const String _historicoKey =
      'historico_geral_presencas'; // Chave para SharedPreferences do histórico

  // --- Novos Estados para Duração e Timer da Rodada ---
  int _duracaoRodadaMinutos =
      5; // Duração padrão de uma rodada, carregada das configurações
  // Map para controlar o tempo de término (DateTime) de cada rodada que está "Em Andamento"
  final Map<String, DateTime> _rodadaEndTimes = {};
  // Timer para forçar a atualização da UI a cada segundo, mostrando o tempo restante nas rodadas ativas
  Timer? _uiUpdateTimer;

  // --- Estados para Antifraude: Rate Limiting de PIN ---
  // Rastreia tentativas de PIN: "matricula_rodada" -> count de tentativas
  // Estrutura: attemptKey -> { 'count': int, 'firstAt': int(millisecondsSinceEpoch) }
  final Map<String, Map<String, int>> _pinAttempts = {};
  static const int _maxPinAttempts = 3; // Máximo de tentativas por rodada
  // Janela de bloqueio (10 minutos por padrão). Pode ser sobrescrita por SharedPreferences
  int _pinWindowMillis = 10 * 60 * 1000;

  // Chave para persistir tentativas de PIN no SharedPreferences
  static const String _pinAttemptsKey = 'pin_attempts_v1';
  // Chave opcional para configurar janela em minutos
  static const String _pinWindowMinutesKey = 'pin_window_minutes';

  @override
  void initState() {
    super.initState();
    _initializeServer(); // Inicia o processo de configuração e servidor ao carregar a tela
  }

  @override
  void dispose() {
    _stopServer(); // Garante que o servidor seja parado e recursos liberados
    _uiUpdateTimer?.cancel(); // Cancela o timer de atualização da UI
    super.dispose();
  }

  // --- Funções Principais de Lógica ---

  /// 1. Inicializa o servidor WebSocket, carrega configurações, define o estado inicial das rodadas
  /// e inicia os timers necessários.
  Future<void> _initializeServer() async {
    if (_isServerRunning) {
      _log.info("Servidor já está rodando. Ignorando _initializeServer.");
      return;
    }

    // Define o estado inicial de carregamento para a UI
    setState(() {
      _isLoading = true;
      _serverStatus = 'Carregando configurações e iniciando servidor...';
      _serverIp = "Aguardando IP...";
      _port = 0;
      _rodadaEndTimes.clear(); // Limpa quaisquer tempos de rodada anteriores
    });

    // Carrega as configurações gerais (como a duração da rodada)
    await _loadConfiguracoesGerais();
    // Carrega tentativas de PIN persistidas (se houver) e purga expiradas
    await _loadPinAttempts();
    // Carrega os horários das rodadas definidos pelo professor
    await _loadRodadasFromPrefs();
    // Carrega o histórico de presenças e nomes de alunos
    await _loadHistorico();

    if (!mounted) return; // Verifica se o widget ainda está ativo

    // Se não houver rodadas configuradas, impede o início do servidor
    if (_rodadas.isEmpty) {
      setState(() {
        _serverStatus =
            'Erro! Programe os horários das rodadas primeiro nas configurações.';
        _isLoading = false;
        _isServerRunning = false;
      });
      return;
    }

    // --- Define o status inicial correto de cada rodada com base na hora atual ---
    final now = DateTime.now(); // Usa DateTime para cálculos precisos
    for (var rodada in _rodadas) {
      // Cria um DateTime para o início da rodada no dia atual
      final rodadaStartTimeToday = DateTime(
        now.year,
        now.month,
        now.day,
        rodada.horaInicio.hour,
        rodada.horaInicio.minute,
      );
      // Calcula o DateTime para o fim da rodada, adicionando a duração configurada
      final rodadaEndTimeToday = rodadaStartTimeToday.add(
        Duration(minutes: _duracaoRodadaMinutos),
      );

      if (now.isAfter(rodadaEndTimeToday)) {
        // Se a hora atual já passou do fim da rodada, marca como Encerrada
        rodada.status = "Encerrada";
        rodada.pin = null;
        _rodadaEndTimes.remove(rodada.nome); // Remove do controle de tempo
      } else if (now.isAfter(rodadaStartTimeToday)) {
        // Se a hora atual está entre o início e o fim, marca como Em Andamento
        rodada.status = "Em Andamento";
        rodada.pin = _generatePin(); // Gera um PIN
        _rodadaEndTimes[rodada.nome] =
            rodadaEndTimeToday; // Armazena o tempo de término
      } else {
        // Se a hora atual ainda não chegou ao início, marca como Aguardando
        rodada.status = "Aguardando";
        rodada.pin = null;
        _rodadaEndTimes.remove(rodada.nome);
      }
    }

    await _startServer(); // Tenta iniciar o servidor WebSocket e anunciar via NSD

    // Se o servidor iniciou com sucesso, inicia os timers de lógica e UI
    if (_isServerRunning) {
      _startGameLoop();
      _startUiUpdateTimer();
    } else {
      // Se o servidor não iniciou por algum motivo, garante que _isLoading seja false
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 2. Carrega configurações gerais, como a duração padrão de uma rodada, do SharedPreferences.
  Future<void> _loadConfiguracoesGerais() async {
    final prefs = await SharedPreferences.getInstance();
    // Obtém a duração da rodada salva, ou usa 5 minutos como padrão
    _duracaoRodadaMinutos =
        prefs.getInt(ConfiguracoesScreen.DURACAO_RODADA_KEY) ?? 5;
    // Carrega configuração de janela de PIN (em minutos), se existir
    final pinWindowMinutes = prefs.getInt(_pinWindowMinutesKey);
    if (pinWindowMinutes != null && pinWindowMinutes > 0) {
      _pinWindowMillis = pinWindowMinutes * 60 * 1000;
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
        } catch (_) {
          // ignore malformed entries
        }
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

  /// 3. Carrega o histórico de presenças e nomes dos alunos do SharedPreferences.
  Future<void> _loadHistorico() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? historicoJson = prefs.getString(_historicoKey);

      if (historicoJson != null && historicoJson.isNotEmpty) {
        final decodedData = jsonDecode(historicoJson) as Map<String, dynamic>;

        // Carrega nomes dos alunos
        _alunoNomes = Map<String, String>.from(
          decodedData['nomes'] as Map? ?? {},
        );

        // Carrega presenças
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

  /// 4. Salva o histórico de presenças e nomes dos alunos no SharedPreferences.
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

  /// 5. Carrega os horários das rodadas do SharedPreferences, definidas na tela de configurações.
  Future<void> _loadRodadasFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // Função auxiliar para converter string "HH:MM" para TimeOfDay
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
            .whereType<TimeOfDay>() // Filtra nulos
            .toList();

        // Ordena os horários
        horarios.sort((a, b) {
          if (a.hour != b.hour) return a.hour.compareTo(b.hour);
          return a.minute.compareTo(b.minute);
        });

        // Cria objetos Rodada
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

  /// 6. Inicia o servidor HTTP e WebSocket e anuncia o serviço via NSD.
  Future<void> _startServer() async {
    try {
      final info = NetworkInfo();
      _serverIp =
          (await info.getWifiIP()) ?? "127.0.0.1"; // Tenta obter o IP do Wi-Fi

      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
      ); // Porta 0 = porta dinâmica
      _port = _server!.port;

      _server!.listen(
        _handleWebSocketRequest,
      ); // Ouve requisições HTTP e faz upgrade para WebSocket

      // --- Encode string para Uint8List ---
      final Map<String, Uint8List?> txtData = {
        'ip': utf8.encode(
          _serverIp,
        ), // Converte a string IP para bytes para o registro NSD
      };

      // Inicia a publicação NSD (Network Service Discovery)
      _registration = await register(
        Service(
          name:
              'SmartPresence-${_serverIp.split('.').last}', // Nome único para o serviço
          type: '_smartpresence._tcp', // Tipo de serviço definido
          port: _port,
          txt: txtData, // Dados extras (IP) para o serviço
        ),
      );
      _log.info('Serviço SmartPresence anunciado na rede local (NSD).');

      if (mounted) {
        setState(() {
          _isServerRunning = true;
          _serverStatus = 'Servidor rodando em: $_serverIp:$_port';
          _isLoading = false; // Terminou de carregar/iniciar
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
          _isLoading = false; // Terminou de carregar/iniciar com erro
        });
      }
      await _stopServer(
        log: false,
      ); // Tenta parar o que foi iniciado, sem log redundante
    }
  }

  /// 7. Inicia o loop de verificação periódica do estado das rodadas (a cada 10 segundos).
  void _startGameLoop() {
    _gameLoopTimer?.cancel(); // Cancela qualquer timer anterior
    _log.info("Iniciando game loop (verificação de rodadas a cada 10s)...");
    _gameLoopTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted || !_isServerRunning) {
        timer
            .cancel(); // Para o timer se o widget não estiver montado ou servidor parado
        _gameLoopTimer = null;
        _log.info("Game loop parado.");
        return;
      }
      _verificarRodadas(); // Chama a função de verificação
    });
  }

  /// 8. Inicia um timer para atualizar a UI a cada segundo, mostrando o tempo restante nas rodadas ativas.
  void _startUiUpdateTimer() {
    _uiUpdateTimer?.cancel(); // Cancela qualquer timer anterior
    _uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel(); // Para o timer se o widget não estiver montado
        return;
      }
      // Otimização: só chama setState se houver rodadas com timer para evitar reconstruções desnecessárias
      if (_rodadaEndTimes.isNotEmpty) {
        setState(
          () {},
        ); // Força a reconstrução da UI para atualizar os timers nos cards
      }
    });
  }

  /// 9. Função centralizada para verificar o estado das rodadas e atualizar a UI.
  void _verificarRodadas() {
    final now = DateTime.now(); // Hora atual com precisão de DateTime
    _log.fine(
      'Verificando rodadas... Hora atual: ${DateFormat('HH:mm:ss').format(now)}',
    );

    bool changed =
        false; // Flag para indicar se houve alguma mudança que exija setState
    for (var rodada in _rodadas) {
      // Cria um DateTime para o início da rodada no dia atual
      final rodadaStartTimeToday = DateTime(
        now.year,
        now.month,
        now.day,
        rodada.horaInicio.hour,
        rodada.horaInicio.minute,
      );
      // Calcula o DateTime para o fim da rodada, adicionando a duração configurada
      final rodadaEndTimeToday = rodadaStartTimeToday.add(
        Duration(minutes: _duracaoRodadaMinutos),
      );

      // Lógica para iniciar a rodada:
      // Se a rodada está aguardando, a hora atual é depois do início E antes do fim
      if (rodada.status == "Aguardando" &&
          now.isAfter(rodadaStartTimeToday) &&
          now.isBefore(rodadaEndTimeToday)) {
        _log.info('--> Hora de INICIAR ${rodada.nome}');
        _startRodada(
          rodada,
          rodadaEndTimeToday,
        ); // Passa o tempo de fim calculado
        changed = true;
      }
      // Lógica para encerrar a rodada:
      // Se a rodada está em andamento e a hora atual é depois ou igual ao fim
      else if (rodada.status == "Em Andamento" &&
          now.isAfter(rodadaEndTimeToday)) {
        _log.info('--> Hora de ENCERRAR ${rodada.nome} (por tempo)');
        _endRodada(rodada);
        changed = true;
      }
      // Caso uma rodada esteja 'Aguardando' mas a hora já passou do seu tempo de encerramento
      // (ex: o app foi aberto tarde e a rodada deveria ter começado e terminado)
      else if (rodada.status == "Aguardando" &&
          now.isAfter(rodadaEndTimeToday)) {
        if (mounted) {
          setState(() {
            // Atualiza diretamente para Encerrada
            rodada.status = "Encerrada";
            rodada.pin = null;
            _rodadaEndTimes.remove(rodada.nome); // Remove do controle de tempo
            _log.info(
              '--> Rodada ${rodada.nome} já expirou ao ser verificada. Marcando como Encerrada.',
            );
          });
        }
        changed = true;
      }
    }
    if (changed && mounted) setState(() {}); // Atualiza a UI se houver mudanças
  }

  /// 10. Gera um PIN aleatório de 4 dígitos.
  String _generatePin() => (1000 + Random().nextInt(9000)).toString();

  /// 11. Verifica se o IP do cliente está na mesma sub-rede do servidor (antifraude).
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
      // Se ambos IPv4, compara primeira 3 partes (/24)
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
      // Para IPv6 ou misto, por ora não aplicar a verificação rígida (aceitar)
      _log.fine(
        'Verificação de sub-rede: Detected non-IPv4; pulando checagem rígida e permitindo (IPv6/Misto).',
      );
      return true;
    } catch (e, s) {
      _log.severe('Erro ao verificar sub-rede', e, s);
      return false; // Falha segura
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

  /// Registra uma tentativa de PIN (cria entrada com timestamp se for a primeira).
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
      // Janela expirou: reinicia contador
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

  /// 12. Inicia uma rodada específica (manual ou automática).
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

        // Calcula o tempo de término: usa o fornecido ou calcula um novo
        final endTime =
            forcedEndTime ??
            DateTime.now().add(Duration(minutes: _duracaoRodadaMinutos));
        _rodadaEndTimes[rodada.nome] =
            endTime; // Armazena para controle da UI do professor

        // Envia mensagem de RODADA_ABERTA para os alunos, incluindo o timestamp do fim da rodada
        _broadcastMessage({
          'command': 'RODADA_ABERTA',
          'nome': rodada.nome,
          'message': 'A ${rodada.nome} está aberta! Insira o PIN.',
          'endTimeMillis':
              endTime.millisecondsSinceEpoch, // Timestamp em milissegundos
        });
      });
    }
    _showSnackBar("Rodada ${rodada.nome} iniciada.", isError: false);
  }

  /// 13. Encerra uma rodada específica (manual ou automática).
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
        _rodadaEndTimes.remove(rodada.nome); // Remove do controle de tempo

        // Marca alunos que não submeteram presença como "Ausente" para esta rodada
        final List<AlunoConectado> currentClients = List.from(
          _clients,
        ); // Cria uma cópia para evitar problemas de iteração
        for (var aluno in currentClients) {
          final matricula = aluno.matricula;
          _presencas[matricula] ??=
              {}; // Garante que o mapa de presença do aluno exista
          if (!_presencas[matricula]!.containsKey(rodada.nome)) {
            _presencas[matricula]![rodada.nome] = 'Ausente';
            _log.info(
              "Aluno ${aluno.nome} ($matricula) marcado como Ausente para ${rodada.nome}.",
            );
          }
        }
        _saveHistorico(); // Salva o histórico após marcar as ausências
      });
    }
    // Envia mensagem de RODADA_FECHADA para os alunos
    _broadcastMessage({'command': 'RODADA_FECHADA', 'nome': rodada.nome});
    _showSnackBar("Rodada ${rodada.nome} encerrada.", isError: false);
  }

  /// 14. Lida com novas solicitações HTTP, fazendo upgrade para WebSocket se for o caso.
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
          cancelOnError: true, // Cancela a inscrição em caso de erro
        );
      } catch (e, s) {
        _log.severe("Erro ao fazer upgrade para WebSocket", e, s);
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.close();
      }
    } else {
      // Rejeita requisições que não são de upgrade para WebSocket
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write(
          'Servidor SmartPresence - Apenas conexões WebSocket são permitidas.',
        )
        ..close();
    }
  }

  /// 15. Lida com mensagens recebidas dos clientes WebSocket.
  void _handleClientMessage(WebSocket socket, dynamic message, String alunoIp) {
    _log.fine('Mensagem recebida de $alunoIp: $message');
    try {
      final data = jsonDecode(message as String);
      // Validação básica do JSON: deve ser um objeto com campo 'command' string
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

      // Tenta encontrar o aluno na lista, se já estiver conectado
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

        // Verifica se matrícula já está conectada por OUTRO socket
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

        // Cria ou atualiza o objeto AlunoConectado
        aluno = AlunoConectado(
          socket: socket,
          nome: nome,
          matricula: matricula,
          ip: alunoIp,
          connectedAt: DateTime.now(),
        );

        if (clientIndex == -1) {
          // Novo cliente
          if (mounted) {
            setState(() {
              _clients.add(aluno!);
              _presencas[matricula] ??=
                  {}; // Garante mapa de presença para o aluno
              _alunoNomes[matricula] = nome; // Salva/Atualiza nome do aluno
            });
            _saveHistorico(); // Salva o novo aluno/nome
            _log.info(
              "Aluno $nome ($matricula) conectado ($alunoIp) e adicionado.",
            );
          }
        } else {
          // Cliente reconectando ou atualizando nome
          if (mounted) {
            setState(() {
              _clients[clientIndex] = aluno!; // Atualiza objeto na lista
              _alunoNomes[matricula] = nome; // Atualiza nome se mudou
            });
            _saveHistorico(); // Salva caso nome tenha mudado
            _log.info(
              "Aluno $nome ($matricula) reconectado/atualizado ($alunoIp).",
            );
          }
        }
        // Confirma ao aluno que a conexão foi bem-sucedida
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

        // Encontra a rodada ativa com o nome fornecido
        final rodadaAtiva = _rodadas.firstWhereOrNull(
          (r) => r.nome == rodadaNome && r.status == "Em Andamento",
        );

        _presencas[matricula] ??= {}; // Garante mapa de presença para o aluno

        // --- ANTIFRAUDE: Rate Limiting de PIN com janela temporal ---
        final attemptKey = "${matricula}_${rodadaNome}";
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
                  'Você excedeu o número máximo de tentativas ($_maxPinAttempts) na janela de ${_pinWindowMillis / 60000} minutos. Tente novamente mais tarde.',
            }),
          );
          return;
        }
        // --- FIM RATE LIMITING ---

        // --- ANTIFRAUDE: Verificação de Sub-rede ---
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
        // --- FIM ANTIFRAUDE ---

        // Verifica se a rodada está ativa e o PIN está correto
        if (rodadaAtiva != null && pinEnviado == rodadaAtiva.pin) {
          _log.info(
            'PIN Correto do aluno ${aluno.nome} ($matricula) para ${rodadaAtiva.nome}',
          );
          _presencas[matricula]![rodadaAtiva.nome] =
              'Presente'; // Registra presença
          _clearPinAttempts(attemptKey); // Limpa tentativas após sucesso
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
          // Incrementa tentativa de PIN (registra timestamp na primeira tentativa)
          _registerPinAttempt(attemptKey);
          _presencas[matricula]![rodadaNome] =
              'Falhou PIN'; // Marca como "Falhou PIN"
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
        // Tenta enviar o erro de volta se o socket estiver aberto
        socket.add(
          jsonEncode({
            'command': 'ERROR',
            'message': 'Erro interno no servidor.',
          }),
        );
      }
    }
  }

  /// 16. Remove um cliente da lista de clientes conectados.
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

  /// 17. Envia uma mensagem JSON para todos os clientes conectados.
  void _broadcastMessage(Map<String, dynamic> message) {
    final jsonMessage = jsonEncode(message);
    _log.fine("Enviando broadcast: $jsonMessage");
    // Cria uma cópia da lista para evitar modificação durante a iteração (se um cliente se desconectar)
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
          _removeClient(client.socket); // Remove clientes com sockets fechados
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
      // Log mais preciso
      _log.info("Broadcast enviado para $sentCount clientes ativos.");
    } else {
      _log.info("Nenhum cliente ativo para receber broadcast.");
    }
  }

  /// 18. Desliga completamente o servidor, incluindo WebSocket, NSD e clientes conectados.
  Future<void> _stopServer({bool log = true}) async {
    if (!_isServerRunning && log) {
      _log.info("Tentativa de parar servidor que já está parado.");
      return;
    }
    if (log) _log.info("Iniciando processo de parada do servidor...");

    _gameLoopTimer?.cancel(); // Cancela o timer de lógica do jogo
    _gameLoopTimer = null;
    _uiUpdateTimer?.cancel(); // Cancela o timer de atualização da UI
    _uiUpdateTimer = null;

    if (_registration != null) {
      try {
        await unregister(_registration!); // Desregistra o serviço NSD
        if (log) _log.info("Serviço NSD cancelado com sucesso.");
      } catch (e, s) {
        if (log) _log.warning("Erro ao cancelar registro NSD", e, s);
      }
      _registration = null;
    }

    if (log) _log.info("Fechando conexões de ${_clients.length} clientes...");
    final List<AlunoConectado> clientsToClose = List.from(
      _clients,
    ); // Copia a lista
    _clients.clear(); // Limpa a lista principal

    // Fecha individualmente cada socket de cliente
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
      await _server?.close(
        force: true,
      ); // force: true para fechar imediatamente
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
        _serverIp = "Aguardando IP..."; // Resetar IP
        _isLoading = false; // Não está mais carregando/tentando iniciar
        _rodadaEndTimes.clear(); // Limpa os tempos de fim de rodada
      });
    }
    if (log) _log.info('Processo de parada do servidor concluído.');
  }

  /// 19. Navega para a tela de histórico de presenças.
  void _navigateToHistorico(BuildContext context) {
    _log.info('Navegando para HistoricoScreen');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistoricoScreen(
          presencas: _presencas,
          alunoNomes: _alunoNomes,
          rodadas: _rodadas, // Passa a lista de rodadas
        ),
      ),
    );
  }

  /// 20. Exibe uma SnackBar na parte inferior da tela.
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

  /// 21. Exporta o histórico de presenças para um arquivo CSV.
  Future<void> _exportarCSV() async {
    _log.info("Iniciando exportação de CSV...");
    var status = await Permission.storage
        .request(); // Solicita permissão de armazenamento
    if (!status.isGranted) {
      _showSnackBar('Permissão de armazenamento negada.', isError: true);
      _log.warning('Permissão de armazenamento negada ao tentar exportar CSV.');
      return;
    }

    List<List<String>> rows = [];
    // Cabeçalho do CSV
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

    List<String> matriculas = _presencas.keys.toList()
      ..sort(); // Ordena as matrículas

    for (var matricula in matriculas) {
      final presencasRodadas = _presencas[matricula]!;
      final nomeAluno = _alunoNomes[matricula] ?? 'Nome Desconhecido';
      for (var rodada in _rodadas) {
        // Itera sobre todas as rodadas configuradas
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

    // Formata o conteúdo CSV com aspas para lidar com vírgulas ou caracteres especiais
    String csvContent = rows
        .map(
          (row) =>
              row.map((item) => '"${item.replaceAll('"', '""')}"').join(','),
        )
        .join('\n');

    try {
      final directory =
          await getDownloadsDirectory(); // Obtém o diretório de downloads
      if (directory == null) {
        throw Exception('Não foi possível acessar o diretório de downloads.');
      }
      final path =
          '${directory.path}/smartpresence_presencas_${DateFormat('yyyyMMdd_HHmmss').format(now)}.csv';
      final file = File(path);
      await file.writeAsString(
        csvContent,
        encoding: utf8,
      ); // Escreve o arquivo com encoding UTF-8
      _showSnackBar('CSV exportado para: ${file.path}');
      _log.info('CSV exportado com sucesso para: ${file.path}');
    } catch (e, s) {
      _showSnackBar('Erro ao exportar CSV: $e', isError: true);
      _log.severe('Erro ao exportar CSV', e, s);
    }
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        if (_isServerRunning) {
          // Exibe um diálogo de confirmação se o servidor estiver rodando
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
        return true; // Permite voltar se o servidor não estiver rodando
      },
      child: Scaffold(
        appBar: AppBar(
          // Garante o botão de voltar quando aplicável
          leading: Navigator.canPop(context) ? const BackButton() : null,

          // Força o título a alinhar à esquerda
          centerTitle: false,

          // Reduz o espaçamento padrão ao redor do título para dar mais espaço
          titleSpacing: NavigationToolbar.kMiddleSpacing / 2,
          // Usa Row + Expanded para maximizar o espaço do título
          title: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Expanded(
                child: const Text(
                  'Painel do Professor',
                  overflow: TextOverflow.ellipsis, // Segurança contra overflow
                  maxLines: 1,
                ),
              ),
            ],
          ),
          actions: [
            // Botão de Histórico
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Ver Histórico',
              onPressed:
                  !_isLoading &&
                      (_presencas.isNotEmpty || _alunoNomes.isNotEmpty)
                  ? () => _navigateToHistorico(context)
                  : null,
            ),
            // Botão de Exportar CSV
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Exportar CSV',
              onPressed:
                  _isServerRunning &&
                      (_presencas.isNotEmpty || _alunoNomes.isNotEmpty)
                  ? _exportarCSV
                  : null,
            ),
            // Botão de Parar/Reiniciar Servidor
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
    // Tela de carregamento
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              _serverStatus,
              style: const TextStyle(fontSize: 16),
            ), // Mostra o status de inicialização
          ],
        ),
      );
    }
    // Tela de erro se não há rodadas configuradas
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
                _serverStatus, // Mostra a mensagem de erro específica
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Colors.black87),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings),
                label: const Text('Configurar Horários'),
                onPressed: () =>
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ConfiguracoesScreen(),
                      ),
                    ).then(
                      (_) => _initializeServer(),
                    ), // Re-inicializa ao retornar das configurações
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

    // Painel principal quando tudo está ok e o servidor está pronto
    return RefreshIndicator(
      onRefresh:
          _initializeServer, // Permite puxar para baixo para reiniciar o servidor
      child: ListView.builder(
        itemCount: _rodadas.length + 1, // +1 para o card da lista de clientes
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildClientList(); // Primeiro item é o card da lista de clientes
          }
          final rodada =
              _rodadas[index - 1]; // Demais itens são os cards das rodadas
          return _buildRodadaCard(rodada);
        },
      ),
    );
  }

  /// Widget que exibe o número de alunos conectados e o IP do servidor (Layout Melhorado).
  Widget _buildClientList() {
    return Card(
      // --- Estilo Consistente com _buildRodadaCard ---
      elevation: 2,
      margin: const EdgeInsets.only(
        bottom: 16,
      ), // Mesma margem dos cards de rodada
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // Mesmas bordas arredondadas
      ),
      // ---------------------------------------------
      child: ExpansionTile(
        // Remove a cor de fundo padrão para usar a do Card
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        // Ícone e Título
        leading: Icon(
          Icons.people_alt_rounded,
          color: Theme.of(context).primaryColor,
          size: 30,
        ), // Ícone um pouco maior
        title: Text(
          "${_clients.length} Alunos Conectados",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ), // Ajuste de fonte
        ),
        // Subtítulo com o IP/Porta
        subtitle: Text(
          _isServerRunning
              ? 'Servidor em: $_serverIp:$_port'
              : 'Servidor parado ou não iniciado.',
          style: const TextStyle(fontSize: 14, color: Colors.black54),
        ),
        // Começa aberto se houver clientes ou se estiver carregando (para mostrar IP)
        initiallyExpanded: _clients.isNotEmpty || _isLoading,
        // Espaçamento interno dos filhos (lista de alunos)
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        tilePadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 8.0,
        ), // Padding do header
        children: _clients.isEmpty
            ? [
                // Mensagem se não houver alunos
                Padding(
                  // Adiciona padding à mensagem
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
            : _clients // Lista de alunos
                  .map(
                    (aluno) => ListTile(
                      dense: true, // ListTile mais compacto
                      leading: const Icon(Icons.person_outline, size: 20),
                      title: Text('${aluno.nome} (${aluno.matricula})'),
                      subtitle: Text('IP: ${aluno.ip}'), // Mostra o IP do aluno
                      contentPadding:
                          EdgeInsets.zero, // Remove padding extra do ListTile
                    ),
                  )
                  .toList(),
      ),
    );
  }

  /// Widget que exibe um card para cada rodada, com status, PIN e botões de ação (Layout Melhorado v2).
  Widget _buildRodadaCard(Rodada rodada) {
    // --- Definição de Cores e Ícones ---
    Color cardColor = Colors.white;
    Color accentColor = Colors.grey[600]!;
    IconData iconData = Icons.schedule; // Ícone padrão
    String statusDisplay = rodada.status; // Texto do status a ser exibido

    // --- Lógica de Tempo Restante ---
    String? timeLeftFormatted; // Formato MM:SS
    DateTime? endTime = _rodadaEndTimes[rodada.nome];
    Duration? remainingDuration;

    if (rodada.status == "Em Andamento") {
      cardColor = Theme.of(
        context,
      ).primaryColor.withAlpha((0.05 * 255).round());
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
          statusDisplay =
              'Encerrando...'; // Indica que o tempo acabou visualmente
          timeLeftFormatted = '00:00';
        }
      }
    } else if (rodada.status == "Encerrada") {
      cardColor = Colors.grey[100]!;
      accentColor = Colors.green[700]!;
      iconData = Icons.check_circle_outline;
    }

    // --- Construção do Card ---
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
        padding: const EdgeInsets.all(16.0), // Padding geral do Card
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // --- Ícone da Rodada (Esquerda) ---
            Icon(iconData, color: accentColor, size: 35),
            const SizedBox(width: 16),

            // --- Informações da Rodada (Centro) ---
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nome da Rodada
                  Text(
                    rodada.nome,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Horário de Início
                  Text(
                    'Início: ${rodada.horaInicio.format(context)}',
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  // --- LAYOUT REVISADO PARA STATUS E TEMPO ---
                  const SizedBox(height: 6), // Espaço extra
                  // Exibe o Tempo Restante se aplicável
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
                          timeLeftFormatted, // Mostra MM:SS
                          style: TextStyle(
                            fontSize: 16,
                            color: accentColor,
                            fontWeight: FontWeight.bold,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  // Exibe o Status em uma linha separada (ou se não houver timer)
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
                  // --- FIM LAYOUT REVISADO ---
                ],
              ),
            ),
            const SizedBox(width: 12), // Espaço antes das ações/PIN
            // --- Ações / PIN (Direita) ---
            Container(
              alignment: Alignment.centerRight,
              child: _buildRodadaActions(
                rodada,
                accentColor,
                timeLeftFormatted,
              ), // Chama o helper
            ),
          ],
        ),
      ),
    );
  }

  /// Helper Widget para construir a seção de ações/PIN à direita do Card.
  Widget _buildRodadaActions(
    Rodada rodada,
    Color accentColor,
    String? timeLeftFormatted,
  ) {
    // Se estiver Aguardando e o servidor rodando, mostra o botão de Iniciar
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
    }
    // Se estiver Em Andamento e o servidor rodando, mostra PIN e botão Encerrar
    else if (_isServerRunning &&
        rodada.status == "Em Andamento" &&
        rodada.pin != null) {
      return Row(
        mainAxisSize: MainAxisSize.min, // Encolhe o Row para caber
        children: [
          // Container estilizado para o PIN
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accentColor.withAlpha(
                (0.1 * 255).round(),
              ), // Fundo bem sutil
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: accentColor.withAlpha((0.5 * 255).round()),
                width: 1,
              ),
            ),
            child: Text(
              rodada.pin!,
              style: TextStyle(
                color: accentColor,
                fontSize: 22, // Ligeiramente maior
                fontWeight: FontWeight.bold,
                letterSpacing: 3, // Mais espaçado
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Botão de Encerrar Manual
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
    }
    // Se Encerrada ou servidor parado, não mostra ações/PIN
    else {
      return const SizedBox(width: 40); // Placeholder para manter alinhamento
    }
  }
}

// Extensão helper para firstWhereOrNull em iteráveis
extension IterableExtension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
