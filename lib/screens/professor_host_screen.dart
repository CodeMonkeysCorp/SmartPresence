import 'dart:async';
import 'dart:convert'; // Para JSON
import 'dart:io';
import 'dart:math'; // Para o PIN
import 'package:flutter/material.dart';
import 'package:nsd/nsd.dart'; // Pacote de descoberta
import 'package:web_socket_channel/io.dart'; // Para WebSocket server
import 'package:shared_preferences/shared_preferences.dart'; // Para persistência
import 'package:network_info_plus/network_info_plus.dart'; // Para descobrir o IP
import 'package:intl/intl.dart'; // Para formatar a data no CSV
import 'configuracoes_screen.dart'; // Para as chaves de horário
import 'historico_screen.dart'; // Para navegar para o histórico

// 1. Importar o logging
import 'package:logging/logging.dart';

// 2. Criar a instância do Logger
final _log = Logger('ProfessorHostScreen');

// --- Modelos de Dados ---
class AlunoConectado {
  final WebSocket socket;
  final String nome;
  AlunoConectado({required this.socket, required this.nome});
}

class Rodada {
  final String nome;
  final TimeOfDay horaInicio;
  String status; // "Aguardando", "Em Andamento", "Encerrada"
  String? pin;
  Rodada({
    required this.nome,
    required this.horaInicio,
    this.status = "Aguardando",
    this.pin,
  });
}
// --- Fim dos Modelos ---

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

  // Mapa para armazenar presença (Persistente)
  Map<String, Map<String, String>> _presencas = {};
  static const String _presencasKey =
      'historico_presencas'; // Chave para SharedPreferences

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

  // 1. INICIALIZAÇÃO (Carrega Horários e Presenças Salvas)
  Future<void> _initializeServer() async {
    setState(() => _isLoading = true); // Inicia loading
    await _loadRodadasFromPrefs(); // Carrega horários programados
    await _loadPresencas(); // Carrega histórico de presenças salvo
    if (!mounted) return; // Se a tela foi fechada durante o carregamento

    if (_rodadas.isEmpty) {
      // Se não conseguiu carregar as rodadas, mostra erro e para
      setState(() {
        _serverStatus = 'Erro! Programe os horários das 4 rodadas primeiro.';
        _isLoading = false;
      });
      return;
    }
    // Se carregou rodadas, tenta iniciar o servidor
    await _startServer();
    if (_isServerRunning) {
      _startGameLoop(); // Inicia o timer das rodadas automáticas
    }
    // Garante que o loading termine mesmo se startServer falhar
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // 2. CARREGAR/SALVAR PRESENÇAS (Persistência com SharedPreferences)
  Future<void> _loadPresencas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? presencasJson = prefs.getString(_presencasKey);
      if (presencasJson != null && presencasJson.isNotEmpty) {
        final decodedMap = jsonDecode(presencasJson) as Map<String, dynamic>;
        // Converte o mapa decodificado de volta para a estrutura <String, Map<String, String>>
        _presencas = decodedMap.map(
          (key, value) => MapEntry(key, Map<String, String>.from(value as Map)),
        );
        _log.info(
          "Histórico de presenças carregado com ${decodedMap.length} alunos.",
        );
      } else {
        _log.info("Nenhum histórico de presenças encontrado ou está vazio.");
        _presencas = {}; // Inicia vazio
      }
    } catch (e, s) {
      _log.warning(
        "Erro ao carregar presenças salvas: $e. Iniciando com histórico vazio.",
        e,
        s,
      );
      _presencas = {}; // Reseta em caso de erro de decodificação
    }
    // Atualiza a UI caso o botão de histórico precise ser habilitado/desabilitado
    if (mounted) setState(() {});
  }

  Future<void> _savePresencas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String presencasJson = jsonEncode(_presencas);
      await prefs.setString(_presencasKey, presencasJson);
      _log.info("Histórico de presenças salvo (${_presencas.length} alunos).");
    } catch (e, s) {
      _log.warning("Erro ao salvar presenças", e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar histórico: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 3. CARREGAR HORÁRIOS (Shared Prefs)
  Future<void> _loadRodadasFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    TimeOfDay? getTime(String key) {
      final val = prefs.getString(key);
      if (val == null) return null;
      try {
        final parts = val.split(':');
        if (parts.length != 2) return null;
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
        return TimeOfDay(hour: hour, minute: minute);
      } catch (e) {
        return null;
      }
    }

    final r1Time = getTime(ConfiguracoesScreen.R1_KEY);
    final r2Time = getTime(ConfiguracoesScreen.R2_KEY);
    final r3Time = getTime(ConfiguracoesScreen.R3_KEY);
    final r4Time = getTime(ConfiguracoesScreen.R4_KEY);

    if (r1Time == null || r2Time == null || r3Time == null || r4Time == null) {
      _rodadas =
          []; // Garante que a lista está vazia se horários não estão configurados
    } else {
      _rodadas = [
        Rodada(nome: "Rodada 1", horaInicio: r1Time),
        Rodada(nome: "Rodada 2", horaInicio: r2Time),
        Rodada(nome: "Rodada 3", horaInicio: r3Time),
        Rodada(nome: "Rodada 4", horaInicio: r4Time),
      ];
    }
    if (mounted) setState(() {});
  }

  // 4. INICIAR SERVIDOR (WebSocket + NSD + IP Info)
  Future<void> _startServer() async {
    setState(() => _serverStatus = 'Iniciando servidor...');
    try {
      final wifiIP = await NetworkInfo().getWifiIP(); // Pega IP da máquina host
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
      ); // Ouve em qualquer IP, porta dinâmica
      _port = _server!.port;
      _serverIp =
          wifiIP ?? "IP não encontrado"; // IP para exibir (conexão manual)
      _log.info(
        'Servidor iniciado. Escutando na porta $_port. IP da máquina: $_serverIp',
      );

      _server!.listen(
        _handleWebSocketRequest,
      ); // Começa a ouvir conexões WebSocket

      // Anuncia o serviço na rede local via NSD/Bonjour
      _registration = await register(
        Service(
          name: 'smartpresence', // Nome que os alunos procurarão
          type:
              '_smartpresence._tcp', // Tipo padrão (precisa ser igual no iOS Info.plist)
          port: _port, // Porta onde o servidor WebSocket está rodando
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
      // Opcional: tentar parar o que foi iniciado
      await _stopServer();
    }
  }

  // 5. LOOP AUTOMÁTICO (Timer que controla as rodadas)
  void _startGameLoop() {
    // Cancela timer anterior se existir (segurança)
    _gameLoopTimer?.cancel();
    _gameLoopTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted || !_isServerRunning) {
        // Para o timer se a tela for removida ou servidor parado
        timer.cancel();
        _gameLoopTimer = null;
        _log.info("Game loop parado.");
        return;
      }
      final now = TimeOfDay.now();
      for (var rodada in _rodadas) {
        // Verifica se é hora de iniciar uma rodada que está aguardando
        if (rodada.status == "Aguardando" &&
            (now.hour > rodada.horaInicio.hour ||
                (now.hour == rodada.horaInicio.hour &&
                    now.minute >= rodada.horaInicio.minute))) {
          _startRodada(rodada);
        }
        // Verifica se é hora de encerrar uma rodada em andamento (5 minutos após início)
        // Calcula o minuto de término
        int endMinute = rodada.horaInicio.minute + 5;
        int endHour =
            rodada.horaInicio.hour +
            (endMinute ~/ 60); // Adiciona horas se passar de 59 min
        endMinute %= 60; // Pega o resto (minuto final)

        if (rodada.status == "Em Andamento" &&
            (now.hour > endHour ||
                (now.hour == endHour && now.minute >= endMinute))) {
          _endRodada(rodada);
        }
      }
    });
    _log.info("Game loop iniciado.");
  }

  // 6. AÇÕES DAS RODADAS (Start/End + Lógica de Ausência)
  String _generatePin() => (1000 + Random().nextInt(9000)).toString();

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
        rodada.pin = null; // Limpa o PIN da UI
        // Marca alunos *conectados* que *não* registraram presença como 'Ausente'
        final List<AlunoConectado> currentClients = List.from(
          _clients,
        ); // Cópia segura
        for (var aluno in currentClients) {
          _presencas[aluno.nome] ??= {}; // Garante que o mapa do aluno existe
          // Só marca como ausente se não houver registro para esta rodada específica
          if (!_presencas[aluno.nome]!.containsKey(rodada.nome)) {
            _presencas[aluno.nome]![rodada.nome] = 'Ausente';
            _log.info(
              "Aluno ${aluno.nome} marcado como Ausente para ${rodada.nome} (não respondeu).",
            );
          }
        }
        _savePresencas(); // Salva o status de ausência
      });
    }
    _broadcastMessage({'command': 'RODADA_FECHADA', 'nome': rodada.nome});
  }

  // 7. GERENCIAMENTO DE CLIENTES (WebSocket + Registro de Presença)
  void _handleWebSocketRequest(HttpRequest request) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      WebSocketTransformer.upgrade(request)
          .then((websocket) {
            _log.info("Nova conexão WebSocket recebida.");
            websocket.listen(
              (message) => _handleClientMessage(websocket, message),
              onDone: () {
                _log.info("Conexão WebSocket fechada (onDone).");
                _removeClient(websocket);
              },
              onError: (error, s) {
                _log.warning('Erro na conexão WebSocket (onError)', error, s);
                _removeClient(websocket);
              },
              cancelOnError:
                  true, // Fecha a conexão se ocorrer um erro no stream
            );
          })
          .catchError((e, s) {
            // Erro durante o upgrade da conexão HTTP para WebSocket
            _log.warning("Erro ao fazer upgrade para WebSocket", e, s);
            // Tenta fechar a requisição HTTP de forma limpa
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.close();
          });
    } else {
      // Responde a requisições HTTP normais (não WebSocket)
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write(
          'Servidor SmartPresence - Apenas conexões WebSocket são permitidas.',
        )
        ..close();
    }
  }

  void _handleClientMessage(WebSocket socket, dynamic message) {
    _log.fine('Mensagem recebida: $message'); // Nível 'fine' para verbose
    try {
      final data = jsonDecode(message as String);
      final String command = data['command'];

      // Tenta encontrar o aluno na lista atual de clientes conectados
      int clientIndex = _clients.indexWhere((c) => c.socket == socket);
      AlunoConectado? aluno = (clientIndex != -1)
          ? _clients[clientIndex]
          : null;

      if (command == 'JOIN') {
        final String nome =
            data['nome'] ?? 'Aluno Desconhecido'; // Nome padrão se ausente
        aluno = AlunoConectado(
          socket: socket,
          nome: nome,
        ); // Cria/Atualiza info do aluno

        // Adiciona à lista de clientes ativos se for uma nova conexão
        if (clientIndex == -1) {
          if (mounted) {
            setState(() {
              _clients.add(aluno!);
              _presencas[nome] ??=
                  {}; // Inicializa mapa de presença se for a primeira vez
            });
            _savePresencas(); // Salva caso um novo aluno tenha sido adicionado ao histórico
            _log.info("Aluno $nome conectado e adicionado à lista.");
          }
        } else {
          // Se o cliente já existia, atualiza o objeto na lista (caso o nome mude, etc.)
          if (mounted) {
            setState(() => _clients[clientIndex] = aluno!);
            _log.info("Aluno $nome reconectado/atualizado.");
          }
        }
        // Confirma ao aluno que ele entrou na sala
        socket.add(
          jsonEncode({
            'command': 'JOIN_SUCCESS',
            'message': 'Bem-vindo, $nome!',
          }),
        );
      } else if (command == 'SUBMIT_PIN') {
        // Se não achou o cliente pelo socket (não enviou JOIN?), rejeita
        if (aluno == null) {
          _log.warning(
            "Recebido SUBMIT_PIN de socket não associado a um aluno. Rejeitando.",
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

        _presencas[aluno.nome] ??= {}; // Garante mapa

        if (rodadaAtiva.nome != 'Inválida' && pinEnviado == rodadaAtiva.pin) {
          _log.info('PIN Correto do aluno ${aluno.nome} para $rodadaNome');
          _presencas[aluno.nome]![rodadaNome] = 'Presente';
          _savePresencas(); // Salva a presença
          socket.add(
            jsonEncode({'command': 'PRESENCA_OK', 'rodada': rodadaNome}),
          );
        } else {
          _log.info(
            'PIN Incorreto ou rodada inválida do aluno ${aluno.nome} para $rodadaNome',
          );
          _presencas[aluno.nome]![rodadaNome] = 'Falhou PIN';
          _savePresencas(); // Salva a falha (opcional)
          socket.add(
            jsonEncode({
              'command': 'PRESENCA_FALHA',
              'message': 'PIN incorreto ou rodada encerrada.',
            }),
          );
        }
      } else {
        _log.warning("Comando desconhecido recebido: $command");
        // Opcional: enviar erro de volta ao cliente
      }
    } catch (e, s) {
      _log.severe('Erro ao processar mensagem JSON ou lógica', e, s);
      // Opcional: enviar erro genérico ao cliente se a conexão ainda estiver ativa
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
      _log.warning("Tentativa de remover um socket desconhecido.");
    }
  }

  void _broadcastMessage(Map<String, dynamic> message) {
    final jsonMessage = jsonEncode(message);
    _log.fine("Enviando broadcast: $jsonMessage"); // Nível 'fine'
    final List<AlunoConectado> clientsCopy = List.from(_clients);
    int sentCount = 0;
    for (var client in clientsCopy) {
      try {
        if (client.socket.readyState == WebSocket.open) {
          client.socket.add(jsonMessage);
          sentCount++;
        } else {
          _log.info("Socket para ${client.nome} não estava aberto. Removendo.");
          _removeClient(client.socket); // Remove se o socket já estava fechado
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
    _log.info("Broadcast enviado para $sentCount clientes ativos.");
  }

  // 8. DESLIGAR O SERVIDOR (Processo de Encerramento Limpo)
  Future<void> _stopServer() async {
    _log.info("Iniciando processo de parada do servidor...");
    _gameLoopTimer?.cancel();
    _gameLoopTimer = null;

    // Cancela o registro NSD
    if (_registration != null) {
      try {
        await unregister(_registration!);
        _log.info("Serviço NSD cancelado com sucesso.");
      } catch (e, s) {
        _log.warning("Erro ao cancelar registro NSD", e, s);
      }
      _registration = null;
    }

    // Fecha as conexões dos clientes
    _log.info("Fechando conexões de ${_clients.length} clientes...");
    final List<AlunoConectado> clientsToClose = List.from(_clients);
    for (var client in clientsToClose) {
      try {
        await client.socket.close(
          WebSocketStatus.goingAway,
          "Servidor encerrando.",
        );
        _log.info("Conexão com ${client.nome} fechada.");
      } catch (e, s) {
        _log.warning("Erro ao fechar socket do cliente ${client.nome}", e, s);
      }
    }
    _clients.clear();

    // Fecha o servidor HTTP/WebSocket
    _log.info("Parando o servidor HTTP...");
    try {
      await _server?.close(force: true);
      _log.info("Servidor HTTP/WebSocket parado com sucesso.");
    } catch (e, s) {
      _log.warning("Erro ao fechar servidor HTTP", e, s);
    }
    _server = null;

    // Atualiza a UI
    if (mounted) {
      setState(() {
        _isServerRunning = false;
        _serverStatus = "Servidor parado.";
        _port = 0;
        _serverIp = "...";
        // Mantém _rodadas e _presencas carregados
      });
    }
    _log.info('Processo de parada do servidor concluído.');
  }

  // 9. NAVEGAR PARA O HISTÓRICO
  void _navigateToHistorico(BuildContext context) {
    _log.info('Navegando para HistoricoScreen');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistoricoScreen(presencas: _presencas),
      ),
    );
  }

  // 10. EXPORTAR CSV (Simulado N2)
  void _exportarCSV() {
    final hoje = DateFormat('yyyy-MM-dd').format(DateTime.now());
    StringBuffer csvData = StringBuffer();
    csvData.writeln('Nome Aluno,Data,Rodada,Status'); // Cabeçalho

    // Ordena alunos pelo nome para consistência
    List<String> nomesAlunos = _presencas.keys.toList()..sort();

    for (var nomeAluno in nomesAlunos) {
      final presencasRodadas = _presencas[nomeAluno]!;
      // Usa a lista _rodadas para garantir que todas as rodadas apareçam e na ordem correta
      for (var rodadaDefinida in _rodadas) {
        // Se não há registro, assume Ausente
        final status = presencasRodadas[rodadaDefinida.nome] ?? 'Ausente';
        // Adiciona aspas se o nome do aluno contiver vírgula (pouco provável, mas seguro)
        final nomeFormatado = nomeAluno.contains(',')
            ? '"$nomeAluno"'
            : nomeAluno;
        csvData.writeln('$nomeFormatado,$hoje,${rodadaDefinida.nome},$status');
      }
    }

    _log.info("\n--- INÍCIO CSV SIMULADO (${DateTime.now()}) ---");
    _log.info("DADOS CSV:\n$csvData"); // Log dos dados
    _log.info("--- FIM CSV SIMULADO ---\n");

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CSV simulado gerado no console de depuração.'),
        ),
      );
    }
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    // WillPopScope impede o usuário de voltar usando o botão físico/gesto do Android
    // e força o uso do botão 'X' na AppBar, que chama _stopServer()
    return WillPopScope(
      onWillPop: () async {
        // Mostra um diálogo de confirmação antes de fechar
        bool? sair = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Encerrar Sessão?'),
            content: const Text(
              'Deseja realmente parar o servidor e voltar? Os alunos conectados serão desconectados.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false), // Não sai
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await _stopServer(); // Para o servidor
                  if (mounted)
                    Navigator.of(context).pop(true); // Confirma e sai
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Encerrar'),
              ),
            ],
          ),
        );
        return sair ?? false; // Retorna true só se confirmou
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Painel do Professor'),
          actions: [
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Ver Histórico de Presença',
              onPressed: !_isLoading && _presencas.isNotEmpty
                  ? () => _navigateToHistorico(context)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Exportar CSV (Simulado)',
              onPressed: _isServerRunning ? _exportarCSV : null,
            ),
          ],
          // O leading agora é controlado pelo WillPopScope
          automaticallyImplyLeading: true, // Mostra o botão de voltar padrão
          // O onPressed do botão de voltar padrão vai acionar o onWillPop
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
                'Os horários das 4 rodadas não foram programados. Por favor, programe os horários na tela de Configurações antes de iniciar o painel.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings_rounded),
                label: const Text('Ir para Configurações'),
                onPressed: () {
                  // Navega para as configurações e *substitui* a tela atual
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const ConfiguracoesScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }
    // Painel principal com as rodadas
    return RefreshIndicator(
      // Permite puxar para recarregar (útil se algo travar)
      onRefresh: _initializeServer, // Recarrega tudo
      child: ListView.builder(
        // Adiciona um item extra no início para mostrar os clientes conectados
        itemCount: _rodadas.length + 1, // +1 para a lista de clientes
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          // O primeiro item (index 0) é a lista de clientes
          if (index == 0) {
            return _buildClientList();
          }
          // Os itens seguintes são as rodadas
          final rodada = _rodadas[index - 1]; // Ajusta o índice
          return _buildRodadaCard(rodada);
        },
      ),
    );
  }

  // NOVO WIDGET: Lista de Clientes Conectados
  Widget _buildClientList() {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 20),
      child: ExpansionTile(
        // Usa um ExpansionTile para não ocupar muito espaço
        leading: Icon(Icons.people, color: Theme.of(context).primaryColor),
        title: Text(
          "${_clients.length} Alunos Conectados",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        initiallyExpanded: false, // Começa fechado
        children: _clients.isEmpty
            ? [
                const ListTile(
                  title: Text("Nenhum aluno conectado no momento."),
                ),
              ]
            : _clients
                  .map(
                    (aluno) => ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(aluno.nome),
                      // Opcional: Adicionar ação ao clicar, como ver detalhes ou desconectar
                      // onTap: () { /* ... */ },
                    ),
                  )
                  .toList(),
      ),
    );
  }

  // Card para cada rodada (com botão Forçar Início)
  Widget _buildRodadaCard(Rodada rodada) {
    Color cardColor = Colors.white;
    Color accentColor = Colors.grey[600]!; // Cor padrão cinza
    IconData iconData = Icons.schedule; // Ícone padrão relógio
    if (rodada.status == "Em Andamento") {
      cardColor = Theme.of(
        context,
      ).primaryColor.withOpacity(0.05); // Fundo levemente colorido
      accentColor = Theme.of(context).primaryColor; // Cor do tema
      iconData = Icons.play_circle_outline; // Ícone de play
    } else if (rodada.status == "Encerrada") {
      cardColor = Colors.grey[100]!; // Fundo cinza claro
      accentColor = Colors.green[700]!; // Verde escuro
      iconData = Icons.check_circle_outline; // Ícone de check
    }
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        // Adiciona borda colorida se estiver em andamento
        side: BorderSide(
          color: rodada.status == "Em Andamento"
              ? accentColor
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 12.0,
        ), // Padding ajustado
        child: Row(
          children: [
            Icon(iconData, color: accentColor, size: 30),
            const SizedBox(width: 16), // Espaçamento
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
                  ), // Tamanho ajustado
                  const SizedBox(height: 4),
                  Text(
                    'Início: ${rodada.horaInicio.format(context)}  |  Status: ${rodada.status}',
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black54,
                    ), // Tamanho ajustado
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8), // Espaço antes dos botões/PIN
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
            // Mostra o PIN se Em Andamento
            if (rodada.status == "Em Andamento" && rodada.pin != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ), // Padding ajustado
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
                  ), // Tamanho ajustado
                ),
              ),
          ],
        ),
      ),
    );
  }
}
