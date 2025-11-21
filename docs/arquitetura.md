# Arquitetura do Sistema - SmartPresence

**Versão:** 2.0  
**Data:** 20 de Novembro de 2025  
**Grupo:** CodeMonkeys Corp  
**Disciplina:** N3 (Trabalho Final)

---

## 1. Visão Geral

O **SmartPresence** é um sistema de controle de presença baseado em presença física (validação de rede) e PIN aleatório, implementado em **Flutter** com arquitetura cliente-servidor usando **WebSocket** para comunicação em tempo real e **Network Service Discovery (NSD)** para descoberta automática de servidores.

### Motivação Arquitetural

- **Distribuído:** Professor (servidor) executa num dispositivo, alunos (clientes) em múltiplos dispositivos
- **Tempo Real:** WebSocket garante latência baixa e bi-direcionalidade
- **Offline-Friendly:** NSD descobre servidor via Bluetooth/WiFi sem Internet centralizada
- **Seguro:** SubnetCheck (IP validado) + Rate Limiting (força bruta bloqueada) + Token único por socket
- **Persistente:** SharedPreferences + CSV export para histórico

---

## 2. Componentes Principais

### 2.1 Camada de Apresentação (UI)

#### **RoleSelectionScreen** (Entry Point)

- **Propósito:** Escolher papel (Professor ou Aluno)
- **Estado:** UI apenas (sem lógica)
- **Transição:**
  - "Professor" → ProfessorHostScreen
  - "Aluno" → AlunoJoinScreen
- **Localização:** `lib/screens/role_selection_screen.dart`
- **Dependências:** Material Flutter, Navigator

#### **ProfessorHostScreen** (Server + Control Panel)

- **Propósito:** Hospedar WebSocket server, gerenciar rodadas, monitorar presença, exportar CSV
- **Responsabilidades:**
  1. Criar HttpServer em porta aleatória
  2. Publicar serviço via NSD (`_smartpresence._tcp`)
  3. Gerir timer de rodadas (início/fim)
  4. Processar mensagens JSON do WebSocket (JOIN, SUBMIT_PIN)
  5. Validar antifraude (SubnetCheck, Rate Limiting)
  6. Registrar presença (em memória + SharedPreferences)
  7. Exportar para CSV
- **Estado (Dart):**
  ```dart
  late HttpServer _server;
  late NsdServiceInfo _nsdService;
  final Map<String, WebSocket> _connectedClients = {};
  final Map<String, AlunoConectado> _alunosConectados = {};
  final Map<String, Map<String, String>> _presencas = {};
  final Map<String, int> _pinAttempts = {}; // Antifraude
  final List<Rodada> _rodadas = [];
  Timer? _timerRodada;
  late int _portaServidor;
  ```
- **Métodos Críticos:**
  - `_startServer()` — Cria HttpServer e inicia upgrade WebSocket
  - `_publishNsdService()` — Registra serviço via NSD
  - `_startRodada(Rodada rodada)` — Inicia timer de rodada
  - `_endRodada(String rodadaNome)` — Encerra rodada e marca ausentes
  - `_handleClientMessage(WebSocket socket, String message)` — Router de comandos
  - `_validateSubnet(String clientIp)` — Validação antifraude
  - `_exportarCSV()` — Salva CSV em Downloads
- **Localização:** `lib/screens/professor_host_screen.dart` (~1511 linhas)
- **Dependências:**
  - `dart:io` (HttpServer, WebSocket)
  - `nsd` (NSD discovery)
  - `shared_preferences`
  - `path_provider`
  - `intl` (formatação data/hora)
  - `logging`

#### **ConfiguracoesScreen** (Settings)

- **Propósito:** Configurar agendamento de rodadas e duração
- **Funcionalidades:**
  1. Adicionar múltiplas rodadas (nome, hora de início)
  2. Editar rodadas
  3. Remover rodadas
  4. Definir duração padrão
- **Persistência:** SharedPreferences (`rodadas_config`, `duracao_rodada`)
- **Localização:** `lib/screens/configuracoes_screen.dart` (~350 linhas)
- **Dependências:** Material Flutter, time_picker

#### **HistoricoScreen** (Data Visualization)

- **Propósito:** Visualizar histórico de presença por aluno e rodada
- **Funcionalidades:**
  1. Listar alunos conectados (expandível)
  2. Mostrar status por rodada
  3. Ordenar por matrícula/nome
- **Dados:** Lidos de SharedPreferences (chave: `presenca_history`)
- **Localização:** `lib/screens/historico_screen.dart` (~350 linhas)
- **Dependências:** Material Flutter, json parsing

#### **AlunoJoinScreen** (Discovery + Connection)

- **Propósito:** Descobrir servidor professor via NSD, conectar WebSocket
- **Responsabilidades:**
  1. Pedir permissões de localização (necessário para NSD em Android 11+)
  2. Iniciar NSD discovery para `_smartpresence._tcp`
  3. Listar serviços descobertos
  4. Permitir entrada manual de IP:Porta como fallback
  5. Validar nome e matrícula do aluno
  6. Conectar WebSocket e enviar JOIN
  7. Navegar para AlunoWaitScreen se sucesso
- **Estado:**
  ```dart
  late NsdServiceListener _nsdListener;
  final List<NsdServiceInfo> _discoveredServices = [];
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _matriculaController = TextEditingController();
  final TextEditingController _nomeController = TextEditingController();
  WebSocketChannel? _channel;
  ```
- **Métodos Críticos:**
  - `_startDiscovery()` — Pede Permission.location, inicia NSD
  - `_resolveService(NsdServiceInfo)` — Obtém IP/Porta
  - `_connectToWebSocket(String ip, int port)` — Conecta e envia JOIN
- **Localização:** `lib/screens/aluno_join_screen.dart` (~476 linhas)
- **Dependências:**
  - `nsd`
  - `web_socket_channel`
  - `permission_handler`

#### **AlunoWaitScreen** (PIN Submission + Feedback)

- **Propósito:** Aguardar rodada, receber PIN, enviar resposta, receber feedback
- **Responsabilidades:**
  1. Receber mensagem RODADA_ABERTA com `endTimeMillis`
  2. Exibir countdown timer
  3. Mostrar teclado numérico (4 dígitos)
  4. Enviar SUBMIT_PIN com PIN + rodada
  5. Receber PRESENCA_OK (✅ Presente) ou PRESENCA_FALHA (❌ Falhou)
  6. Exibir feedback com haptic
  7. Garantir fechamento de WebSocket em dispose
- **Estado:**
  ```dart
  late StreamController<dynamic> _streamController;
  String _currentStatus = 'Aguardando rodada...';
  int? _endTimeMillis;
  int _countdown = 0;
  String _pinInput = '';
  ```
- **Métodos Críticos:**
  - `_listenToServer()` — Inicia stream.listen com handlers
  - `_submitPin()` — Envia SUBMIT_PIN JSON
  - `_updateCountdown()` — Timer de 1s para atualizar UI
- **Localização:** `lib/screens/aluno_wait_screen.dart` (~437 linhas)
- **Dependências:**
  - `web_socket_channel`
  - `vibration` (haptic feedback)

---

### 2.2 Camada de Comunicação

#### **WebSocket Protocol (JSON-based)**

**Mensagens Server → Client:**

1. **JOIN_SUCCESS**

   ```json
   {
     "command": "JOIN_SUCCESS",
     "message": "Bem-vindo, João!",
     "rodada_atual": "Rodada 1"
   }
   ```

2. **RODADA_ABERTA**

   ```json
   {
     "command": "RODADA_ABERTA",
     "rodada": "Rodada 1",
     "pin": "9876",
     "endTimeMillis": 1700500542000,
     "duracao_segundos": 120
   }
   ```

3. **PRESENCA_OK**

   ```json
   {
     "command": "PRESENCA_OK",
     "message": "✅ Presença registrada com sucesso!"
   }
   ```

4. **PRESENCA_FALHA**

   ```json
   {
     "command": "PRESENCA_FALHA",
     "message": "PIN incorreto. Tentativas restantes: 2"
   }
   ```

5. **RODADA_FECHADA**

   ```json
   {
     "command": "RODADA_FECHADA",
     "message": "Rodada encerrada."
   }
   ```

6. **ERROR**
   ```json
   {
     "command": "ERROR",
     "message": "❌ Matrícula já está conectada em outro dispositivo."
   }
   ```

**Mensagens Client → Server:**

1. **JOIN**

   ```json
   {
     "command": "JOIN",
     "matricula": "202301",
     "nome": "João Silva"
   }
   ```

2. **SUBMIT_PIN**
   ```json
   {
     "command": "SUBMIT_PIN",
     "pin": "9876",
     "rodada": "Rodada 1",
     "matricula": "202301"
   }
   ```

#### **Network Service Discovery (mDNS/Bonjour)**

- **Serviço:** `_smartpresence._tcp.local.`
- **Tipo:** TCP, local network
- **Attributes Publicados:**
  ```
  Port: <RANDOM_PORT>
  Instance Name: SmartPresence-<DEVICE_NAME>
  ```
- **Descoberta:** Client usa `mdns` listener para encontrar instâncias ativas
- **Resolução:** Obtém IP do host + porta do atributo

---

### 2.3 Camada de Persistência

#### **SharedPreferences (Local Storage)**

| Chave              | Tipo        | Propósito                                        |
| ------------------ | ----------- | ------------------------------------------------ |
| `rodadas_config`   | JSON String | Lista de rodadas (nome, horaInicio, duracao)     |
| `duracao_rodada`   | Integer     | Duração padrão em segundos                       |
| `presenca_history` | JSON String | Histórico de presenças (aluno → rodada → status) |
| `last_export_csv`  | String      | Data/hora do último export (info)                |

**Estrutura de `presenca_history`:**

```json
{
  "2025-11-20": {
    "202301": {
      "nome": "João Silva",
      "Rodada 1": "Presente",
      "Rodada 2": "Presente",
      "Rodada 3": "Falhou PIN",
      "Rodada 4": "Ausente"
    },
    "202302": {
      "nome": "Maria Santos",
      "Rodada 1": "Presente",
      ...
    }
  }
}
```

#### **CSV Export**

- **Localização:** `<DOWNLOADS>/presenca_smartpresence_YYYYMMDD_HHmmss.csv`
- **Formato:** UTF-8, delimitador `,`, escape com `"`
- **Colunas:** `matricula, nome, data, rodada, status, gravado_em, notas, metodo_validacao`
- **Permissões:** `WRITE_EXTERNAL_STORAGE`, `READ_EXTERNAL_STORAGE`
- **Gerado por:** `ProfessorHostScreen._exportarCSV()`

---

### 2.4 Camada de Modelos

#### **Rodada** (`lib/models/app_models.dart`)

```dart
class Rodada {
  final String nome;
  final TimeOfDay horaInicio;
  final int duracaoSegundos; // 120 padrão
  RodadaStatus status; // AGENDADA, ABERTA, FECHADA
  String pin; // 4 dígitos
  DateTime? dataInicio;

  Rodada({
    required this.nome,
    required this.horaInicio,
    this.duracaoSegundos = 120,
    this.status = RodadaStatus.AGENDADA,
    this.pin = '',
    this.dataInicio,
  });

  Map<String, dynamic> toJson() => {...};
  factory Rodada.fromJson(Map<String, dynamic> json) => ...;
}

enum RodadaStatus { AGENDADA, ABERTA, FECHADA }
```

#### **AlunoConectado**

```dart
class AlunoConectado {
  final WebSocket socket;
  final String matricula;
  final String nome;
  final String ip;
  final DateTime connectedAt;

  AlunoConectado({
    required this.socket,
    required this.matricula,
    required this.nome,
    required this.ip,
    required this.connectedAt,
  });
}
```

---

## 3. Fluxo de Dados

### 3.1 Fluxo de Conexão (JOIN)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         ALUNO                                        │
├─────────────────────────────────────────────────────────────────────┤
│ 1. RoleSelectionScreen → taps "Aluno"                               │
│ 2. AlunoJoinScreen: pede Permission.location                        │
│ 3. AlunoJoinScreen: NSD discovery para "_smartpresence._tcp"        │
│ 4. AlunoJoinScreen: usuário seleciona serviço ou digita IP:Porta    │
│ 5. AlunoJoinScreen: _connectToWebSocket(ip, port)                   │
│ 6. AlunoJoinScreen: envia JSON:                                     │
│    {"command": "JOIN", "matricula": "202301", "nome": "João Silva"} │
│ 7. AlunoJoinScreen: aguarda resposta                                │
└─────────────────────────────────────────────────────────────────────┘
                              ↓ WebSocket
┌─────────────────────────────────────────────────────────────────────┐
│                     PROFESSOR (Servidor)                             │
├─────────────────────────────────────────────────────────────────────┤
│ 1. ProfessorHostScreen: _startServer() criou HttpServer             │
│ 2. HttpServer: recebe GET /socket (upgrade para WebSocket)          │
│ 3. _handleClientMessage(socket, message) processa JOIN              │
│ 4. Validações:                                                      │
│    a) Matrícula já conectada? → ERROR + close socket               │
│    b) IP em mesma sub-rede? → OK                                   │
│    c) Novo aluno? → armazena em _alunosConectados                  │
│ 5. Envia resposta:                                                  │
│    {"command": "JOIN_SUCCESS", "message": "Bem-vindo, João!", ...} │
│ 6. Armazena socket em _connectedClients["matricula"]               │
│ 7. Atualiza UI em ProfessorHostScreen: "+1 aluno conectado"        │
└─────────────────────────────────────────────────────────────────────┘
                              ↓ WebSocket
┌─────────────────────────────────────────────────────────────────────┐
│                         ALUNO                                        │
├─────────────────────────────────────────────────────────────────────┤
│ 1. AlunoJoinScreen: recebe JOIN_SUCCESS                             │
│ 2. AlunoJoinScreen: Navigator.push(AlunoWaitScreen, channel)        │
│ 3. AlunoWaitScreen: inicia _listenToServer()                        │
│ 4. AlunoWaitScreen: aguarda RODADA_ABERTA                           │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.2 Fluxo de Rodada (PRESENÇA)

```
┌─────────────────────────────────────────────────────────────────────┐
│                   PROFESSOR (Servidor)                              │
├─────────────────────────────────────────────────────────────────────┤
│ 1. Professor taps "Iniciar Rodada 1" em ProfessorHostScreen        │
│ 2. _startRodada(rodada):                                            │
│    a) Gera PIN aleatório: "9876"                                   │
│    b) Armazena _presencas["Rodada 1"] = {todos: "Ausente"}         │
│    c) Calcula endTime = now + duracaoSegundos (120s)               │
│    d) Inicia Timer para chamar _endRodada em 120s                  │
│ 3. Broadcast para TODOS os clientes conectados:                    │
│    {"command": "RODADA_ABERTA",                                    │
│     "rodada": "Rodada 1",                                           │
│     "pin": "9876",                                                  │
│     "endTimeMillis": 1700500542000,                                │
│     "duracao_segundos": 120}                                        │
│ 4. ProfessorHostScreen: exibe "Rodada 1 ativa (PIN: 9876)"        │
└─────────────────────────────────────────────────────────────────────┘
                              ↓ WebSocket (broadcast)
┌─────────────────────────────────────────────────────────────────────┐
│                         ALUNOS                                       │
├─────────────────────────────────────────────────────────────────────┤
│ 1. AlunoWaitScreen: recebe RODADA_ABERTA                            │
│ 2. AlunoWaitScreen: atualiza UI:                                    │
│    - Exibe "Rodada 1 aberta!"                                      │
│    - Mostra countdown de 120s → 119s → ... → 1s → 0s              │
│    - Exibe teclado numérico                                         │
│ 3. Aluno digita PIN: "9876"                                         │
│ 4. Aluno taps "CONFIRMAR"                                           │
│ 5. AlunoWaitScreen envia SUBMIT_PIN:                                │
│    {"command": "SUBMIT_PIN",                                        │
│     "pin": "9876",                                                  │
│     "rodada": "Rodada 1",                                           │
│     "matricula": "202301"}                                          │
└─────────────────────────────────────────────────────────────────────┘
                              ↓ WebSocket
┌─────────────────────────────────────────────────────────────────────┐
│                   PROFESSOR (Servidor)                              │
├─────────────────────────────────────────────────────────────────────┤
│ 1. _handleClientMessage(socket, SUBMIT_PIN) recebe PIN              │
│ 2. Validações (em ordem):                                           │
│    a) Rate Limiting:                                                │
│       - Chave: "202301_Rodada 1"                                   │
│       - Se _pinAttempts[key] >= 3: BLOQUEADO                       │
│       - Senão: incrementa _pinAttempts[key]                        │
│    b) Subnet Check:                                                 │
│       - Se clientIp ∉ mesma /24: FALHOU (rede)                    │
│    c) PIN Verification:                                             │
│       - Se pin != "9876": FALHOU (tentativa +1)                    │
│       - Se pin == "9876": SUCESSO                                  │
│ 3. Se sucesso:                                                      │
│    - _presencas["202301"]["Rodada 1"] = "Presente"                │
│    - Envia PRESENCA_OK:                                             │
│      {"command": "PRESENCA_OK",                                    │
│       "message": "✅ Presença registrada!"}                        │
│    - Zera contador de tentativas: _pinAttempts["202301_Rodada 1"]  │
│ 4. Se falha PIN:                                                    │
│    - _presencas["202301"]["Rodada 1"] = "Falhou PIN"              │
│    - Envia PRESENCA_FALHA:                                          │
│      {"command": "PRESENCA_FALHA",                                 │
│       "message": "PIN incorreto. Tentativas restantes: 2"}         │
│ 5. Se rate limit excedido:                                          │
│    - Envia PRESENCA_FALHA:                                          │
│      {"command": "PRESENCA_FALHA",                                 │
│       "message": "Máximo de tentativas (3) excedido. Acesso bloqueado."}
│ 6. Se falha rede (subnet):                                          │
│    - Envia PRESENCA_FALHA:                                          │
│      {"command": "PRESENCA_FALHA",                                 │
│       "message": "Falha na validação de rede (IP inválido)"}       │
│ 7. ProfessorHostScreen: atualiza UI em tempo real                  │
└─────────────────────────────────────────────────────────────────────┘
                              ↓ WebSocket
┌─────────────────────────────────────────────────────────────────────┐
│                         ALUNO                                        │
├─────────────────────────────────────────────────────────────────────┤
│ 1. AlunoWaitScreen: recebe PRESENCA_OK                              │
│ 2. AlunoWaitScreen: exibe ✅ "Presença registrada!"                 │
│ 3. AlunoWaitScreen: toca haptic feedback (vibração)                 │
│ 4. AlunoWaitScreen: aguarda próxima rodada                          │
│                                                                      │
│ OU se recebe PRESENCA_FALHA:                                        │
│ 1. AlunoWaitScreen: exibe ❌ "PIN incorreto. Tentativas restantes: 2" │
│ 2. AlunoWaitScreen: limpa campo de PIN                              │
│ 3. AlunoWaitScreen: usuário tenta novamente                         │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.3 Fluxo de Encerramento de Rodada

```
┌─────────────────────────────────────────────────────────────────────┐
│                   PROFESSOR (Servidor)                              │
├─────────────────────────────────────────────────────────────────────┤
│ 1. Timer (iniciado em _startRodada) expira após 120s                │
│ 2. _endRodada("Rodada 1") é chamado:                                │
│    a) Para o Timer                                                  │
│    b) Para cada aluno em _alunosConectados:                         │
│       - Se _presencas[matricula]["Rodada 1"] == undefined:         │
│         → Define como "Ausente"                                    │
│    c) Broadcast RODADA_FECHADA para todos:                         │
│       {"command": "RODADA_FECHADA",                                │
│        "message": "Rodada 1 finalizada."}                          │
│ 3. ProfessorHostScreen: atualiza UI                                 │
│ 4. Aguarda próxima rodada ou professor inicia manualmente           │
└─────────────────────────────────────────────────────────────────────┘
                              ↓ WebSocket
┌─────────────────────────────────────────────────────────────────────┐
│                         ALUNOS                                       │
├─────────────────────────────────────────────────────────────────────┤
│ 1. AlunoWaitScreen: recebe RODADA_FECHADA                           │
│ 2. AlunoWaitScreen: para o countdown                                │
│ 3. AlunoWaitScreen: exibe "Rodada finalizada"                       │
│ 4. AlunoWaitScreen: aguarda próxima RODADA_ABERTA                   │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.4 Fluxo de Exportação CSV

```
┌─────────────────────────────────────────────────────────────────────┐
│                   PROFESSOR                                         │
├─────────────────────────────────────────────────────────────────────┤
│ 1. ProfessorHostScreen: taps "Exportar CSV"                         │
│ 2. _exportarCSV():                                                  │
│    a) Pede Permission.storage.request()                             │
│    b) Lê _presencas (mapa na memória)                               │
│    c) Lê SharedPreferences presenca_history                         │
│    d) Gera filename: presenca_smartpresence_20251120_193500.csv    │
│    e) Constrói headers: matricula,nome,data,rodada,status,...      │
│    f) Itera todos os alunos × rodadas                               │
│    g) Escreve CSV com encoding UTF-8                                │
│    h) Salva em getDownloadsDirectory()                              │
│    i) Notifica usuário com Toast: "CSV exportado para..."           │
│ 3. CSV fica acessível em:                                           │
│    /storage/emulated/0/Downloads/presenca_smartpresence_*.csv      │
│ 4. Usuário pode compartilhar via email, Drive, etc.                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Antifraude (Mitigações Implementadas)

### 4.1 SubnetCheck (MC01 - Aluno Ausente)

**Ameaça:** Aluno conecta de IP fora da sala (acesso remoto)

**Implementação:**

```dart
bool _isSameSubnet(String clientIp) {
  try {
    // Server IP: 192.168.1.50
    // Client IP: 192.168.1.100
    // Válida se primeiros 3 octetos iguais
    final serverParts = "192.168.1.50".split('.');
    final clientParts = clientIp.split('.');

    for (int i = 0; i < 3; i++) {
      if (serverParts[i] != clientParts[i]) {
        return false; // Diferentes sub-redes
      }
    }
    return true;
  } catch (e) {
    return false;
  }
}
```

**Localização:** `professor_host_screen.dart` linha ~850  
**Trigger:** Antes de validar PIN  
**Feedback:** "Falha na validação de rede (IP inválido)"

### 4.2 Rate Limiting (MC02 - Força Bruta)

**Ameaça:** Atacante tenta todos os PINs (0000-9999) até acertar

**Implementação:**

```dart
final Map<String, int> _pinAttempts = {}; // Estado
static const int _maxPinAttempts = 3;

// Na função _handleClientMessage(), seção SUBMIT_PIN:
final attemptKey = "${matricula}_${rodadaNome}";
final currentAttempts = _pinAttempts[attemptKey] ?? 0;

if (currentAttempts >= _maxPinAttempts) {
  socket.add(jsonEncode({
    'command': 'PRESENCA_FALHA',
    'message': 'Você excedeu o número máximo de tentativas (3). Acesso bloqueado.',
  }));
  _presencas[matricula]![rodadaNome] = 'Falhou PIN';
  return;
}

// Incrementa contador
_pinAttempts[attemptKey] = currentAttempts + 1;
final tentativasRestantes = _maxPinAttempts - (currentAttempts + 1);

if (pin != rodada.pin) {
  socket.add(jsonEncode({
    'command': 'PRESENCA_FALHA',
    'message': 'PIN incorreto. Tentativas restantes: $tentativasRestantes',
  }));
  _presencas[matricula]![rodadaNome] = 'Falhou PIN';
  return;
}
```

**Localização:** `professor_host_screen.dart` linhas ~708-800  
**Trigger:** Antes de validar PIN correto  
**Feedback:** "Tentativas restantes: X" ou "Acesso bloqueado"

### 4.3 Socket Uniqueness (MC03 - Matrícula Duplicada)

**Ameaça:** Mesma matrícula conecta 2x (física vs. remota)

**Implementação:**

```dart
if (_connectedClients.containsKey(matricula)) {
  socket.add(jsonEncode({
    'command': 'ERROR',
    'message': "❌ Matrícula '$matricula' já está conectada em outro dispositivo. Desconecte o outro primeiro.",
  }));
  socket.close();
  return;
}
```

**Localização:** `professor_host_screen.dart` ~640  
**Trigger:** No JOIN  
**Feedback:** Clear instruction to disconnect other device

### 4.4 Multiple Rounds Detection (MC04 - Aluno Fantasma)

**Ameaça:** Aluno se conecta mas nunca está presente (padrão suspeito)

**Implementação:**

```dart
// Cada rodada gera novo PIN
// Se aluno ausente em 3 de 4 rodadas, padrão é detectável em análise CSV
// CSV possui coluna "metodo_validacao" para rastreamento
```

**Localização:** Não há bloqueio automático; apenas rastreamento em CSV  
**Análise:** Professor pode ver em `HistoricoScreen` padrão de ausências  
**Feedback:** CSV shows "Ausente" para múltiplas rodadas

---

## 5. Diagrama de Classe (Simplificado)

```
┌───────────────────────────────────┐
│         main.dart                 │
│  - runApp(MyApp)                  │
│  - MaterialApp(home: RoleSelect)   │
└───────────────┬─────────────────────┘
                │
    ┌───────────┴────────────┐
    │                         │
    v                         v
┌──────────────────┐   ┌────────────────────┐
│ ProfessorHostSc. │   │ AlunoJoinScreen    │
├──────────────────┤   ├────────────────────┤
│ _server: HttpSrv │   │ _nsdListener       │
│ _nsdService      │   │ _discoveredServices│
│ _connectedClients│   │ _channel: WS       │
│ _presencas       │   │ _ipController      │
│ _pinAttempts     │   │ _matriculaControl  │
│ _rodadas         │   │ _nomeController    │
├──────────────────┤   ├────────────────────┤
│ _startServer()   │   │ _startDiscovery()  │
│ _handleClientMsg │   │ _resolveService()  │
│ _validateSubnet  │   │ _connectToWS()     │
│ _exportarCSV()   │   └────────────────────┘
│ _startRodada()   │            │
│ _endRodada()     │            v
└──────────────────┘   ┌────────────────────┐
        ↓              │ AlunoWaitScreen    │
┌──────────────────┐   ├────────────────────┤
│ConfiguracoesScreen   │ _channel: WS       │
├──────────────────┤   │ _currentStatus     │
│ _rodadas: List   │   │ _endTimeMillis     │
│ _duracao: int    │   │ _countdown: int    │
├──────────────────┤   │ _pinInput: String  │
│ _addHorario()    │   ├────────────────────┤
│ _editHorario()   │   │ _listenToServer()  │
│ _removeHorario() │   │ _submitPin()       │
└──────────────────┘   │ _updateCountdown() │
        ↑              └────────────────────┘
        │
    ┌───┴──────┐
    │           │
    v           v
┌─────────┐  ┌──────────────┐
│Rodada   │  │HistoricoSc.  │
├─────────┤  ├──────────────┤
│ nome    │  │ _presencas   │
│ hora    │  ├──────────────┤
│ duracao │  │ _buildList() │
│ status  │  │ _sortByName()│
│ pin     │  └──────────────┘
└─────────┘
```

---

## 6. Tecnologias e Dependências

| Componente          | Tecnologia         | Versão   | Propósito                              |
| ------------------- | ------------------ | -------- | -------------------------------------- |
| **UI Framework**    | Flutter            | 3.9.2    | Desenvolvimento cross-platform         |
| **Linguagem**       | Dart               | 3.x      | Lógica de aplicação                    |
| **WebSocket**       | web_socket_channel | 2.4.x    | Comunicação em tempo real              |
| **NSD Discovery**   | nsd                | 2.5.x    | Descoberta de serviço na rede local    |
| **Persistência**    | shared_preferences | 2.x      | Armazenamento local                    |
| **Filesystem**      | path_provider      | 2.x      | Acesso a Downloads                     |
| **Permissões**      | permission_handler | 11.x     | Permissões runtime (location, storage) |
| **Formatação**      | intl               | 0.19.x   | Data/hora em português                 |
| **Logging**         | logging            | 1.2.x    | Debug output                           |
| **Tipografia**      | google_fonts       | 6.x      | Fontes customizadas                    |
| **Vibração**        | vibration          | 1.8.x    | Haptic feedback                        |
| **Material Design** | Material 3         | Built-in | Design system                          |

---

## 7. Decisões Arquiteturais Justificadas

### D1: Cliente-Servidor (vs. P2P)

**Razão:** Professor controla todas as rodadas centralmente; garante sincronismo.

### D2: WebSocket (vs. HTTP Polling)

**Razão:** Latência baixa, bidirecional, mais eficiente que polling.

### D3: NSD (vs. IP Hardcoded/QR Code)

**Razão:** Automático, não requer código externo para cada sala; escalável para múltiplos servidores.

### D4: PIN de 4 dígitos (vs. biometria/token)

**Razão:** Simples, não requer hardware adicional, adequado para educação.

### D5: SharedPreferences (vs. SQLite)

**Razão:** Dados simples (JSON), sem queries complexas; SharedPreferences é suficiente.

### D6: Rate Limiting local (vs. servidor central)

**Razão:** Sem depender de backend externo; efetivo contra força bruta.

### D7: Subnet validation (vs. GPS)

**Razão:** GPS é impreciso em ambientes internos; rede é garantida se na sala.

---

## 8. Segurança

### Ameaças Mitigadas

| Ameaça                           | Mitigação             | Implementado |
| -------------------------------- | --------------------- | ------------ |
| Aluno conecta remotamente (MC01) | SubnetCheck (/24)     | ✅           |
| Força bruta de PIN (MC02)        | Rate Limiting (3x)    | ✅           |
| Matrícula duplicada (MC03)       | Socket Uniqueness     | ✅           |
| Padrão suspeito (MC04)           | Múltiplas rodadas     | ✅           |
| Reconexão rápida pós-bloqueio    | Tentativas por rodada | ✅           |
| Vazamento de memória             | WebSocket.close()     | ✅           |

### Ameaças Futuras (N10)

- Geofencing com GPS (maior precisão)
- Device ID binding (previne múltiplos dispositivos/aluno)
- QR Code dinâmico por rodada
- Captura biométrica
- Backend Firebase com auditoria

---

## 9. Testes

### Testes Manuais (N3)

```
┌─ Cenário 1: Conexão bem-sucedida
│  1. Professor inicia app → seleciona "Professor"
│  2. Aluno inicia app → seleciona "Aluno" → NSD descobre servidor
│  3. Aluno digita nome/matrícula → conecta
│  4. Professor vê "+1 aluno conectado"
│  5. ESPERADO: ✅ Aluno aparece na lista

┌─ Cenário 2: PIN correto
│  1. Professor inicia rodada
│  2. Aluno recebe RODADA_ABERTA com PIN
│  3. Aluno digita PIN correto
│  4. ESPERADO: ✅ "Presença registrada"

┌─ Cenário 3: Rate Limiting (3x errado)
│  1. Professor inicia rodada
│  2. Aluno digita PIN errado 1x → "Tentativas: 2"
│  3. Aluno digita PIN errado 2x → "Tentativas: 1"
│  4. Aluno digita PIN errado 3x → "Acesso bloqueado"
│  5. ESPERADO: ❌ Bloqueado após 3

┌─ Cenário 4: Matrícula duplicada
│  1. Aluno A conecta com matrícula "202301"
│  2. Aluno B tenta conectar com mesma matrícula
│  3. ESPERADO: ❌ "Já conectada. Desconecte o outro primeiro"

┌─ Cenário 5: SubnetCheck (IP externo)
│  1. Professor em 192.168.1.50
│  2. Aluno conecta via IP fora da rede (ex: 10.0.0.10)
│  3. Aluno envia PIN
│  4. ESPERADO: ❌ "Validação de rede falhou"

┌─ Cenário 6: CSV Export
│  1. Professor completa 4 rodadas
│  2. Professor taps "Exportar CSV"
│  3. Arquivo criado em Downloads
│  4. ESPERADO: 4 linhas por aluno, status correto
```

---

## 10. Roadmap Futuro

### Fase N4 (Próximos passos)

- [ ] Diagramas UML (classe, componente, sequência, atividade)
- [ ] Wireframes/protótipos de telas
- [ ] Testes unitários (Dart test framework)
- [ ] Testes de integração (real device)

### Fase N5-10 (Médio prazo)

- [ ] Firebase backend para persistência de dados
- [ ] Geofencing com GPS
- [ ] Device ID binding (antifraude avançada)
- [ ] QR Code dinâmico
- [ ] CAPTCHA para múltiplas tentativas
- [ ] Dashboard web (professor visualizar dados remotamente)
- [ ] Relatório de presença em PDF
- [ ] Integração com LMS (Moodle, Canvas)

---

**Especificação arquitetural final para N3. Pronto para implementação e teste em dispositivo real.**
