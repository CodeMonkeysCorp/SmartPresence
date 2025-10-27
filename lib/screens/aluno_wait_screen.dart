import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para input formatters
import 'package:logging/logging.dart'; // Para logging
import 'package:web_socket_channel/web_socket_channel.dart'; // Para WebSocket

final _log = Logger('AlunoWaitScreen');

class AlunoWaitScreen extends StatefulWidget {
  final WebSocketChannel channel; // Canal de comunicação recebido
  final String nomeAluno; // Nome do aluno recebido
  // --- CAMPO ADICIONADO ---
  final String matriculaAluno; // MATRÍCULA DO ALUNO

  const AlunoWaitScreen({
    super.key,
    required this.channel,
    required this.nomeAluno,
    // --- PARÂMETRO ADICIONADO ---
    required this.matriculaAluno,
  });

  @override
  State<AlunoWaitScreen> createState() => _AlunoWaitScreenState();
}

class _AlunoWaitScreenState extends State<AlunoWaitScreen> {
  // Estado da UI
  String _statusMessage = 'Entrando na sala...'; // Mensagem inicial
  String _currentRodadaName = ''; // Nome da rodada ativa
  bool _showPinInput = false; // Controla se mostra campo de PIN ou loading
  bool _isDisposed = false; // Flag para evitar setState após dispose

  final TextEditingController _pinController =
      TextEditingController(); // Controller do campo PIN
  StreamSubscription? _subscription; // Para ouvir mensagens do servidor

  @override
  void initState() {
    super.initState();
    _listenToServer(); // Começa a escutar por mensagens do servidor

    // Envia a mensagem JOIN para se identificar ao servidor
    // AGORA INCLUI A MATRÍCULA
    final joinMessage = jsonEncode({
      'command': 'JOIN',
      'nome': widget.nomeAluno,
      'matricula': widget.matriculaAluno, // USA A MATRÍCULA RECEBIDA
    });

    widget.channel.sink.add(joinMessage);
    _log.info('Mensagem JOIN enviada para o servidor: $joinMessage');
  }

  @override
  void dispose() {
    _isDisposed = true; // Marca como disposed
    _subscription?.cancel(); // Cancela a escuta do stream
    // O fechamento do channel.sink é feito no onDone/onError do listener
    _pinController.dispose(); // Limpa o controller do TextField
    super.dispose();
  }

  // --- Lógica de Rede ---

  // Função principal que escuta e processa mensagens do servidor
  void _listenToServer() {
    _subscription = widget.channel.stream.listen(
      (message) {
        if (_isDisposed) return; // Se a tela foi fechada, não faz nada

        _log.fine("Mensagem recebida do professor: $message");
        try {
          // Decodifica a mensagem JSON
          final data = jsonDecode(message);
          final String command = data['command'];

          // Atualiza o estado da UI baseado no comando recebido
          setState(() {
            switch (command) {
              case 'JOIN_SUCCESS': // Servidor confirmou a entrada
                _statusMessage =
                    "Você está na sala! Aguardando início das rodadas...";
                break;
              case 'RODADA_ABERTA': // Servidor iniciou uma rodada
                _statusMessage =
                    data['message'] ?? 'Rodada iniciada! Insira o PIN.';
                _currentRodadaName =
                    data['nome'] ?? ''; // Guarda o nome da rodada
                _showPinInput = true; // Mostra o campo para digitar o PIN
                _pinController.clear(); // Limpa campo anterior
                break;
              case 'RODADA_FECHADA': // Servidor encerrou a rodada
                _statusMessage =
                    'A ${data['nome'] ?? 'rodada'} foi encerrada. Aguardando a próxima...';
                _showPinInput = false; // Esconde o campo de PIN
                _pinController.clear(); // Limpa o campo
                break;
              case 'PRESENCA_OK': // Servidor confirmou o PIN
                _statusMessage =
                    'Presença confirmada para a ${data['rodada']}!';
                _showPinInput = false; // Esconde o campo de PIN
                _pinController.clear();
                // Mostra um feedback rápido de sucesso
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_statusMessage),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
                break;
              case 'PRESENCA_FALHA': // Servidor indicou PIN errado ou falha
                _statusMessage =
                    data['message'] ?? 'PIN incorreto. Tente novamente.';
                // Mostra um feedback rápido de erro
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_statusMessage),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
                // Mantém _showPinInput = true para permitir nova tentativa
                _pinController.clear(); // Limpa o campo para nova digitação
                break;
              case 'ERROR': // Servidor enviou um erro genérico
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
        } catch (e, s) {
          _log.severe("Erro ao processar mensagem JSON do servidor", e, s);
        }
      },
      onDone: () {
        // Conexão fechada pelo servidor
        if (_isDisposed) return;
        _log.info("Conexão WebSocket fechada pelo servidor (onDone).");
        if (mounted) {
          setState(() {
            _statusMessage = 'Desconectado pelo professor. Você pode voltar.';
            _showPinInput = false;
          });
          // Volta automaticamente para a tela anterior
          Navigator.of(context).pop();
        }
        widget.channel.sink.close(); // Fecha o lado do cliente
      },
      onError: (error, s) {
        // Erro na conexão WebSocket
        if (_isDisposed) return;
        _log.severe('Erro na conexão WebSocket (onError)', error, s);
        if (mounted) {
          setState(() {
            _statusMessage =
                'Erro de conexão com o servidor. Tente entrar novamente.';
            _showPinInput = false;
          });
          // Volta automaticamente para a tela anterior
          Navigator.of(context).pop();
        }
        widget.channel.sink.close(); // Fecha o lado do cliente
      },
      cancelOnError: true, // Cancela a subscrição se ocorrer um erro
    );
    _log.info("AlunoWaitScreen: Iniciou a escuta por mensagens do servidor.");
  }

  // Envia o PIN digitado para o servidor
  void _submitPin() {
    final pin = _pinController.text.trim();
    // Valida se o PIN tem 4 dígitos
    if (pin.length == 4) {
      _log.info("Enviando PIN $pin para a rodada $_currentRodadaName");
      // Envia o comando SUBMIT_PIN para o servidor
      widget.channel.sink.add(
        jsonEncode({
          'command': 'SUBMIT_PIN',
          'rodada': _currentRodadaName, // Nome da rodada atual
          'pin': pin, // PIN digitado
          // A matrícula/nome não precisam ser enviados aqui,
          // pois o servidor já associou este 'socket' a um aluno
        }),
      );
      // Atualiza UI para indicar que está verificando
      setState(() {
        _statusMessage = 'Verificando PIN...';
        // Não esconde o input ainda, espera a resposta do servidor
      });
    } else {
      // Mostra erro se o PIN não tiver 4 dígitos
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O PIN deve ter exatamente 4 dígitos.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // --- Construção da UI ---
  @override
  Widget build(BuildContext context) {
    // WillPopScope impede o usuário de voltar usando o botão físico/gesto
    return WillPopScope(
      onWillPop: () async => false, // Retorna false para impedir o "voltar"
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _showPinInput ? 'Registre sua Presença!' : 'Sala de Espera',
          ),
          automaticallyImplyLeading: false,
          // UI ATUALIZADA (SUGESTÃO ANTERIOR)
          backgroundColor: Theme.of(context).primaryColor, // Cor do fundo
          foregroundColor: Colors.white, // Cor do título e ícones
          elevation: 0, // Sem sombra, para integrar
        ),
        // Fundo na cor primária do tema
        backgroundColor: Theme.of(context).primaryColor,
        body: Center(
          // AnimatedSwitcher faz a transição suave
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300), // Duração da animação
            transitionBuilder: (Widget child, Animation<double> animation) {
              // Animação de Fade
              return FadeTransition(opacity: animation, child: child);
            },
            // Decide qual UI mostrar
            child: _showPinInput
                ? _buildPinInputView(context) // Mostra campo de PIN
                : _buildWaitingView(context), // Mostra indicador de espera
          ),
        ),
      ),
    );
  }

  // Widget para a UI de "Aguardando"
  Widget _buildWaitingView(BuildContext context) {
    // Usa uma Key para o AnimatedSwitcher identificar a mudança
    return Padding(
      key: const ValueKey('waiting'),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Indicador de progresso circular
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              Colors.white,
            ), // Cor branca
            strokeWidth: 3, // Espessura
          ),
          const SizedBox(height: 32),
          // Mensagem de status
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

  // Widget para a UI de "Inserir PIN"
  Widget _buildPinInputView(BuildContext context) {
    // Usa uma Key para o AnimatedSwitcher identificar a mudança
    return Padding(
      key: const ValueKey('pinInput'),
      padding: const EdgeInsets.all(32.0), // Padding maior
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment:
            CrossAxisAlignment.stretch, // Estica os filhos na largura
        children: [
          // Mensagem de instrução (ex: "Rodada X aberta, insira o PIN")
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          // Campo de Texto para o PIN
          TextField(
            controller: _pinController,
            maxLength: 4, // Limita a 4 dígitos
            keyboardType: TextInputType.number, // Teclado numérico
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ], // Permite apenas dígitos
            textAlign: TextAlign.center, // Centraliza o texto
            autofocus: true, // Abre o teclado automaticamente
            style: const TextStyle(
              // Estilo do texto digitado (grande, espaçado)
              fontSize: 48,
              letterSpacing: 20, // Espaçamento entre dígitos
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            decoration: InputDecoration(
              counterText: '', // Esconde o contador de caracteres (ex: 0/4)
              hintText: '----', // Placeholder
              hintStyle: TextStyle(
                color: Colors.grey[400],
                letterSpacing: 20,
              ), // Estilo do placeholder
              filled: true, // Habilita cor de fundo
              fillColor: Colors.white.withOpacity(
                0.9,
              ), // Fundo branco semi-transparente
              border: OutlineInputBorder(
                // Bordas arredondadas sem linha visível
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                // Borda quando focado
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Theme.of(context).primaryColorDark,
                  width: 2,
                ), // Borda mais escura
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 20,
              ), // Padding vertical
            ),
          ),
          const SizedBox(height: 24),
          // Botão de Enviar Presença
          ElevatedButton(
            onPressed: _submitPin, // Chama a função para enviar o PIN
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16), // Botão alto
              backgroundColor: Colors.white, // Fundo branco
              foregroundColor: Theme.of(
                context,
              ).primaryColor, // Texto na cor do tema
              shape: RoundedRectangleBorder(
                // Bordas arredondadas
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
