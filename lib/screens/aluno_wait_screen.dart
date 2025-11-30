import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final _log = Logger('AlunoWaitScreen');

class AlunoWaitScreen extends StatefulWidget {
  final WebSocketChannel channel;
  final String nomeAluno;
  final String matriculaAluno;

  const AlunoWaitScreen({
    super.key,
    required this.channel,
    required this.nomeAluno,
    required this.matriculaAluno,
  });

  @override
  State<AlunoWaitScreen> createState() => _AlunoWaitScreenState();
}

class _AlunoWaitScreenState extends State<AlunoWaitScreen> {
  String _statusMessage = 'Entrando na sala...';
  String _currentRodadaName = '';
  bool _showPinInput = false;

  final TextEditingController _pinController = TextEditingController();
  StreamSubscription? _subscription;
  bool _isDisposed = false;

  DateTime? _rodadaEndTime;
  Timer? _rodadaTimer;
  Duration _remainingTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _listenToServer();

    final joinMessage = jsonEncode({
      'command': 'JOIN',
      'nome': widget.nomeAluno,
      'matricula': widget.matriculaAluno,
    });
    widget.channel.sink.add(joinMessage);
    _log.info('Mensagem JOIN enviada para o servidor: $joinMessage');
  }

  @override
  void dispose() {
    _isDisposed = true;
    _subscription?.cancel();
    _rodadaTimer?.cancel();
    _pinController.dispose();
    try {
      widget.channel.sink.close();
    } catch (e) {
      _log.fine('Erro ao fechar channel.sink em dispose (ignorado): $e');
    }
    super.dispose();
  }

  void _listenToServer() {
    _subscription = widget.channel.stream.listen(
      (message) {
        if (_isDisposed) return;

        _log.fine("Mensagem recebida do professor: $message");
        try {
          final data = jsonDecode(message);
          final String command = data['command'];

          setState(() {
            switch (command) {
              case 'JOIN_SUCCESS':
                _statusMessage =
                    "Você está na sala! Aguardando início das rodadas...";
                break;
              case 'RODADA_ABERTA':
                HapticFeedback.heavyImpact();
                _statusMessage =
                    data['message'] ?? 'Rodada iniciada! Insira o PIN.';
                _currentRodadaName = data['nome'] ?? '';
                _showPinInput = true;
                _pinController.clear();

                final int? endTimeMillis = data['endTimeMillis'];
                if (endTimeMillis != null) {
                  _rodadaEndTime = DateTime.fromMillisecondsSinceEpoch(
                    endTimeMillis,
                  );
                  _startRodadaTimer();
                } else {
                  _log.warning('RODADA_ABERTA sem endTimeMillis.');
                }
                break;
              case 'RODADA_FECHADA':
                HapticFeedback.mediumImpact();
                _statusMessage =
                    'A ${data['nome'] ?? 'rodada'} foi encerrada. Aguardando a próxima...';
                _showPinInput = false;
                _pinController.clear();
                _currentRodadaName = '';
                _rodadaEndTime = null;
                _rodadaTimer?.cancel();
                _remainingTime = Duration.zero;
                break;
              case 'PRESENCA_OK':
                HapticFeedback.lightImpact();
                _statusMessage =
                    'Presença confirmada para a ${data['rodada']}!';
                _showPinInput = false;
                _pinController.clear();
                break;
              case 'PRESENCA_FALHA':
                HapticFeedback.vibrate();
                _statusMessage =
                    data['message'] ?? 'PIN incorreto. Tente novamente.';
                _pinController.clear();
                break;
              case 'ERROR':
                _statusMessage =
                    data['message'] ?? 'Ocorreu um erro no servidor.';
                _showPinInput = false;
                _log.warning('Erro recebido do servidor: $_statusMessage');
                break;
              default:
                _log.warning(
                  "Comando desconhecido recebido do servidor: $command",
                );
            }
          });
          _showSnackBar(
            _statusMessage,
            isError: command == 'PRESENCA_FALHA' || command == 'ERROR',
          );
        } catch (e, s) {
          _log.severe("Erro ao processar mensagem JSON do servidor", e, s);
        }
      },
      onDone: () {
        if (_isDisposed) return;
        _log.info("Conexão WebSocket fechada pelo servidor (onDone).");
        if (mounted) {
          setState(() {
            _statusMessage = 'Desconectado pelo professor. Você pode voltar.';
            _showPinInput = false;
            _rodadaEndTime = null;
            _rodadaTimer?.cancel();
            _remainingTime = Duration.zero;
          });
          Navigator.of(context).pop();
        }
        widget.channel.sink.close();
      },
      onError: (error, s) {
        if (_isDisposed) return;
        _log.severe('Erro na conexão WebSocket (onError)', error, s);
        if (mounted) {
          setState(() {
            _statusMessage =
                'Erro de conexão com o servidor. Tente entrar novamente.';
            _showPinInput = false;
            _rodadaEndTime = null;
            _rodadaTimer?.cancel();
            _remainingTime = Duration.zero;
          });
          Navigator.of(context).pop();
        }
        widget.channel.sink.close();
      },
      cancelOnError: true,
    );
    _log.info("AlunoWaitScreen: Iniciou a escuta por mensagens do servidor.");
  }

  void _startRodadaTimer() {
    _rodadaTimer?.cancel();
    if (_rodadaEndTime == null) {
      return;
    }

    _rodadaTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }
      final now = DateTime.now();
      final remaining = _rodadaEndTime!.difference(now);

      if (remaining.isNegative || remaining.inSeconds <= 0) {
        timer.cancel();
        setState(() {
          _remainingTime = Duration.zero;
          if (_currentRodadaName.isNotEmpty) {
            _statusMessage = 'Tempo esgotado para $_currentRodadaName.';
            _currentRodadaName = '';
          }
          _showPinInput = false;
          _pinController.clear();
        });
        HapticFeedback.lightImpact();
        _log.info("Timer da rodada esgotado.");
      } else {
        setState(() {
          _remainingTime = remaining;
        });
      }
    });
    _log.info("Timer da rodada iniciado. Fim em: $_rodadaEndTime");
  }

  void _submitPin() {
    final pin = _pinController.text.trim();
    if (_currentRodadaName.isEmpty) {
      _showSnackBar('Nenhuma rodada ativa para enviar o PIN.', isError: true);
      return;
    }
    if (pin.length != 4) {
      _showSnackBar('O PIN deve ter exatamente 4 dígitos.', isError: true);
      return;
    }
    if (_remainingTime.inSeconds <= 0) {
      _showSnackBar('Tempo esgotado para enviar o PIN.', isError: true);
      return;
    }

    _log.info("Enviando PIN $pin para a rodada $_currentRodadaName");
    widget.channel.sink.add(
      jsonEncode({
        'command': 'SUBMIT_PIN',
        'rodada': _currentRodadaName,
        'pin': pin,
      }),
    );
    setState(() {
      _statusMessage = 'Verificando PIN...';
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _showPinInput ? 'Registre sua Presença!' : 'Sala de Espera',
            style: TextStyle(color: Colors.white),
          ),
          automaticallyImplyLeading: false,
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        backgroundColor: Theme.of(context).primaryColor,
        body: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: _showPinInput
                ? _buildPinInputView(context)
                : _buildWaitingView(context),
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingView(BuildContext context) {
    return Padding(
      key: const ValueKey('waiting'),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            strokeWidth: 3,
          ),
          const SizedBox(height: 32),
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinInputView(BuildContext context) {
    final String timeLeftFormatted =
        '${_remainingTime.inMinutes.toString().padLeft(2, '0')}:${(_remainingTime.inSeconds % 60).toString().padLeft(2, '0')}';

    final bool canSubmit =
        _pinController.text.length == 4 && _remainingTime.inSeconds > 0;
    final bool isInputEnabled = _remainingTime.inSeconds > 0;

    return Padding(
      key: const ValueKey('pinInput'),
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (_currentRodadaName.isNotEmpty && _remainingTime.inSeconds > 0)
            Column(
              children: [
                const Text(
                  'Tempo restante:',
                  style: TextStyle(fontSize: 18, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  timeLeftFormatted,
                  style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          TextField(
            controller: _pinController,
            maxLength: 4,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            autofocus: true,
            style: const TextStyle(
              fontSize: 48,
              letterSpacing: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '----',
              hintStyle: TextStyle(color: Colors.grey[400], letterSpacing: 20),
              filled: true,
              fillColor: Colors.white.withAlpha((0.9 * 255).round()),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Theme.of(context).primaryColorDark,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 20),
            ),
            enabled: isInputEnabled,
            onSubmitted: (_) => _submitPin(),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: canSubmit ? _submitPin : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.white,
              foregroundColor: Theme.of(context).primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Enviar Presença',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
