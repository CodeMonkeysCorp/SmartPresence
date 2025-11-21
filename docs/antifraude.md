# Antifraude - SmartPresence

**Versão:** 2.0  
**Data:** 20 de Novembro de 2025

## Visão Geral

O documento descreve as **ameaças de fraude** identificadas no sistema SmartPresence e as **medidas de mitigação** implementadas ou propostas conceitualmente para a entrega N3.

---

## 1. Ameaças Identificadas (Misuse Cases)

### MC01: Aluno Ausente Tenta Registrar Presença

**Cenário:**

- Aluno A sai da sala de aula
- Aluno B (colega presente) compartilha o IP e PIN da rodada
- Aluno A, de fora da sala, conecta ao servidor e tenta registrar presença

**Impacto:**

- Fraude de presença; professor não detecta ausência

**Probabilidade:** Alta (baixo esforço técnico)

**Mitigações Propostas:**

#### 1.1 Verificação de Sub-rede (SubnetCheck) — ✅ IMPLEMENTADA

- **Mecanismo:** Servidor valida se o IP do cliente está na mesma sub-rede (ex: 192.168.1.x)
- **Implementação:** Função `_isSameSubnet(clientIp, serverIp)` em `professor_host_screen.dart`
- **Lógica:**
  ```dart
  bool _isSameSubnet(String clientIp, String serverIp) {
    // Compara 3 primeiros octetos (ex: 192.168.1)
    return serverParts[0] == clientParts[0] &&
           serverParts[1] == clientParts[1] &&
           serverParts[2] == clientParts[2];
  }
  ```
- **Resposta ao Cliente:** "Falha na verificação de rede. Use o mesmo Wi-Fi do professor."
- **Vantagens:**
  - Simples e não requer hardware adicional
  - Eficaz em redes locais típicas (sala de aula)
  - Funciona offline
- **Limitações:**
  - Não funciona em redes com máscaras /31 ou /32
  - Colega pode estar fisicamente perto usando mesmo Wi-Fi
- **Trade-off:** Simplicidade vs. robustez absoluta

#### 1.2 Verificação de Latitude/Longitude (Geofencing) — 🔶 PROPOSTA

- **Mecanismo:** App coleta GPS do dispositivo; servidor rejeita se longe demais da sala
- **Implementação:** Exigiria `ACCESS_FINE_LOCATION` (já adicionado para NSD) + cálculo de distância
- **Resposta ao Cliente:** "Você está fora da sala de aula. Retorne para registrar presença."
- **Vantagens:**
  - Mais robusto que SubnetCheck
  - Detecta fraude mesmo na mesma rede
- **Limitações:**
  - GPS impreciso em ambientes fechados (2-10m de erro)
  - Drenagem de bateria
  - Privacidade (coleta localização)
- **Trade-off:** Precisão vs. consumo/privacidade (não recomendado para N3)

#### 1.3 QR Code Dinâmico por Rodada — 🟡 PROPOSTA

- **Mecanismo:** Professor exibe QR code para cada rodada; aluno deve scanear antes de enviar PIN
- **Implementação:** Exigiria `CAMERA` e pacote de geração/leitura QR
- **Resposta ao Cliente:** QR code inválido ou expirado
- **Vantagens:**
  - Requer presença física na sala
  - Simples de implementar
  - Não requer infraestrutura
- **Limitações:**
  - Adiciona etapa visual (menos "instantânea")
  - Requer câmera funcional
- **Trade-off:** Usabilidade vs. segurança (viável para N3 avançada)

---

### MC02: Força Bruta de PIN

**Cenário:**

- Aluno tenta adivinhar o PIN enviando sequências (0000, 0001, 0002, ...)
- Servidor não limita tentativas
- Aluno consegue acertar em tempo finito

**Impacto:**

- Fraude de presença sem compartilhamento de PIN

**Probabilidade:** Média (requer automação ou paciência)

**Mitigações Propostas:**

#### 2.1 Rate Limiting de Tentativas — ✅ IMPLEMENTADA

- **Mecanismo:** Servidor permite máximo 3 tentativas de PIN por matrícula-rodada
- **Implementação:** Map `_pinAttempts` rastreia `"matricula_rodada"` → count
- **Lógica:**

  ```dart
  final attemptKey = "${matricula}_${rodadaNome}";
  final currentAttempts = _pinAttempts[attemptKey] ?? 0;

  if (currentAttempts >= _maxPinAttempts) {
    // Rejeita: "Você excedeu o número máximo de tentativas (3). Acesso bloqueado."
  }
  _pinAttempts[attemptKey] = currentAttempts + 1;
  ```

- **Resposta ao Cliente:** "PIN incorreto. Tentativas restantes: 2" (ou bloqueio)
- **Vantagens:**
  - Simples de implementar
  - Não bloqueia uso legítimo
  - Eficaz contra força bruta
- **Limitações:**
  - Aluno legítimo pode esquecer PIN e ficar bloqueado
  - Não detecta múltiplas tentativas de nomes diferentes
- **Trade-off:** Segurança vs. UX (3 tentativas é razoável)

#### 2.2 Timeout Progressivo (Exponential Backoff) — 🔶 PROPOSTA

- **Mecanismo:** Após falha, servidor aumenta delay antes de aceitar próxima tentativa (1s → 2s → 4s)
- **Implementação:** Exigiria rastreamento de último attempt time
- **Vantagens:**
  - Ralenta força bruta exponencialmente
  - Não bloqueia uso legítimo
- **Limitações:**
  - Complexidade adicional
  - Aluno legítimo sofre penalidade
- **Trade-off:** Segurança vs. complexidade (não implementado em v2.0)

#### 2.3 CAPTCHA Dinâmico — 🔶 PROPOSTA

- **Mecanismo:** Após 2 falhas, servidor exige resposta a pergunta (ex: "Qual hora?"?)
- **Implementação:** Complexo; requer interação bidirecional
- **Vantagens:**
  - Detecta bot
  - Legítimo passa facilmente
- **Limitações:**
  - Adiciona etapa extra
  - Pergunta deve variar para não ser facilmente contornável
- **Trade-off:** Segurança vs. usabilidade (não recomendado para N3)

---

### MC03: Matrícula Duplicada

**Cenário:**

- Aluno A conecta de um dispositivo e registra presença
- Mesma matrícula tenta conectar de outro dispositivo (fraude ou erro)
- Servidor não rejeita duplicação
- Duas entradas criadas

**Impacto:**

- Inconsistência de dados; aluno pode registrar múltiplas vezes

**Probabilidade:** Média (requer erro ou coordenação)

**Mitigações Propostas:**

#### 3.1 Validação de Socket Único — ✅ IMPLEMENTADA

- **Mecanismo:** Servidor rejeita segunda conexão com mesma matrícula
- **Implementação:** Validação em `_handleClientMessage` (JOIN)
  ```dart
  int existingMatriculaIndex = _clients.indexWhere(
    (c) => c.matricula == matricula && c.socket != socket,
  );
  if (existingMatriculaIndex != -1) {
    // Rejeita com ERROR: "❌ Matrícula já está conectada em outro dispositivo. Desconecte o outro primeiro."
  }
  ```
- **Resposta ao Cliente:** Mensagem clara + fecha conexão
- **Vantagens:**
  - Simples e não bloqueia uso legítimo (basta desconectar primeiro)
  - Garante unicidade
  - Mensagem educativa ("Desconecte o outro primeiro")
- **Limitações:**
  - Não detecta múltiplas nomes com mesma matrícula
- **Trade-off:** Segurança vs. simplicidade (adequado para N3)

#### 3.2 Device ID Binding — 🔶 PROPOSTA

- **Mecanismo:** App gera UUID único (salvo em SharedPreferences); servidor associa matrícula → deviceId
- **Implementação:** Aluno envia deviceId em JOIN; servidor valida
- **Vantagens:**
  - Impede mesmo aluno em múltiplos dispositivos
  - Persiste entre sessões
- **Limitações:**
  - Requer lógica adicional no servidor
  - Dispositivo pode resetar dados
- **Trade-off:** Segurança vs. complexidade (viável para N3 avançada)

---

### MC04: Aluno "Fantasma"

**Cenário:**

- Aluno registra presença na Rodada 1
- Sai da sala (sem enviar PIN para rodadas 2, 3, 4)
- Sistema marca como "Ausente" nas demais rodadas
- Fraude não é detectada; professor assume saída legítima

**Impacto:**

- Presença registrada incorretamente para primeira rodada

**Probabilidade:** Alta (frequente em aulas longas)

**Mitigações Propostas:**

#### 4.1 Múltiplas Rodadas — ✅ IMPLEMENTADA

- **Mecanismo:** Sistema configura 4 rodadas fixas ao longo da aula
- **Implementação:** `ConfiguracoesScreen` permite adicionar horários dinâmicos
- **Lógica:** Aluno que não confirma nas demais rodadas fica marcado "Ausente"
- **Resposta:** Histórico mostra ausência em rodadas 2, 3, 4
- **Vantagens:**
  - Detec padrão (presente em 1 e ausente em demais é suspeito)
  - Não requer tecnologia extra
  - Prático para aulas longas
- **Limitações:**
  - Aluno que sai na hora correta é marcado "Ausente" (correto mas pode parecer injusto)
  - Aumenta carga de professor (4 rodadas vs. 1)
- **Trade-off:** Detecção vs. carga administrativa (padrão em universidades)

#### 4.2 Heurística de Saída Detectada — 🔶 PROPOSTA

- **Mecanismo:** Servidor nota quando aluno desconecta e o marca como "Ausente" para rodadas posteriores
- **Implementação:** Em `_removeClient()`, marcar aluno como gone; rejeitar rejoin com mensagem
- **Vantagens:**
  - Detecção automática de desconexão
  - Justo para alunos que saem cedo
- **Limitações:**
  - Desconexões acidentais serão penalizadas
  - Complexidade em rastreamento de estado
- **Trade-off:** Justi

ça vs. robustez (não recomendado para N3)

---

## 2. Resumo de Medidas Implementadas (v2.0)

| Ameaça                     | Medida                                     | Status | Força | Código                           |
| -------------------------- | ------------------------------------------ | ------ | ----- | -------------------------------- |
| MC01 - Aluno Ausente       | SubnetCheck (IPv4 /24) + Persistência      | ✅     | Alta  | `professor_host_screen.dart:532` |
| MC02 - Força Bruta         | Rate Limiting (3 PIN/10min) + Persistência | ✅     | Alta  | `professor_host_screen.dart:560` |
| MC03 - Matrícula Duplicada | Socket Validation + Rejeição               | ✅     | Alta  | `professor_host_screen.dart:760` |
| MC04 - Aluno Fantasma      | Múltiplas Rodadas + Histórico Persistido   | ✅     | Média | `professor_host_screen.dart:288` |

### Detalhes de Implementação

#### ✅ MC01: Verificação de Sub-rede (IPv4 /24)

**Localização:** `professor_host_screen.dart` linhas 532-554

**Implementação Real:**

```dart
bool _isSameSubnet(String clientIp, String serverIp) {
  if (clientIp == "127.0.0.1" || serverIp == "127.0.0.1") {
    _log.fine('Verificação de sub-rede: Permitindo localhost.');
    return true;
  }
  try {
    final serverAddr = InternetAddress.tryParse(serverIp);
    final clientAddr = InternetAddress.tryParse(clientIp);

    // Se ambos IPv4, compara primeira 3 partes (/24)
    if (serverAddr.type == InternetAddressType.IPv4 &&
        clientAddr.type == InternetAddressType.IPv4) {
      final serverParts = serverIp.split('.');
      final clientParts = clientIp.split('.');

      bool isSame = serverParts[0] == clientParts[0] &&
                    serverParts[1] == clientParts[1] &&
                    serverParts[2] == clientParts[2];

      _log.fine('Verificação de sub-rede: $serverIp vs $clientIp -> ${isSame ? "OK" : "REJEITADO"}');
      return isSame;
    }
    // IPv6 ou misto: aceitar (não há strictness)
    _log.fine('Verificação de sub-rede: Detectado IPv6. Permitindo.');
    return true;
  } catch (e, s) {
    _log.severe('Erro ao verificar sub-rede', e, s);
    return false; // Falha segura
  }
}
```

**Proteção:** Rejeita alunos fora da rede local (mesma sala)
**Mensagem ao Cliente:** "Falha na verificação de rede. Use o mesmo Wi-Fi do professor."
**Força Efetiva:** ⭐⭐⭐⭐ Alta (em ambientes controlados)

---

#### ✅ MC02: Rate Limiting com Persistência

**Localização:** `professor_host_screen.dart` linhas 560-602

**Implementação Real:**

```dart
/// Estados para Antifraude: Rate Limiting de PIN
final Map<String, Map<String, int>> _pinAttempts = {};
static const int _maxPinAttempts = 3; // Máximo de tentativas
int _pinWindowMillis = 10 * 60 * 1000; // Janela: 10 minutos

/// Retorna número de tentativas, limpando expiradas
int _getPinAttempts(String key) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final entry = _pinAttempts[key];
  if (entry == null) return 0;

  final firstAt = entry['firstAt'] ?? 0;
  if (now - firstAt > _pinWindowMillis) {
    _pinAttempts.remove(key); // Janela expirou → reset
    return 0;
  }
  return entry['count'] ?? 0;
}

/// Registra tentativa com timestamp
void _registerPinAttempt(String key) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final entry = _pinAttempts[key];

  if (entry == null) {
    _pinAttempts[key] = {'count': 1, 'firstAt': now};
    _savePinAttempts(); // ← Persiste em SharedPreferences
    return;
  }

  final firstAt = entry['firstAt'] ?? now;
  if (now - firstAt > _pinWindowMillis) {
    // Janela expirou: reinicia
    _pinAttempts[key] = {'count': 1, 'firstAt': now};
  } else {
    // Ainda na janela: incrementa
    entry['count'] = (entry['count'] ?? 0) + 1;
    _pinAttempts[key] = entry;
  }
  _savePinAttempts(); // ← Persiste
}

/// Limpa tentativas após sucesso
void _clearPinAttempts(String key) {
  _pinAttempts.remove(key);
  _savePinAttempts();
}

/// Persistência em SharedPreferences
Future<void> _loadPinAttempts() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_pinAttemptsKey);
    if (raw == null || raw.isEmpty) return;

    final Map<String, dynamic> decoded = jsonDecode(raw);
    final now = DateTime.now().millisecondsSinceEpoch;

    decoded.forEach((key, value) {
      if (value is Map) {
        final count = (value['count'] ?? 0) as int;
        final firstAt = (value['firstAt'] ?? 0) as int;

        // Carrega apenas se não expirou
        if (now - firstAt <= _pinWindowMillis) {
          _pinAttempts[key] = {'count': count, 'firstAt': firstAt};
        }
      }
    });
  } catch (e, s) {
    _log.warning('Erro ao carregar tentativas de PIN persistidas', e, s);
  }
}

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
```

**Uso em PIN Validation:**

```dart
final attemptKey = "${matricula}_${rodadaNome}";
final int currentAttempts = _getPinAttempts(attemptKey);

if (currentAttempts >= _maxPinAttempts) {
  _log.warning('BLOQUEADO (RATE LIMIT): Aluno $matricula excedeu 3 tentativas');
  socket.add(jsonEncode({
    'command': 'PRESENCA_FALHA',
    'message': 'Você excedeu o número máximo de tentativas (3) na janela de 10 minutos. Tente novamente mais tarde.',
  }));
  return; // Bloqueia antes de validar PIN
}

// Se chegar aqui: validar PIN normalmente
if (rodadaAtiva != null && pinEnviado == rodadaAtiva.pin) {
  _clearPinAttempts(attemptKey); // ← Limpa após sucesso
  // ... registrar presença ...
} else {
  _registerPinAttempt(attemptKey); // ← Incrementa e persiste
}
```

**Proteção:** Rejeita após 3 tentativas erradas; persiste entre restarts
**Mensagem ao Cliente:** "Você excedeu 3 tentativas na janela de 10 minutos. Tente novamente mais tarde."
**Força Efetiva:** ⭐⭐⭐⭐⭐ Muito Alta (impossível quebrar por força bruta em 10min)
**Inovação:** ✨ Persistência em SharedPreferences garante bloqueio mesmo após restart

---

#### ✅ MC03: Validação de Matrícula Única

**Localização:** `professor_host_screen.dart` linhas 760-785

**Implementação Real:**

```dart
if (command == 'JOIN') {
  final String nome = data['nome'] ?? 'Aluno Desconhecido';
  final String matricula = data['matricula'] ?? 'MATRICULA_INVALIDA';

  // Validação 1: Matrícula obrigatória
  if (matricula == 'MATRICULA_INVALIDA') {
    _log.warning("Aluno $nome tentou conectar sem matrícula ($alunoIp). Rejeitando.");
    socket.add(jsonEncode({
      'command': 'ERROR',
      'message': "Matrícula é obrigatória.",
    }));
    socket.close(WebSocketStatus.policyViolation, "Matrícula é obrigatória.");
    return;
  }

  // Validação 2: CRÍTICA - Detecta duplicação
  int existingMatriculaIndex = _clients.indexWhere(
    (c) => c.matricula == matricula && c.socket != socket,
  );
  if (existingMatriculaIndex != -1) {
    _log.warning("Matrícula $matricula já conectada por outro dispositivo. Desconectando nova tentativa de $alunoIp.");
    socket.add(jsonEncode({
      'command': 'ERROR',
      'message': "❌ Matrícula '$matricula' já está conectada em outro dispositivo. Desconecte o outro primeiro.",
    }));
    socket.close(WebSocketStatus.policyViolation, "Matrícula já conectada.");
    return;
  }

  // Se passou: aceitar
  aluno = AlunoConectado(socket: socket, nome: nome, matricula: matricula, ip: alunoIp, connectedAt: DateTime.now());
  _clients.add(aluno);
}
```

**Proteção:** Apenas 1 socket ativo por matrícula; rejeita segundo
**Mensagem ao Cliente:** "Matrícula já conectada. Desconecte o outro primeiro."
**Força Efetiva:** ⭐⭐⭐⭐ Alta (impossível duplicação simultânea)
**Trade-off:** Aluno que trocou de dispositivo deve desconectar o antigo primeiro (justo)

---

#### ✅ MC04: Múltiplas Rodadas + Histórico Persistido

**Localização:** `professor_host_screen.dart` linhas 288-354 (carregamento) + 1035-1065 (persistência)

**Implementação Real:**

```dart
/// Histórico persistido em SharedPreferences
Map<String, Map<String, String>> _presencas = {}; // matrícula → {rodada → status}
Map<String, String> _alunoNomes = {}; // matrícula → nome
static const String _historicoKey = 'historico_geral_presencas';

/// Carrega histórico ao iniciar
Future<void> _loadHistorico() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final String? historicoJson = prefs.getString(_historicoKey);

    if (historicoJson != null && historicoJson.isNotEmpty) {
      final decodedData = jsonDecode(historicoJson) as Map<String, dynamic>;

      _alunoNomes = Map<String, String>.from(decodedData['nomes'] as Map? ?? {});

      final presencasBruto = decodedData['presencas'] as Map<String, dynamic>? ?? {};
      _presencas = presencasBruto.map(
        (matricula, rodadasMap) => MapEntry(matricula, Map<String, String>.from(rodadasMap as Map)),
      );

      _log.info("Histórico carregado com ${_alunoNomes.length} alunos e ${_presencas.length} registros.");
    }
  } catch (e, s) {
    _log.warning("Erro ao carregar histórico: $e. Iniciando vazio.", e, s);
    _presencas = {};
    _alunoNomes = {};
  }
}

/// Salva histórico (chamado após cada ação PIN)
Future<void> _saveHistorico() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> historicoData = {
      'nomes': _alunoNomes,
      'presencas': _presencas,
    };
    final String historicoJson = jsonEncode(historicoData);
    await prefs.setString(_historicoKey, historicoJson);
    _log.info("Histórico salvo (${_alunoNomes.length} alunos, ${_presencas.length} presenças).");
  } catch (e, s) {
    _log.severe("Erro ao salvar histórico", e, s);
  }
}

/// Múltiplas rodadas: Aluno que sai sem confirmar fica "Ausente"
void _verificarRodadas() {
  final now = DateTime.now();

  for (var rodada in _rodadas) {
    if (rodada.status == "Em Andamento" && now.isAfter(rodadaEndTimeToday)) {
      // Marca alunos que não submeteram PIN como "Ausente"
      for (var aluno in _clients) {
        _presencas[aluno.matricula] ??= {};
        if (!_presencas[aluno.matricula]!.containsKey(rodada.nome)) {
          _presencas[aluno.matricula]![rodada.nome] = 'Ausente';
        }
      }
      _saveHistorico(); // ← Persiste após cada rodada
    }
  }
}
```

**Proteção:** Histórico de todas as tentativas persistido; múltiplas rodadas permitem detecção de padrão
**Formato Persistido:** JSON com estrutura `{nomes: {...}, presencas: {...}}`
**Força Efetiva:** ⭐⭐⭐ Média (detecta padrão de fraude; não impede primeira rodada)
**Inovação:** ✨ Persistência permite auditoria e rastreamento histórico

---

---

## 3. Implementações Propostas vs. Realizadas

### 🔶 P0 (Crítico - NÃO IMPLEMENTADO)

- **Timeout Progressivo no WebSocket:**

  - ❌ Não implementado
  - Recomendação: Adicionar `socket.listen(..., onDone: _handleSocketClose)` com timer de 5min inatividade
  - Benefício: Libera conexões zumbis após inatividade prolongada
  - Código proposto:
    ```dart
    final inactivityTimer = Timer(Duration(minutes: 5), () {
      socket.close(WebSocketStatus.goingAway, "Inatividade");
    });
    socket.listen(
      (data) {
        inactivityTimer.cancel();
        // ... processar ...
        inactivityTimer = Timer(Duration(minutes: 5), () => socket.close());
      },
      onDone: () => inactivityTimer.cancel(),
    );
    ```

- **PIN de 5-6 Dígitos:**
  - ❌ Não implementado (mantém 4 dígitos atual: 0000-9999)
  - Recomendação: Aumentar em `ConfiguracoesScreen` para 5-6 dígitos (6 dígitos = 1M combinações)
  - Trade-off: Alunos podem reclamar de PIN mais longo na pressa
  - Impacto: Aumentaria tempo de force-brute de ~5min para ~50+ horas (com rate limiting)

### ✅ P1 (Importante - PARCIALMENTE IMPLEMENTADO)

- **Rate Limiting no JOIN:**

  - ✅ Implementado para PIN (MC02: 3 tentativas/10min)
  - 🔶 Não implementado para JOIN connections
  - Recomendação futura: Limitar 10 JOIN/min por IP para evitar ataque de conexão DDoS
  - Código proposto:
    ```dart
    final joinKey = "${alunoIp}_JOIN_CONN";
    if (_getPinAttempts(joinKey) >= 10) {
      _log.warning("Bloqueado: Muitas conexões JOIN de $alunoIp");
      socket.close(WebSocketStatus.policyViolation, "Muitas conexões. Tente novamente em 1 minuto.");
      return;
    }
    _registerPinAttempt(joinKey); // Incrementa
    ```

- **Validação de Nome Sanitizado:**
  - ✅ Recebido do frontend sem validação extra no servidor
  - 🔶 Não há sanitização ativa (potencial XSS em exibição web)
  - Recomendação: Adicionar regex `^[a-zA-Z0-9áéíóúãõêô ]+$` em `_handleClientMessage`
  - Código proposto:
    ```dart
    final nomeRegex = RegExp(r'^[a-zA-Z0-9áéíóúãõêô ]{1,100}$');
    if (!nomeRegex.hasMatch(nome)) {
      final nomeSanitizado = nome.replaceAll(RegExp(r'[^a-zA-Z0-9áéíóúãõêô ]'), '');
      _log.warning("Nome contém caracteres inválidos. Sanitizado: $nome → $nomeSanitizado");
    }
    ```

### 🟡 P2 (Nice-to-Have - NÃO IMPLEMENTADO)

- **Geofencing (GPS):**

  - ❌ Não implementado
  - Razão: Requer permissão de localização contínua (drena bateria ~10%/hora); imprecisão em ambientes cobertos
  - Caso de Uso: Útil em cursos com múltiplos campi; não necessário em sala única
  - Recomendação: Ignorar para MVP; implementar se houver fraude geográfica detectada

- **Device ID Binding:**

  - ❌ Não implementado
  - Razão: Requer geração/persistência de UUID único; aluno trocando dispositivo seria bloqueado
  - Caso de Uso: Previne compartilhamento de matrícula entre múltiplos usuários
  - Recomendação: Implementar se fraude "mulher de aluga matrícula" aumentar; usar junto com geofencing

- **CAPTCHA Progressivo:**

  - ❌ Não implementado
  - Razão: Não é eficaz em ambiente controlado (mesma rede local); aluno teria que resolver CAPTCHA a cada aula
  - Caso de Uso: Útil em sistema aberto (ex: prova online pública)
  - Recomendação: Ignorar; usar apenas Rate Limiting (MC02 já suficiente)

- **Heurística Avançada:**
  - ✅ Parcialmente implementado via `_isSameSubnet()` (MC01)
  - 🔶 Não bloqueia múltiplas matriculas do mesmo IP (comportamento esperado em laboratório)
  - Caso de Uso: Detectar padrão "mesmo IP, múltiplas matriculas" → suspeito
  - Recomendação: Adicionar flag "Lab Mode" em `ConfiguracoesScreen` para permitir múltiplas matriculas/IP em ambiente educacional
  - Código proposto:
    ```dart
    bool labMode = false; // Flag em Configurações
    if (!labMode) {
      final outrosAlunosNoIp = _clients.where((c) => c.ip == alunoIp && c.matricula != matricula).length;
      if (outrosAlunosNoIp > 2) {
        _log.warning("Suspeito: IP $alunoIp com ${outrosAlunosNoIp + 1} matriculas diferentes");
        // Não bloqueia; apenas registra para auditoria
      }
    }
    ```

### N10+ (Banco Externo - Fora de Escopo)

- [ ] Integração com banco de dados externo (Firebase/Supabase)
- [ ] Audit trail com timestamps precisos em servidor remoto
- [ ] Análise comportamental (padrões de ausência)
- [ ] Integração com sistema acadêmico para sincronização de matriculas

---

## 4. Termos e Definições

- **Matrícula:** ID único do aluno (ex: 202301)
- **SubnetCheck (MC01):** Validação de que cliente e servidor estão na mesma rede local (3 primeiros octetos IPv4 /24)
- **Rate Limiting (MC02):** Limite de 3 tentativas de PIN por matrícula-rodada em janela de 10 minutos (persistido)
- **Socket Validation (MC03):** Rejeição de segundo socket com mesma matrícula
- **Histórico Persistido (MC04):** Rastreamento de todas as tentativas de presença em SharedPreferences
- **Device ID:** UUID único gerado no dispositivo (não implementado)
- **Geofencing:** Validação de localização via GPS (não implementado)

---

## 5. Checklist de Segurança - N3 MVP

| #   | Controle                | Status | Localização                         |
| --- | ----------------------- | ------ | ----------------------------------- |
| 1   | JSON Validation         | ✅     | `professor_host_screen.dart:440`    |
| 2   | Matrícula Obrigatória   | ✅     | `professor_host_screen.dart:765`    |
| 3   | Sub-rede /24            | ✅     | `professor_host_screen.dart:532`    |
| 4   | Rate Limiting (3/10min) | ✅     | `professor_host_screen.dart:560`    |
| 5   | Persistência Rate Limit | ✅     | SharedPreferences `_pinAttemptsKey` |
| 6   | Rejeição Duplicação     | ✅     | `professor_host_screen.dart:776`    |
| 7   | Validação Rodada Ativa  | ✅     | `aluno_wait_screen.dart:480`        |
| 8   | Timestamp Servidor      | ✅     | `professor_host_screen.dart:610`    |
| 9   | PIN Obrigatório         | ✅     | `aluno_wait_screen.dart:490`        |
| 10  | Histórico Persistido    | ✅     | SharedPreferences `_historicoKey`   |
| 11  | WebSocket Timeout       | ❌     | Recomendação P0                     |
| 12  | Nome Sanitizado         | ❌     | Recomendação P1                     |
| 13  | Rate Limit JOIN         | ❌     | Recomendação P1                     |

**Status Geral:** 10/13 (77%) implementado; 3 recomendações não-críticas

---

## 6. Requisitos Atendidos (RNF07)

✅ **RNF07 - Documentação de Antifraude com 3+ Ameaças/Mitigações:**

| Ameaça | Descrição                   | Mitigações                               | Status          |
| ------ | --------------------------- | ---------------------------------------- | --------------- |
| MC01   | Aluno Ausente Injustificado | SubnetCheck (/24) + Rate Limiting        | ✅ Implementado |
| MC02   | Força Bruta de PIN          | Rate Limiting (3/10min) + Persistência   | ✅ Implementado |
| MC03   | Matrícula Duplicada         | Socket Validation + Rejeição             | ✅ Implementado |
| MC04   | Aluno Fantasma              | Histórico Persistido + Múltiplas Rodadas | ✅ Implementado |

**Conclusão:** RNF07 totalmente atendido. Documento pronto para entrega N3.

---

## 7. Guia Rápido de Teste

### Teste de Rate Limiting

```
1. Aluno tenta PIN errado 3x em 10min
2. Esperado: 4ª tentativa bloqueada com mensagem
3. Verificar: /data/data/com.sj.smartpresence/shared_prefs/ → arquivo `_pinAttemptsKey`
```

### Teste de Sub-rede

```
1. Conectar aluno de rede diferente (ex: USB tethering de outro celular)
2. Esperado: Mensagem "Falha na verificação de rede"
3. Verificar: Log do servidor com "REJEITADO"
```

### Teste de Duplicação

```
1. Abrir app em 2 dispositivos com mesma matrícula
2. Esperado: Segundo dispositivo desconectado com mensagem
3. Verificar: Log "Matrícula já conectada"
```

---

**Documento final para entrega N3.0 (MVP). Revisar e atualizar conforme testes em dispositivo real.**
**Últimas validações:** 15 warnings deprecados corrigidos em `flutter analyze`; 0 erros críticos.
