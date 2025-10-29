import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:nsd/nsd.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'aluno_wait_screen.dart';

final _log = Logger('AlunoJoinScreen');

class AlunoJoinScreen extends StatefulWidget {
  const AlunoJoinScreen({super.key});

  @override
  State<AlunoJoinScreen> createState() => _AlunoJoinScreenState();
}

class _AlunoJoinScreenState extends State<AlunoJoinScreen> {
  // Variáveis de estado da UI
  String _statusMessage = 'Procurando sala do professor na rede...';
  IconData _statusIcon = Icons.wifi_tethering_outlined; // Ícone inicial
  Color _statusColor = Colors.grey[700]!;

  // Objetos de rede
  Discovery? _discovery; // Objeto de descoberta NSD
  WebSocketChannel? _channel; // Canal de comunicação WebSocket

  // --- CONTROLES PARA DADOS DO ALUNO ---
  final _formKey = GlobalKey<FormState>(); // Chave para validar o formulário
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _matriculaController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();

  // "Trava" para evitar múltiplas tentativas de conexão simultâneas
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    // Atraso inicial para a UI carregar antes de iniciar a descoberta
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        // Verifica se a tela ainda existe
        _startDiscovery();
      }
    });
  }

  @override
  void dispose() {
    _stopDiscovery(); // Garante que a descoberta pare ao sair
    _channel?.sink.close(); // Fecha o canal WebSocket se estiver aberto
    _ipController.dispose();
    _nomeController.dispose(); // Limpa o controller
    _matriculaController.dispose(); // Limpa o controller
    super.dispose();
  }

  // --- Lógica de Rede ---

  // Valida os campos de nome e matrícula
  bool _validateStudentFields() {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      _log.warning('Validação falhou. Nome ou Matrícula estão vazios.');
      setState(() {
        _statusMessage = 'Por favor, preencha seu Nome e Matrícula.';
        _statusIcon = Icons.error_outline_rounded;
        _statusColor = Colors.red;
      });
      return false;
    }
    return true;
  }

  // 1. Inicia a procura (NSD) pelo serviço do professor
  Future<void> _startDiscovery() async {
    // Não inicia se já estiver tentando conectar ou já conectado
    if (_isConnecting || (_channel != null && _channel?.closeCode == null))
      return;

    // Atualiza UI para estado "Procurando"
    setState(() {
      _statusMessage = 'Procurando sala do professor na rede...';
      _statusIcon = Icons.wifi_tethering;
      _statusColor = Colors.blueGrey;
    });

    try {
      _discovery = await startDiscovery(
        '_smartpresence._tcp',
        autoResolve: false,
      );

      _discovery!.addListener(() {
        if (_discovery != null &&
            _discovery!.services.isNotEmpty &&
            !_isConnecting) {
          final service = _discovery!.services.firstWhere(
            (s) => s.name == 'smartpresence',
            orElse: () => Service(
              name: 'NotFound',
              type: '',
              host: '',
              port: 0,
            ), // Serviço dummy
          );
          if (service.name != 'NotFound') {
            _log.info(
              "Serviço 'smartpresence' encontrado via NSD: ${service.host}:${service.port}",
            );
            // ANTES de resolver, valida os campos
            if (_validateStudentFields()) {
              _resolveService(service); // Encontrou, tenta resolver e conectar
            }
          }
        }
      });
      _log.info("NSD Discovery iniciado para '_smartpresence._tcp'.");
    } catch (e, s) {
      _log.severe('Erro ao iniciar descoberta NSD', e, s);
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Erro ao iniciar busca na rede. Verifique o Wi-Fi e permissões.';
        _statusIcon = Icons.error_outline_rounded;
        _statusColor = Colors.red;
      });
    }
  }

  // Para a procura NSD
  Future<void> _stopDiscovery() async {
    if (_discovery != null) {
      try {
        await stopDiscovery(_discovery!);
        _log.info("NSD Discovery parado.");
      } catch (e, s) {
        _log.warning(
          "Erro ao parar NSD Discovery (pode ser normal se já parado)",
          e,
          s,
        );
      }
      _discovery = null;
    }
  }

  // 2. Resolve o serviço (obtém IP e Porta)
  Future<void> _resolveService(Service service) async {
    // Trava para evitar múltiplas conexões
    if (_isConnecting) return;

    // Valida novamente (segurança)
    if (!_validateStudentFields()) {
      _isConnecting = false;
      return;
    }
    _isConnecting = true;

    await _stopDiscovery(); // Para de procurar outros

    setState(() {
      _statusMessage =
          'Sala encontrada (${service.name})! Resolvendo endereço...';
      _statusIcon = Icons.network_check_rounded;
      _statusColor = Colors.orange;
    });

    try {
      final resolved = await resolve(
        service,
      ); // Resolve o serviço para obter IP/Host
      if (resolved.host != null) {
        _log.info(
          'Serviço resolvido: Host: ${resolved.host}, Porta: ${resolved.port}',
        );
        _connectToWebSocket(
          resolved.host!,
          resolved.port!,
        ); // Conecta via WebSocket
      } else {
        throw Exception('Endereço (host) não encontrado para o serviço.');
      }
    } catch (e, s) {
      _log.severe('Erro ao resolver serviço NSD', e, s);
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Falha ao obter detalhes da sala. Tente novamente.';
        _statusIcon = Icons.error_outline_rounded;
        _statusColor = Colors.red;
        _isConnecting = false; // Libera trava
      });
    }
  }

  // 3. Conecta ao WebSocket do professor (IP e Porta fornecidos)
  void _connectToWebSocket(String host, int port) {
    // Valida os campos ANTES de conectar
    if (!_validateStudentFields()) {
      _isConnecting = false;
      return;
    }

    final wsUrl = '$host:$port';
    _log.info('Tentando conectar via WebSocket a: $wsUrl');

    setState(() {
      _statusMessage = 'Conectando ao professor em $host...';
      _statusIcon = Icons.power_settings_new_rounded; // Ícone de conectar
      _statusColor = Colors.blue;
    });

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _channel!.ready
          .then((_) {
            if (!mounted) return;

            _log.info("Conexão WebSocket estabelecida com sucesso.");
            setState(() {
              _statusMessage = 'Conectado! Entrando na sala...';
              _statusIcon = Icons.check_circle_outline_rounded;
              _statusColor = Colors.green;
            });

            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted && _channel != null) {
                // Pega os dados dos controllers
                final nome = _nomeController.text.trim();
                final matricula = _matriculaController.text.trim();

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    // Passa o canal, nome e matrícula para a próxima tela
                    builder: (context) => AlunoWaitScreen(
                      channel: _channel!,
                      nomeAluno: nome,
                      matriculaAluno: matricula, // NOVO
                    ),
                  ),
                );
              }
            });
          })
          .catchError((e, s) {
            _log.severe('Erro durante conexão WebSocket (.ready)', e, s);
            if (!mounted) return;
            setState(() {
              _statusMessage =
                  'Falha ao conectar. Verifique o IP/Porta ou a rede.';
              _statusIcon = Icons.error_outline_rounded;
              _statusColor = Colors.red;
              _isConnecting = false; // Libera trava
            });
            _channel = null; // Limpa o canal
          });
    } catch (e, s) {
      _log.severe('Erro ao iniciar WebSocketChannel.connect', e, s);
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Endereço inválido ou erro inesperado.';
        _statusIcon = Icons.error_outline_rounded;
        _statusColor = Colors.red;
        _isConnecting = false; // Libera trava
      });
      _channel = null;
    }
  }

  // --- Diálogo para Inserção Manual de IP ---
  Future<void> _showManualIPDialog() async {
    // Valida Nome e Matrícula ANTES de abrir o diálogo de IP
    if (!_validateStudentFields()) return;

    await _stopDiscovery(); // Para a busca automática
    _ipController.text = ""; // Limpa campo
    _isConnecting = true; // Ativa trava para conexão manual

    final String? ipPort = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Conexão Manual'),
              content: TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  hintText: 'Ex: 192.168.1.5:45678',
                  labelText: 'IP:Porta do Professor',
                  errorText: errorText,
                ),
                keyboardType: TextInputType.url,
                autofocus: true,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(null), // Retorna null (cancelou)
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final text = _ipController.text.trim();
                    if (text.isEmpty || !text.contains(':')) {
                      setDialogState(
                        () => errorText = 'Formato inválido (ex: IP:PORTA)',
                      );
                      return;
                    }
                    try {
                      final parts = text.split(':');
                      if (parts.length != 2 ||
                          parts[0].isEmpty ||
                          parts[1].isEmpty)
                        throw FormatException();
                      int.parse(parts[1]); // Tenta converter porta para int
                      Navigator.of(context).pop(text);
                    } catch (e) {
                      setDialogState(() => errorText = 'IP ou Porta inválido');
                    }
                  },
                  child: const Text('Conectar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ipPort != null && ipPort.isNotEmpty) {
      try {
        final parts = ipPort.split(':');
        final host = parts[0];
        final port = int.parse(parts[1]);
        _connectToWebSocket(host, port); // Tenta conectar com os dados manuais
      } catch (e, s) {
        _log.severe("Erro ao processar IP manual", e, s);
        if (mounted) {
          setState(() {
            _statusMessage = 'Formato de IP:PORTA inválido.';
            _statusIcon = Icons.error_outline_rounded;
            _statusColor = Colors.red;
            _isConnecting = false; // Libera trava
          });
        }
      }
    } else {
      // Se o usuário cancelou o diálogo, reinicia a descoberta automática
      _isConnecting = false; // Libera trava
      _startDiscovery();
    }
  }

  // --- Construção da UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar na Sala')),
      body: SingleChildScrollView(
        // Permite rolagem se o teclado aparecer
        child: Padding(
          padding: const EdgeInsets.all(24.0), // Padding geral
          child: Form(
            // Adiciona o Form para validação
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nomeController,
                  decoration: InputDecoration(
                    labelText: 'Nome Completo',
                    hintText: 'Seu nome',
                    icon: Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Por favor, insira seu nome.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _matriculaController,
                  decoration: InputDecoration(
                    labelText: 'Matrícula',
                    hintText: 'Sua matrícula (ID)',
                    icon: Icon(Icons.badge),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Por favor, insira sua matrícula.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 48),

                // Ícone de Status
                Icon(_statusIcon, size: 80, color: _statusColor),
                const SizedBox(height: 32),

                // Mensagem de Status
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: _statusColor,
                  ),
                ),
                const SizedBox(height: 40),

                // Indicador de Progresso (se procurando ou conectando)
                if (_isConnecting ||
                    _statusIcon == Icons.wifi_tethering ||
                    _statusIcon == Icons.network_check_rounded ||
                    _statusIcon == Icons.power_settings_new_rounded)
                  const CircularProgressIndicator(),

                // Botão Tentar Novamente (se ocorreu erro)
                if (_statusIcon == Icons.error_outline_rounded &&
                    !_isConnecting)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar Descoberta Novamente'),
                    onPressed: _startDiscovery, // Reinicia a busca automática
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),

                const SizedBox(height: 20),
                // Botão para Conexão Manual (Plano B)
                if (_statusIcon != Icons.check_circle_outline_rounded)
                  TextButton(
                    // Desabilita o botão se já estiver conectando
                    onPressed: _isConnecting ? null : _showManualIPDialog,
                    child: const Text(
                      'Não está encontrando? Tentar conexão manual por IP',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
