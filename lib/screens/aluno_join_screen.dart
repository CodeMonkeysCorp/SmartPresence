// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:nsd/nsd.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';
import 'aluno_wait_screen.dart';

final _log = Logger('AlunoJoinScreen');

class AlunoJoinScreen extends StatefulWidget {
  const AlunoJoinScreen({super.key});

  @override
  State<AlunoJoinScreen> createState() => _AlunoJoinScreenState();
}

class _AlunoJoinScreenState extends State<AlunoJoinScreen> {
  String _statusMessage = 'Procurando sala do professor na rede...';
  IconData _statusIcon = Icons.wifi_tethering_outlined;
  Color _statusColor = Colors.grey[700]!;

  Discovery? _discovery;
  WebSocketChannel? _channel;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _matriculaController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();

  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _startDiscovery();
      }
    });
  }

  @override
  void dispose() {
    _stopDiscovery();
    _channel?.sink.close();
    _ipController.dispose();
    _nomeController.dispose();
    _matriculaController.dispose();
    super.dispose();
  }

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

  Future<void> _startDiscovery() async {
    if (_isConnecting || (_channel != null && _channel?.closeCode == null)) {
      return;
    }

    setState(() {
      _statusMessage = 'Procurando sala do professor na rede...';
      _statusIcon = Icons.wifi_tethering;
      _statusColor = Colors.blueGrey;
    });

    try {
      final permissionStatus = await Permission.location.request();
      if (!permissionStatus.isGranted) {
        _log.warning('Permissão de localização negada pelo usuário.');
        if (mounted) {
          setState(() {
            _statusMessage =
                'Permissão de localização necessária para descobrir a sala. Forneça permissão e tente novamente.';
            _statusIcon = Icons.error_outline_rounded;
            _statusColor = Colors.red;
          });
        }
        return;
      }
    } catch (e, s) {
      _log.warning('Erro ao solicitar permissão de localização', e, s);
    }

    try {
      _discovery = await startDiscovery(
        '_smartpresence._tcp',
        autoResolve: false,
      );

      _discovery!.addListener(() {
        if (_discovery != null &&
            _discovery!.services.isNotEmpty &&
            !_isConnecting) {
          final services = _discovery!.services;
          Service service = services.first;
          try {
            service = services.firstWhere(
              (s) =>
                  s.type == '_smartpresence._tcp' ||
                  (s.name != null &&
                      s.name!.toLowerCase().contains('smartpresence')),
              orElse: () => services.first,
            );
          } catch (_) {
            service = services.first;
          }
          _log.info(
            "Serviço NSD encontrado: ${service.name} -> ${service.host ?? 'host?'}:${service.port}",
          );
          if (_validateStudentFields()) {
            _resolveService(service);
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

  Future<void> _resolveService(Service service) async {
    if (_isConnecting) return;

    if (!_validateStudentFields()) {
      _isConnecting = false;
      return;
    }
    _isConnecting = true;

    await _stopDiscovery();

    setState(() {
      _statusMessage =
          'Sala encontrada (${service.name})! Resolvendo endereço...';
      _statusIcon = Icons.network_check_rounded;
      _statusColor = Colors.orange;
    });

    try {
      final resolved = await resolve(service);
      if (resolved.host != null) {
        _log.info(
          'Serviço resolvido: Host: ${resolved.host}, Porta: ${resolved.port}',
        );
        _connectToWebSocket(resolved.host!, resolved.port!);
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
        _isConnecting = false;
      });
    }
  }

  void _connectToWebSocket(String host, int port) {
    if (!_validateStudentFields()) {
      _isConnecting = false;
      return;
    }

    final wsUrl = 'ws://$host:$port';
    _log.info('Tentando conectar via WebSocket a: $wsUrl');

    setState(() {
      _statusMessage = 'Conectando ao professor em $host...';
      _statusIcon = Icons.power_settings_new_rounded; // Ícone de conectar
      _statusColor = Colors.blue;
    });

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      final ctx = context;
      final nomeCapturado = _nomeController.text.trim();
      final matriculaCapturada = _matriculaController.text.trim();

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
                Navigator.pushReplacement(
                  ctx,
                  MaterialPageRoute(
                    builder: (context) => AlunoWaitScreen(
                      channel: _channel!,
                      nomeAluno: nomeCapturado,
                      matriculaAluno: matriculaCapturada,
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
              _isConnecting = false;
            });
            _channel = null;
          });
    } catch (e, s) {
      _log.severe('Erro ao iniciar WebSocketChannel.connect', e, s);
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Endereço inválido ou erro inesperado.';
        _statusIcon = Icons.error_outline_rounded;
        _statusColor = Colors.red;
        _isConnecting = false;
      });
      _channel = null;
    }
  }

  Future<void> _showManualIPDialog() async {
    if (!_validateStudentFields()) return;

    await _stopDiscovery();
    _ipController.text = "";
    _isConnecting = true;

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
                  onPressed: () => Navigator.of(context).pop(null),
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
                          parts[1].isEmpty) {
                        throw FormatException();
                      }
                      int.parse(parts[1]);
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
        _connectToWebSocket(host, port);
      } catch (e, s) {
        _log.severe("Erro ao processar IP manual", e, s);
        if (mounted) {
          setState(() {
            _statusMessage = 'Formato de IP:PORTA inválido.';
            _statusIcon = Icons.error_outline_rounded;
            _statusColor = Colors.red;
            _isConnecting = false;
          });
        }
      }
    } else {
      _isConnecting = false;
      _startDiscovery();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar na Sala')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
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
                Icon(_statusIcon, size: 80, color: _statusColor),
                const SizedBox(height: 32),
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
                if (_isConnecting ||
                    _statusIcon == Icons.wifi_tethering ||
                    _statusIcon == Icons.network_check_rounded ||
                    _statusIcon == Icons.power_settings_new_rounded)
                  const CircularProgressIndicator(),
                if (_statusIcon == Icons.error_outline_rounded &&
                    !_isConnecting)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar Descoberta Novamente'),
                    onPressed: _startDiscovery,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                if (_statusIcon != Icons.check_circle_outline_rounded)
                  TextButton(
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
