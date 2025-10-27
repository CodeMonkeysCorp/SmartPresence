// lib/screens/aluno_join_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:nsd/nsd.dart'; // Pacote de descoberta NSD
import 'package:web_socket_channel/web_socket_channel.dart'; // Pacote WebSocket
import 'aluno_wait_screen.dart'; // Tela seguinte

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

  // Dados do aluno (placeholder - idealmente viria de um login ou config)
  final String _nomeAluno = "Aluno Convidado"; // TODO: Permitir inserir nome
  final TextEditingController _ipController =
      TextEditingController(); // Para IP manual

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
    _ipController.dispose(); // Limpa o controller do TextField
    super.dispose();
  }

  // --- Lógica de Rede ---

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
      // Inicia a descoberta pelo tipo de serviço definido no Professor
      _discovery = await startDiscovery(
        '_smartpresence._tcp',
        autoResolve: false,
      ); // autoResolve: false é geralmente mais estável

      // Escuta por serviços encontrados
      _discovery!.addListener(() {
        if (_discovery != null &&
            _discovery!.services.isNotEmpty &&
            !_isConnecting) {
          // Pega o primeiro serviço encontrado que corresponda ao nome esperado
          final service = _discovery!.services.firstWhere(
            (s) => s.name == 'smartpresence',
            orElse: () => Service(
              name: 'NotFound',
              type: '',
              host: '',
              port: 0,
            ), // Serviço dummy se não encontrar
          );
          if (service.name != 'NotFound') {
            print(
              "Serviço 'smartpresence' encontrado via NSD: ${service.host}:${service.port}",
            );
            _resolveService(service); // Encontrou, tenta resolver e conectar
          }
        }
      });
      print("NSD Discovery iniciado para '_smartpresence._tcp'.");
    } catch (e) {
      print('Erro ao iniciar descoberta NSD: $e');
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
        print("NSD Discovery parado.");
      } catch (e) {
        print("Erro ao parar NSD Discovery (pode ser normal se já parado): $e");
      }
      _discovery = null;
    }
  }

  // 2. Resolve o serviço (obtém IP e Porta) - Necessário se autoResolve=false
  Future<void> _resolveService(Service service) async {
    // Trava para evitar múltiplas conexões
    if (_isConnecting) return;
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
        print(
          'Serviço resolvido: Host: ${resolved.host}, Porta: ${resolved.port}',
        );
        _connectToWebSocket(
          resolved.host!,
          resolved.port!,
        ); // Conecta via WebSocket
      } else {
        throw Exception('Endereço (host) não encontrado para o serviço.');
      }
    } catch (e) {
      print('Erro ao resolver serviço NSD: $e');
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Falha ao obter detalhes da sala. Tente novamente.';
        _statusIcon = Icons.error_outline_rounded;
        _statusColor = Colors.red;
        _isConnecting = false; // Libera trava
      });
      // Opcional: Reiniciar descoberta automaticamente após um tempo
      // Future.delayed(const Duration(seconds: 5), () => _startDiscovery());
    }
  }

  // 3. Conecta ao WebSocket do professor (IP e Porta fornecidos)
  void _connectToWebSocket(String host, int port) {
    final wsUrl = 'ws://$host:$port';
    print('Tentando conectar via WebSocket a: $wsUrl');

    // Atualiza UI para estado "Conectando"
    setState(() {
      _statusMessage = 'Conectando ao professor em $host...';
      _statusIcon = Icons.power_settings_new_rounded; // Ícone de conectar
      _statusColor = Colors.blue;
    });

    try {
      // Cria o canal de comunicação WebSocket
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Espera a conexão ser estabelecida (.ready)
      _channel!.ready
          .then((_) {
            if (!mounted) return; // Se a tela foi fechada antes de conectar

            print("Conexão WebSocket estabelecida com sucesso.");
            setState(() {
              _statusMessage = 'Conectado! Entrando na sala...';
              _statusIcon = Icons.check_circle_outline_rounded;
              _statusColor = Colors.green;
            });

            // Pequeno atraso antes de navegar para a próxima tela
            // Permite que a UI atualize e evita potenciais race conditions
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted && _channel != null) {
                Navigator.pushReplacement(
                  // Substitui a tela atual pela de espera
                  context,
                  MaterialPageRoute(
                    // Passa o canal WebSocket e o nome do aluno para a próxima tela
                    builder: (context) => AlunoWaitScreen(
                      channel: _channel!,
                      nomeAluno: _nomeAluno,
                    ),
                  ),
                );
              }
            });
          })
          .catchError((e) {
            // Erro durante o handshake/conexão WebSocket
            print('Erro durante conexão WebSocket (.ready): $e');
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
    } catch (e) {
      // Erro ao tentar criar o WebSocketChannel (ex: URL inválida)
      print('Erro ao iniciar WebSocketChannel.connect: $e');
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
    await _stopDiscovery(); // Para a busca automática
    _ipController.text = ""; // Limpa campo
    _isConnecting = true; // Ativa trava para conexão manual

    // Mostra o AlertDialog
    final String? ipPort = await showDialog<String>(
      context: context,
      barrierDismissible: false, // Não fecha ao clicar fora
      builder: (context) {
        String? errorText; // Para validação
        // Usa StatefulWidget interno para validar o campo em tempo real
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Conexão Manual'),
              content: TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  hintText: 'Ex: 192.168.1.5:45678',
                  labelText: 'IP:Porta do Professor',
                  errorText: errorText, // Mostra erro de validação
                ),
                keyboardType: TextInputType.url, // Teclado com ':' e '.'
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
                    // Validação simples
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
                      // Se passou, fecha o diálogo retornando o texto
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

    // Se o usuário digitou algo e clicou em Conectar
    if (ipPort != null && ipPort.isNotEmpty) {
      try {
        final parts = ipPort.split(':');
        final host = parts[0];
        final port = int.parse(parts[1]);
        _connectToWebSocket(host, port); // Tenta conectar com os dados manuais
      } catch (e) {
        // Se o formato ainda estiver errado (improvável devido à validação no diálogo)
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0), // Padding geral
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
              if (_statusIcon == Icons.wifi_tethering ||
                  _statusIcon == Icons.network_check_rounded ||
                  _statusIcon == Icons.power_settings_new_rounded)
                const CircularProgressIndicator(),

              // Botão Tentar Novamente (se ocorreu erro)
              if (_statusIcon == Icons.error_outline_rounded)
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

              const SizedBox(height: 20), // Espaço antes do botão manual
              // Botão para Conexão Manual (Plano B)
              // Mostra apenas se não estiver já conectado com sucesso
              if (_statusIcon != Icons.check_circle_outline_rounded)
                TextButton(
                  onPressed: _showManualIPDialog, // Abre o diálogo
                  child: const Text(
                    'Não está encontrando? Tentar conexão manual por IP',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
