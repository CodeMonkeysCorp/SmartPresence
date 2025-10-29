import 'dart:async'; // Para Timer
import 'dart:convert'; // Para jsonEncode, jsonDecode
import 'package:flutter/material.dart'; // Para Widgets Flutter
import 'package:flutter/services.dart'; // Para HapticFeedback e FilteringTextInputFormatter
import 'package:logging/logging.dart'; // Para logging
import 'package:web_socket_channel/web_socket_channel.dart'; // Para WebSocketChannel

final _log = Logger('AlunoWaitScreen');

class AlunoWaitScreen extends StatefulWidget {
  final WebSocketChannel
  channel; // Canal de comunicação WebSocket já estabelecido
  final String nomeAluno; // Nome do aluno
  final String matriculaAluno; // Matrícula do aluno

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
  // --- Estados da UI e Lógica ---
  String _statusMessage =
      'Entrando na sala...'; // Mensagem de status para o aluno
  String _currentRodadaName = ''; // Nome da rodada de presença atualmente ativa
  bool _showPinInput = false; // Controla se mostra o campo de PIN

  final TextEditingController _pinController =
      TextEditingController(); // Controller do campo PIN
  StreamSubscription? _subscription; // Para ouvir mensagens do servidor
  bool _isDisposed = false; // Flag para evitar setState após dispose

  // --- Estados para o timer e o fim da rodada ---
  DateTime? _rodadaEndTime; // O momento em que a rodada atual deve terminar
  Timer? _rodadaTimer; // Timer que atualiza o tempo restante a cada segundo
  Duration _remainingTime = Duration.zero; // Duração restante para a rodada

  @override
  void initState() {
    super.initState();
    _listenToServer(); // Começa a escutar por mensagens do servidor

    // Envia a mensagem JOIN para se identificar ao servidor
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
    _isDisposed = true; // Marca como disposed
    _subscription?.cancel(); // Cancela a escuta do stream
    _rodadaTimer?.cancel(); // Cancela o timer da rodada, se estiver ativo
    _pinController.dispose(); // Limpa o controller do TextField
    // O fechamento do widget.channel.sink é feito no onDone/onError do listener ou na tela anterior
    super.dispose();
  }

  /// Inicia a escuta por mensagens do servidor WebSocket.
  void _listenToServer() {
    _subscription = widget.channel.stream.listen(
      (message) {
        if (_isDisposed) return; // Se a tela foi fechada, não faz nada

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
                HapticFeedback.heavyImpact(); // Vibra o celular para avisar
                _statusMessage =
                    data['message'] ?? 'Rodada iniciada! Insira o PIN.';
                _currentRodadaName = data['nome'] ?? '';
                _showPinInput = true;
                _pinController.clear();

                // --- Inicia o timer da rodada ---
                final int? endTimeMillis = data['endTimeMillis'];
                if (endTimeMillis != null) {
                  _rodadaEndTime = DateTime.fromMillisecondsSinceEpoch(
                    endTimeMillis,
                  );
                  _startRodadaTimer(); // Inicia o timer regressivo
                } else {
                  _log.warning('RODADA_ABERTA sem endTimeMillis.');
                }
                break;
              case 'RODADA_FECHADA':
                HapticFeedback.mediumImpact(); // Vibra o celular para avisar
                _statusMessage =
                    'A ${data['nome'] ?? 'rodada'} foi encerrada. Aguardando a próxima...';
                _showPinInput = false;
                _pinController.clear();
                _currentRodadaName = ''; // Limpa a rodada ativa
                _rodadaEndTime = null; // Reinicia o tempo da rodada
                _rodadaTimer?.cancel(); // Cancela o timer da rodada
                _remainingTime = Duration.zero; // Zera o tempo restante
                break;
              case 'PRESENCA_OK':
                HapticFeedback.lightImpact(); // Vibração leve para sucesso
                _statusMessage =
                    'Presença confirmada para a ${data['rodada']}!';
                _showPinInput = false; // Esconde o campo de PIN após sucesso
                _pinController.clear();
                break;
              case 'PRESENCA_FALHA':
                HapticFeedback.vibrate(); // Vibração padrão para falha
                _statusMessage =
                    data['message'] ?? 'PIN incorreto. Tente novamente.';
                // _showPinInput permanece true para permitir nova tentativa
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
          // Mostra SnackBar para feedback rápido ao usuário
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
            _rodadaEndTime = null; // Reinicia o tempo da rodada
            _rodadaTimer?.cancel(); // Cancela o timer da rodada
            _remainingTime = Duration.zero; // Zera o tempo restante
          });
          Navigator.of(context).pop(); // Volta automaticamente
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
            _rodadaEndTime = null; // Reinicia o tempo da rodada
            _rodadaTimer?.cancel(); // Cancela o timer da rodada
            _remainingTime = Duration.zero; // Zera o tempo restante
          });
          Navigator.of(context).pop(); // Volta automaticamente
        }
        widget.channel.sink.close();
      },
      cancelOnError: true,
    );
    _log.info("AlunoWaitScreen: Iniciou a escuta por mensagens do servidor.");
  }

  /// --- Inicia o timer regressivo para a rodada atual ---
  void _startRodadaTimer() {
    _rodadaTimer?.cancel(); // Cancela qualquer timer anterior
    if (_rodadaEndTime == null)
      return; // Não faz nada se não houver tempo de fim definido

    _rodadaTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isDisposed) {
        timer
            .cancel(); // Para o timer se o widget não estiver montado ou estiver sendo descartado
        return;
      }
      final now = DateTime.now();
      final remaining = _rodadaEndTime!.difference(now); // Calcula a diferença

      if (remaining.isNegative || remaining.inSeconds <= 0) {
        timer.cancel(); // Para o timer quando o tempo acaba
        setState(() {
          _remainingTime = Duration.zero; // Zera o tempo
          if (_currentRodadaName.isNotEmpty) {
            _statusMessage = 'Tempo esgotado para $_currentRodadaName.';
            _currentRodadaName = ''; // Rodada acabou
          }
          _showPinInput = false; // Esconde o campo de PIN
          _pinController.clear();
        });
        HapticFeedback.lightImpact(); // Pequena vibração ao terminar
        _log.info("Timer da rodada esgotado.");
      } else {
        setState(() {
          _remainingTime = remaining; // Atualiza o tempo restante
        });
      }
    });
    _log.info("Timer da rodada iniciado. Fim em: $_rodadaEndTime");
  }

  /// Envia o PIN digitado para o servidor.
  void _submitPin() {
    final pin = _pinController.text.trim();
    if (_currentRodadaName.isEmpty) {
      _showSnackBar('Nenhuma rodada ativa para enviar o PIN.', isError: true);
      return;
    }
    if (pin.length != 4) {
      // Valida se o PIN tem 4 dígitos
      _showSnackBar('O PIN deve ter exatamente 4 dígitos.', isError: true);
      return;
    }
    if (_remainingTime.inSeconds <= 0) {
      // Verifica se o tempo ainda não acabou
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
      _statusMessage =
          'Verificando PIN...'; // Atualiza UI para indicar que está verificando
    });
  }

  /// Exibe um SnackBar (notificação temporária) na parte inferior da tela.
  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: const Duration(seconds: 3), // Duração padrão do SnackBar
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Impede o "voltar"
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _showPinInput ? 'Registre sua Presença!' : 'Sala de Espera',
          ),
          automaticallyImplyLeading: false, // Esconde o botão de voltar padrão
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

  /// Widget para a UI de "Aguardando"
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

  /// Widget para a UI de "Inserir PIN"
  Widget _buildPinInputView(BuildContext context) {
    // Formata o tempo restante em MM:SS
    final String timeLeftFormatted =
        '${_remainingTime.inMinutes.toString().padLeft(2, '0')}:${(_remainingTime.inSeconds % 60).toString().padLeft(2, '0')}';

    // Condição para habilitar o botão de enviar e o campo do PIN
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
          // --- Exibe o timer da rodada ---
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
                    fontSize: 64, // Tamanho grande para o timer
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFeatures: [
                      FontFeature.tabularFigures(),
                    ], // Alinha os números
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
              fillColor: Colors.white.withOpacity(0.9),
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
            enabled: isInputEnabled, // Desabilita o input se o tempo acabar
            onSubmitted: (_) => _submitPin(),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: canSubmit
                ? _submitPin
                : null, // Habilita/desabilita botão
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
