import 'dart:async';
import 'dart:convert'; // Para JSON
import 'dart:io';
import 'dart:math'; // Para o PIN
import 'package:flutter/material.dart';
import 'package:nsd/nsd.dart'; // Pacote de descoberta
import 'package:shared_preferences/shared_preferences.dart'; // Para persistência
import 'package:network_info_plus/network_info_plus.dart'; // Para descobrir o IP
import 'package:intl/intl.dart'; // Para formatar a data no CSV
import 'configuracoes_screen.dart'; // Para a chave de horário
import 'historico_screen.dart'; // Para navegar para o histórico
import 'package:logging/logging.dart'; // Para logging
import 'package:permission_handler/permission_handler.dart'; // Para permissões
import 'package:path_provider/path_provider.dart'; // Para caminhos de pasta

// 1. IMPORTAR OS MODELOS DA PASTA /models
import '../models/app_models.dart';

final _log = Logger('ProfessorHostScreen');

// --- Modelos de Dados (REMOVIDOS DAQUI, AGORA EM app_models.dart) ---

class ProfessorHostScreen extends StatefulWidget {
  const ProfessorHostScreen({super.key});
  @override
  State<ProfessorHostScreen> createState() => _ProfessorHostScreenState();
}

class _ProfessorHostScreenState extends State<ProfessorHostScreen> {
  // Estado do Servidor
  HttpServer? _server;
  final List<AlunoConectado> _clients = [];
  String _serverStatus = 'Iniciando...';
  bool _isServerRunning = false;
  int _port = 0;
  String _serverIp = "...";

  // Estado da Rede
  Registration? _registration;

  // Estado da Lógica de Jogo
  Timer? _gameLoopTimer;
  List<Rodada> _rodadas = [];
  bool _isLoading = true;

  // --- MUDANÇA NA ESTRUTURA DE DADOS ---
  // Mapa de Presenças: { "matricula": { "Rodada 1": "Presente", ... } }
  Map<String, Map<String, String>> _presencas = {};
  // Mapa de Nomes: { "matricula": "Nome do Aluno" }
  Map<String, String> _alunoNomes = {};

  // Chave única para salvar o histórico
  static const String _historicoKey = 'historico_geral_presencas';

  @override
  void initState() {
    super.initState();
    _initializeServer();
  }

  @override
  void dispose() {
    _stopServer();
    super.dispose();
  }

  // 1. INICIALIZAÇÃO
  Future<void> _initializeServer() async {
    setState(() => _isLoading = true);
    await _loadRodadasFromPrefs(); // Carrega horários (dinâmicos)
    await _loadHistorico(); // Carrega histórico de presenças e nomes
    if (!mounted) return;

    if (_rodadas.isEmpty) {
      setState(() {
        _serverStatus = 'Erro! Programe os horários das rodadas primeiro.';
        _isLoading = false;
      });
      return;
    }
    await _startServer();
    if (_isServerRunning) {
      _startGameLoop();
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // 2. CARREGAR/SALVAR HISTÓRICO (MODIFICADO)
  // Carrega a estrutura JSON complexa (nomes e presenças)
  Future<void> _loadHistorico() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? historicoJson = prefs.getString(_historicoKey);

      if (historicoJson != null && historicoJson.isNotEmpty) {
        final decodedData = jsonDecode(historicoJson) as Map<String, dynamic>;

        // Carrega o mapa de nomes
        _alunoNomes = Map<String, String>.from(
          decodedData['nomes'] as Map? ?? {},
        );

        // Carrega o mapa de presenças
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

  // Salva a estrutura JSON complexa
  Future<void> _saveHistorico() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Cria o objeto complexo para salvar
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
      _log.warning("Erro ao salvar histórico", e, s);
      _showSnackBar("Erro ao salvar histórico.", isError: true);
    }
  }

  // 3. CARREGAR HORÁRIOS (Lógica de Rodadas Dinâmicas)
  Future<void> _loadRodadasFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    TimeOfDay? _timeFromPrefs(String? prefsString) {
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
      _log.warning(
        "Nenhuma lista de horários encontrada em SharedPreferences (HORARIOS_KEY).",
      );
      _rodadas = [];
    } else {
      _log.info("Carregando lista dinâmica de horários...");
      try {
        final List<dynamic> horariosListaStrings = jsonDecode(horariosJson);
        List<TimeOfDay> horarios = horariosListaStrings
            .map((timeStr) => _timeFromPrefs(timeStr as String))
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

  // 4. INICIAR SERVIDOR
  Future<void> _startServer() async {
    setState(() => _serverStatus = 'Iniciando servidor...');
    try {
      final wifiIP = await NetworkInfo().getWifiIP();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _port = _server!.port;
      _serverIp = wifiIP ?? "IP não encontrado";
      _log.info(
        'Servidor iniciado. Escutando na porta $_port. IP da máquina: $_serverIp',
      );

      _server!.listen(_handleWebSocketRequest);

      _registration = await register(
        Service(
          name: 'smartpresence',
          type: '_smartpresence._tcp',
          port: _port,
        ),
      );
      _log.info('Serviço SmartPresence anunciado na rede local (NSD).');

      if (mounted) {
        setState(() {
          _isServerRunning = true;
          _serverStatus = 'Servidor rodando. Aguardando alunos...';
        });
      }
    } catch (e, s) {
      _log.severe('Erro crítico ao iniciar o servidor ou anunciar NSD', e, s);
      if (mounted)
        setState(
          () => _serverStatus = 'Falha ao iniciar. Verifique permissões/rede.',
        );
      await _stopServer();
    }
  }

  // 5. LOOP AUTOMÁTICO
  void _startGameLoop() {
    _gameLoopTimer?.cancel();
    _gameLoopTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted || !_isServerRunning) {
        timer.cancel();
        _gameLoopTimer = null;
        _log.info("Game loop parado.");
        return;
      }
      final now = TimeOfDay.now();
      for (var rodada in _rodadas) {
        if (rodada.status == "Aguardando" &&
            (now.hour > rodada.horaInicio.hour ||
                (now.hour == rodada.horaInicio.hour &&
                    now.minute >= rodada.horaInicio.minute))) {
          _startRodada(rodada);
        }
        int endMinute = rodada.horaInicio.minute + 5;
        int endHour = rodada.horaInicio.hour + (endMinute ~/ 60);
        endMinute %= 60;

        if (rodada.status == "Em Andamento" &&
            (now.hour > endHour ||
                (now.hour == endHour && now.minute >= endMinute))) {
          _endRodada(rodada);
        }
      }
    });
    _log.info("Game loop iniciado.");
  }

  // 6. AÇÕES DAS RODADAS
  String _generatePin() => (1000 + Random().nextInt(9000)).toString();

  bool _isSameSubnet(String ipA, String ipB) {
    try {
      final partsA = ipA.split('.');
      final partsB = ipB.split('.');
      if (partsA.length < 4 || partsB.length < 4) {
        _log.warning(
          'Tentativa de verificação de sub-rede com IPs inválidos: $ipA, $ipB',
        );
        return false;
      }
      final subnetA = partsA.take(3).join('.');
      final subnetB = partsB.take(3).join('.');
      final bool isSame = (subnetA == subnetB);
      _log.fine(
        'Verificando sub-rede: $ipA vs $ipB. Resultado: ${isSame ? "IGUAIS" : "DIFERENTES"}',
      );
      return isSame;
    } catch (e, s) {
      _log.warning('Erro ao comparar sub-redes: $ipA, $ipB', e, s);
      return false;
    }
  }

  void _startRodada(Rodada rodada) {
    _log.info("Iniciando ${rodada.nome} automaticamente!");
    if (mounted) {
      setState(() {
        rodada.status = "Em Andamento";
        rodada.pin = _generatePin();
      });
    }
    _broadcastMessage({
      'command': 'RODADA_ABERTA',
      'nome': rodada.nome,
      'message': 'A ${rodada.nome} está aberta! Insira o PIN.',
    });
  }

  void _endRodada(Rodada rodada) {
    _log.info("Encerrando ${rodada.nome} automaticamente.");
    if (mounted) {
      setState(() {
        rodada.status = "Encerrada";
        rodada.pin = null;
        final List<AlunoConectado> currentClients = List.from(_clients);
        for (var aluno in currentClients) {
          // USA A MATRÍCULA COMO CHAVE
          final matricula = aluno.matricula;
          _presencas[matricula] ??= {}; // Garante mapa
          if (!_presencas[matricula]!.containsKey(rodada.nome)) {
            _presencas[matricula]![rodada.nome] = 'Ausente';
            _log.info(
              "Aluno ${aluno.nome} ($matricula) marcado como Ausente para ${rodada.nome}.",
            );
          }
        }
        _saveHistorico(); // Salva o status de ausência
      });
    }
    _broadcastMessage({'command': 'RODADA_FECHADA', 'nome': rodada.nome});
  }

  // 7. GERENCIAMENTO DE CLIENTES (MODIFICADO)
  void _handleWebSocketRequest(HttpRequest request) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final String clientIp =
          request.connectionInfo?.remoteAddress.address ?? 'IP.Desconhecido';
      _log.info("Nova conexão WebSocket recebida de: $clientIp");

      WebSocketTransformer.upgrade(request)
          .then((websocket) {
            websocket.listen(
              (message) => _handleClientMessage(websocket, message, clientIp),
              onDone: () {
                _log.info("Conexão WebSocket fechada (onDone) de: $clientIp");
                _removeClient(websocket);
              },
              onError: (error, s) {
                _log.warning(
                  'Erro na conexão WebSocket (onError) de: $clientIp',
                  error,
                  s,
                );
                _removeClient(websocket);
              },
              cancelOnError: true,
            );
          })
          .catchError((e, s) {
            _log.warning("Erro ao fazer upgrade para WebSocket", e, s);
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.close();
          });
    } else {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write(
          'Servidor SmartPresence - Apenas conexões WebSocket são permitidas.',
        )
        ..close();
    }
  }

  void _handleClientMessage(WebSocket socket, dynamic message, String alunoIp) {
    _log.fine('Mensagem recebida de $alunoIp: $message');
    try {
      final data = jsonDecode(message as String);
      final String command = data['command'];

      int clientIndex = _clients.indexWhere((c) => c.socket == socket);
      AlunoConectado? aluno = (clientIndex != -1)
          ? _clients[clientIndex]
          : null;

      if (command == 'JOIN') {
        // LÊ OS NOVOS CAMPOS
        final String nome = data['nome'] ?? 'Aluno Desconhecido';
        final String matricula = data['matricula'] ?? 'MATRICULA_INVALIDA';

        if (matricula == 'MATRICULA_INVALIDA') {
          _log.warning(
            "Aluno $nome tentou conectar sem matrícula ($alunoIp). Rejeitando.",
          );
          socket.close(
            WebSocketStatus.policyViolation,
            "Matrícula é obrigatória.",
          );
          return;
        }

        // Verifica se a matrícula já está conectada por outro socket
        int existingMatriculaIndex = _clients.indexWhere(
          (c) => c.matricula == matricula && c.socket != socket,
        );
        if (existingMatriculaIndex != -1) {
          _log.warning(
            "Matrícula $matricula já conectada por outro dispositivo. Desconectando nova tentativa de $alunoIp.",
          );
          socket.close(
            WebSocketStatus.policyViolation,
            "Esta matrícula já está conectada em outro dispositivo.",
          );
          return;
        }

        aluno = AlunoConectado(
          socket: socket,
          nome: nome,
          matricula: matricula, // Salva o objeto AlunoConectado
        );

        if (clientIndex == -1) {
          if (mounted) {
            setState(() {
              _clients.add(aluno!);
              // USA A MATRÍCULA COMO CHAVE
              _presencas[matricula] ??= {};
              _alunoNomes[matricula] = nome; // Salva/Atualiza o nome
            });
            _saveHistorico(); // Salva o novo aluno no histórico
            _log.info(
              "Aluno $nome ($matricula) conectado ($alunoIp) e adicionado à lista.",
            );
          }
        } else {
          // Se reconectou, atualiza o objeto na lista (pode ter mudado nome ou socket)
          if (mounted) {
            setState(() {
              _clients[clientIndex] = aluno!;
              _alunoNomes[matricula] = nome; // Atualiza o nome se mudou
            });
            _saveHistorico(); // Salva caso o nome tenha mudado
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
            "Recebido SUBMIT_PIN de socket não associado a um aluno ($alunoIp). Rejeitando.",
          );
          socket.close(
            WebSocketStatus.policyViolation,
            "Identifique-se com JOIN primeiro.",
          );
          return;
        }

        final String pinEnviado = data['pin'] ?? '';
        final String rodadaNome = data['rodada'] ?? '';
        final rodadaAtiva = _rodadas.firstWhere(
          (r) => r.nome == rodadaNome && r.status == "Em Andamento",
          orElse: () => Rodada(
            nome: 'Inválida',
            horaInicio: TimeOfDay(hour: 0, minute: 0),
          ),
        );

        // USA A MATRÍCULA DO ALUNO COMO CHAVE
        final matricula = aluno.matricula;
        _presencas[matricula] ??= {}; // Garante mapa

        // --- ANTIFRAUDE ---
        final String professorIp = _serverIp;
        if (!_isSameSubnet(professorIp, alunoIp)) {
          _log.warning(
            'REJEITADO (ANTIFRAUDE): Aluno ${aluno.nome} ($matricula) de $alunoIp está fora da sub-rede do professor ($professorIp).',
          );
          _presencas[matricula]![rodadaNome] = 'Falhou PIN';
          _saveHistorico();
          socket.add(
            jsonEncode({
              'command': 'PRESENCA_FALHA',
              'message':
                  'Falha na verificação de rede. Conecte-se ao mesmo Wi-Fi do professor.',
            }),
          );
          return;
        }
        _log.fine(
          'APROVADO (ANTIFRAUDE): Aluno ${aluno.nome} ($matricula) de $alunoIp está na mesma sub-rede.',
        );
        // --- FIM ANTIFRAUDE ---

        if (rodadaAtiva.nome != 'Inválida' && pinEnviado == rodadaAtiva.pin) {
          _log.info(
            'PIN Correto do aluno ${aluno.nome} ($matricula) para $rodadaNome',
          );
          _presencas[matricula]![rodadaNome] = 'Presente';
          _saveHistorico(); // Salva a presença
          socket.add(
            jsonEncode({'command': 'PRESENCA_OK', 'rodada': rodadaNome}),
          );
        } else {
          _log.info(
            'PIN Incorreto do aluno ${aluno.nome} ($matricula) para $rodadaNome',
          );
          _presencas[matricula]![rodadaNome] = 'Falhou PIN';
          _saveHistorico(); // Salva a falha
          socket.add(
            jsonEncode({
              'command': 'PRESENCA_FALHA',
              'message': 'PIN incorreto ou rodada encerrada.',
            }),
          );
        }
      } else {
        _log.warning("Comando desconhecido recebido: $command");
      }
    } catch (e, s) {
      _log.severe('Erro ao processar mensagem JSON ou lógica', e, s);
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
      // Isso pode acontecer se o onDone/onError for chamado múltiplas vezes
      _log.fine(
        "Tentativa de remover um socket desconhecido (pode ser normal).",
      );
    }
  }

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
          // Remove silenciosamente se o socket já estava fechado
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
        _removeClient(client.socket); // Remove se houver erro ao enviar
      }
    }
    if (sentCount > 0 || clientsCopy.isEmpty) {
      _log.info("Broadcast enviado para $sentCount clientes ativos.");
    } else {
      _log.info("Nenhum cliente ativo para receber broadcast.");
    }
  }

  // 8. DESLIGAR O SERVIDOR
  Future<void> _stopServer() async {
    _log.info("Iniciando processo de parada do servidor...");
    _gameLoopTimer?.cancel();
    _gameLoopTimer = null;

    if (_registration != null) {
      try {
        await unregister(_registration!);
        _log.info("Serviço NSD cancelado com sucesso.");
      } catch (e, s) {
        _log.warning("Erro ao cancelar registro NSD", e, s);
      }
      _registration = null;
    }

    _log.info("Fechando conexões de ${_clients.length} clientes...");
    final List<AlunoConectado> clientsToClose = List.from(_clients);
    _clients
        .clear(); // Limpa a lista principal primeiro para evitar race conditions

    for (var client in clientsToClose) {
      try {
        await client.socket.close(
          WebSocketStatus.goingAway,
          "Servidor encerrando.",
        );
        _log.info("Conexão com ${client.nome} (${client.matricula}) fechada.");
      } catch (e, s) {
        _log.warning("Erro ao fechar socket do cliente ${client.nome}", e, s);
      }
    }
    // _clients.clear(); // Movido para cima

    _log.info("Parando o servidor HTTP...");
    try {
      await _server?.close(force: true);
      _log.info("Servidor HTTP/WebSocket parado com sucesso.");
    } catch (e, s) {
      _log.warning("Erro ao fechar servidor HTTP", e, s);
    }
    _server = null;

    if (mounted) {
      setState(() {
        _isServerRunning = false;
        _serverStatus = "Servidor parado.";
        _port = 0;
        _serverIp = "...";
      });
    }
    _log.info('Processo de parada do servidor concluído.');
  }

  // 9. NAVEGAR PARA O HISTÓRICO (MODIFICADO)
  void _navigateToHistorico(BuildContext context) {
    _log.info('Navegando para HistoricoScreen');
    Navigator.push(
      context,
      MaterialPageRoute(
        // Passa os dois mapas para o histórico
        builder: (context) =>
            HistoricoScreen(presencas: _presencas, alunoNomes: _alunoNomes),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // 10. EXPORTAR CSV (MODIFICADO)
  Future<void> _exportarCSV() async {
    _log.info("Iniciando exportação de CSV...");

    var status = await Permission.storage.status;
    if (!status.isGranted) {
      _log.info("Solicitando permissão de armazenamento...");
      status = await Permission.storage.request();
    }
    if (!status.isGranted) {
      _log.warning("Permissão de armazenamento negada.");
      _showSnackBar("Permissão de armazenamento negada.", isError: true);
      return;
    }

    _log.info("Permissão de armazenamento concedida.");

    final hoje = DateFormat('yyyy-MM-dd').format(DateTime.now());
    StringBuffer csvData = StringBuffer();
    // ADICIONA COLUNA MATRÍCULA
    csvData.writeln('Matricula,Nome Aluno,Data,Rodada,Status');

    // Ordena pela matrícula
    List<String> matriculas = _presencas.keys.toList()..sort();

    for (var matricula in matriculas) {
      final presencasRodadas = _presencas[matricula]!;
      // Pega o nome do aluno usando a matrícula
      final nomeAluno = _alunoNomes[matricula] ?? 'Nome Desconhecido';

      for (var rodadaDefinida in _rodadas) {
        final status = presencasRodadas[rodadaDefinida.nome] ?? 'Ausente';
        final nomeFormatado = nomeAluno.contains(',')
            ? '"$nomeAluno"'
            : nomeAluno;
        // Adiciona a matrícula na linha
        csvData.writeln(
          '$matricula,$nomeFormatado,$hoje,${rodadaDefinida.nome},$status',
        );
      }
    }
    _log.fine("Dados CSV gerados:\n$csvData");

    Directory? directory;
    try {
      if (Platform.isAndroid) {
        final directories = await getExternalStorageDirectories(
          type: StorageDirectory.downloads,
        );
        if (directories != null && directories.isNotEmpty) {
          directory = directories.first;
        } else {
          _log.warning(
            "Pasta Downloads não encontrada, usando pasta externa do app.",
          );
          directory = await getExternalStorageDirectory();
        }
      } else if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      }
      if (directory == null) {
        throw Exception("Não foi possível encontrar um diretório para salvar.");
      }
    } catch (e, s) {
      _log.severe("Erro ao obter diretório de armazenamento", e, s);
      _showSnackBar("Erro ao encontrar pasta de Downloads.", isError: true);
      return;
    }

    try {
      final fileName = 'presenca_smartpresence_$hoje.csv';
      final path = '${directory.path}/$fileName';
      final file = File(path);
      await file.writeAsString(csvData.toString());

      _log.info("CSV salvo com sucesso em: $path");
      _showSnackBar("CSV salvo com sucesso em: $path");
    } catch (e, s) {
      _log.severe("Erro ao salvar arquivo CSV", e, s);
      _showSnackBar("Erro ao salvar o arquivo CSV.", isError: true);
    }
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        bool? sair = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Encerrar Sessão?'),
            content: const Text(
              'Deseja realmente parar o servidor e voltar? Os alunos conectados serão desconectados.',
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
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Encerrar'),
              ),
            ],
          ),
        );
        return sair ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Painel do Professor'),
          actions: [
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Ver Histórico de Presença',
              // Valida se há presenças ou nomes para exibir
              onPressed:
                  !_isLoading &&
                      (_presencas.isNotEmpty || _alunoNomes.isNotEmpty)
                  ? () => _navigateToHistorico(context)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Exportar CSV',
              onPressed: _isServerRunning ? _exportarCSV : null,
            ),
          ],
          automaticallyImplyLeading: true,
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Carregando e iniciando servidor...'),
          ],
        ),
      );
    }
    // Mensagem de erro atualizada para rodadas dinâmicas
    if (_rodadas.isEmpty && !_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 60),
              const SizedBox(height: 16),
              const Text(
                'Erro Fatal',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Nenhum horário de rodada foi programado. Por favor, vá até a tela de Configurações para adicionar pelo menos um horário.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings_rounded),
                label: const Text('Ir para Configurações'),
                onPressed: () {
                  // Navegação atualizada para recarregar ao voltar
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (context) => const ConfiguracoesScreen(),
                        ),
                      )
                      .then((_) {
                        // Após voltar das configurações, reinicializa o servidor
                        _log.info(
                          "Voltando das Configurações. Reinicializando o servidor...",
                        );
                        _initializeServer();
                      });
                },
              ),
            ],
          ),
        ),
      );
    }
    // Painel principal
    return RefreshIndicator(
      onRefresh: _initializeServer,
      child: ListView.builder(
        itemCount: _rodadas.length + 1, // +1 para a lista de clientes
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

  // Lista de Clientes Conectados
  Widget _buildClientList() {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 20),
      child: ExpansionTile(
        leading: Icon(Icons.people, color: Theme.of(context).primaryColor),
        title: Text(
          "${_clients.length} Alunos Conectados",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'IP: $_serverIp:$_port',
        ), // Mostra IP para conexão manual
        initiallyExpanded: false,
        children: _clients.isEmpty
            ? [
                const ListTile(
                  dense: true,
                  title: Text("Nenhum aluno conectado no momento."),
                ),
              ]
            : _clients
                  .map(
                    (aluno) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      // Mostra Nome e Matrícula
                      title: Text(aluno.nome),
                      subtitle: Text('Matrícula: ${aluno.matricula}'),
                    ),
                  )
                  .toList(),
      ),
    );
  }

  // Card para cada rodada
  Widget _buildRodadaCard(Rodada rodada) {
    Color cardColor = Colors.white;
    Color accentColor = Colors.grey[600]!;
    IconData iconData = Icons.schedule;
    if (rodada.status == "Em Andamento") {
      cardColor = Theme.of(context).primaryColor.withOpacity(0.05);
      accentColor = Theme.of(context).primaryColor;
      iconData = Icons.play_circle_outline;
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
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(iconData, color: accentColor, size: 30),
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
                    'Início: ${rodada.horaInicio.format(context)}  |  Status: ${rodada.status}',
                    style: const TextStyle(fontSize: 15, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Botão para forçar início
            if (rodada.status == "Aguardando")
              IconButton(
                icon: Icon(
                  Icons.play_arrow_rounded,
                  color: Theme.of(context).primaryColor,
                  size: 30,
                ),
                tooltip: 'Iniciar ${rodada.nome} Manualmente',
                onPressed: () => _startRodada(rodada),
              ),
            // Mostra o PIN
            if (rodada.status == "Em Andamento" && rodada.pin != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  rodada.pin!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
