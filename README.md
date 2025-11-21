# SmartPresence - Sistema de Controle de Presença em Tempo Real

**Versão:** 2.0  
**Status:** N3 (Trabalho Final) - Pronto para Teste em Dispositivo Real  
**Grupo:** CodeMonkeys Corp  
**Desenvolvedor:** José Henrique Bruhmuller

---

## 📋 Visão Geral

**SmartPresence** é um aplicativo Flutter que automatiza o controle de presença em ambientes educacionais. Um **professor** (servidor WebSocket) publica um serviço que **alunos** (clientes) descobrem automaticamente via NSD (Network Service Discovery). A presença é validada por:

1. **PIN Aleatório** — 4 dígitos gerados a cada rodada
2. **Validação de Rede** — SubnetCheck para garantir que o aluno está na sala
3. **Rate Limiting** — Máximo 3 tentativas de PIN por aluno por rodada
4. **Múltiplas Rodadas** — Detecta padrões suspeitos de ausência

### Características Principais

✅ **Descoberta Automática:** NSD descobre servidor professor sem hardcoding  
✅ **Tempo Real:** WebSocket garante latência baixa (< 1s)  
✅ **Segurança:** SubnetCheck, Rate Limiting, Socket Uniqueness  
✅ **Persistência:** Histórico salvo em SharedPreferences + CSV export  
✅ **Multi-Dispositivo:** Suporta múltiplos alunos simultâneos  
✅ **Android 11+:** Compatível com API 28+, permissões runtime  

---

## 🚀 Como Usar

### Instalação

```bash
# Clone o repositório
git clone https://github.com/seu-usuario/smartpresence.git
cd smartpresence

# Instale dependências
flutter pub get

# Compile para Android (dispositivo real)
flutter run -d <device-id>

# Ou execute em modo debug
flutter run
```

### Primeira Execução

#### 1️⃣ **Professor** (Dispositivo 1)
```
1. Abrir app
2. Selecionar "Professor"
3. Conceder permissão de localização
4. Ir para "Configurações" → Adicionar rodadas
   - Exemplo: "Rodada 1" às 19:30, duração 120s
5. Voltar para tela principal
6. Aguardar alunos conectarem
```

#### 2️⃣ **Aluno** (Dispositivo 2)
```
1. Abrir app
2. Selecionar "Aluno"
3. Conceder permissão de localização
4. NSD descobre "SmartPresence-Professor"
5. Selecionar servidor
6. Digitar Nome: "João Silva"
7. Digitar Matrícula: "202301"
8. Taps "CONECTAR"
9. Aguardar rodada abrir
```

#### 3️⃣ **Professor Inicia Rodada**
```
1. Taps "Iniciar Rodada 1"
2. PIN gerado (ex: 9876)
3. Broadcast enviado para alunos
```

#### 4️⃣ **Aluno Responde**
```
1. Recebe PIN na tela
2. Digita "9876"
3. Taps "CONFIRMAR"
4. Recebe: ✅ "Presença registrada!"
```

#### 5️⃣ **Professor Exporta CSV**
```
1. Após todas as rodadas
2. Taps "Exportar CSV"
3. Arquivo criado em Downloads
4. Arquivo: presenca_smartpresence_YYYYMMDD_HHmmss.csv
```

---

## 📁 Estrutura do Projeto

```
smartpresence/
├── lib/
│   ├── main.dart                        # Entry point
│   ├── models/
│   │   └── app_models.dart             # Rodada, AlunoConectado
│   └── screens/
│       ├── role_selection_screen.dart   # Seleção Professor/Aluno
│       ├── professor_host_screen.dart   # Servidor + Controle (1511 linhas)
│       ├── aluno_join_screen.dart       # Descoberta + Conexão (476 linhas)
│       ├── aluno_wait_screen.dart       # PIN Submission (437 linhas)
│       ├── configuracoes_screen.dart    # Settings (350 linhas)
│       └── historico_screen.dart        # Data View (350 linhas)
├── docs/
│   ├── requisitos_v2.md                 # Especificação (RFs/RNFs)
│   ├── antifraude.md                    # Ameaças e Mitigações
│   ├── arquitetura.md                   # Diagramas e Decisões
│   ├── csv_layout.md                    # Formato de Exportação
│   ├── plano_testes.md                  # Casos de Teste
│   ├── diagramas/                       # UML (vazio, pronto para preenchimento)
│   └── prototipos/                      # Wireframes (vazio, pronto para preenchimento)
├── android/
│   ├── app/src/main/AndroidManifest.xml # Permissões
│   └── ...
├── ios/
│   └── ...
├── pubspec.yaml                         # Dependências
├── analysis_options.yaml                # Lint rules
├── README.md                            # Este arquivo
└── smartpresence.iml                    # Configuração IDE
```

---

## 🔧 Dependências Principais

| Pacote | Versão | Propósito |
|--------|--------|----------|
| `flutter` | 3.9.2 | Framework UI |
| `web_socket_channel` | 2.4.x | WebSocket |
| `nsd` | 2.5.x | Network Service Discovery |
| `shared_preferences` | 2.x | Armazenamento local |
| `path_provider` | 2.x | Acesso a arquivos |
| `permission_handler` | 11.x | Permissões runtime |
| `intl` | 0.19.x | Localização (pt-BR) |
| `logging` | 1.2.x | Debug logging |
| `google_fonts` | 6.x | Tipografia |
| `vibration` | 1.8.x | Haptic feedback |

---

## 📱 Requisitos do Dispositivo

### Mínimo
- **Android:** API 28 (Android 9.0)
- **RAM:** 2 GB
- **Espaço:** 100 MB

### Recomendado
- **Android:** API 30+ (Android 11+)
- **RAM:** 4 GB
- **WiFi:** 2.4 GHz na mesma sub-rede (/24)

### Permissões Requeridas
```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" /> <!-- NSD -->
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" /> <!-- NSD -->
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" /> <!-- CSV -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" /> <!-- CSV -->
```

---

## 🔒 Segurança e Antifraude

### Mitigações Implementadas

#### 1. **SubnetCheck** (IP Validation)
- **Ameaça:** Aluno conecta remotamente
- **Solução:** Valida que cliente está na mesma sub-rede /24
- **Implementação:** Compara primeiros 3 octetos do IP
- **Localização:** `professor_host_screen.dart` linha ~850

#### 2. **Rate Limiting** (Força Bruta)
- **Ameaça:** 10.000 PINs possíveis (ataque brute force)
- **Solução:** Máximo 3 tentativas por aluno por rodada
- **Implementação:** `_pinAttempts` Map rastreia tentativas
- **Localização:** `professor_host_screen.dart` linhas ~708-800

#### 3. **Socket Uniqueness** (Matrícula Duplicada)
- **Ameaça:** Mesma matrícula em 2 dispositivos
- **Solução:** Rejeita segunda conexão; fecha socket anterior
- **Feedback:** "Matrícula já está conectada. Desconecte o outro primeiro."
- **Localização:** `professor_host_screen.dart` linha ~640

#### 4. **Multiple Rounds Detection** (Padrão Suspeito)
- **Ameaça:** Aluno se conecta mas nunca está presente
- **Solução:** 4 rodadas detectam padrão; CSV exporta para análise
- **Implementação:** Rastreia presença/ausência por rodada
- **Análise:** Professor pode ver em HistoricoScreen

---

## 📊 Protocolo WebSocket (JSON)

### Servidor → Cliente

```json
// Conexão bem-sucedida
{"command": "JOIN_SUCCESS", "message": "Bem-vindo, João!"}

// Rodada aberta
{"command": "RODADA_ABERTA", "rodada": "Rodada 1", "pin": "9876", "endTimeMillis": 1700500542000, "duracao_segundos": 120}

// Presença confirmada
{"command": "PRESENCA_OK", "message": "✅ Presença registrada!"}

// PIN incorreto
{"command": "PRESENCA_FALHA", "message": "PIN incorreto. Tentativas restantes: 2"}

// Rodada encerrada
{"command": "RODADA_FECHADA", "message": "Rodada 1 finalizada."}

// Erro
{"command": "ERROR", "message": "❌ Matrícula já está conectada..."}
```

### Cliente → Servidor

```json
// Solicitação de conexão
{"command": "JOIN", "matricula": "202301", "nome": "João Silva"}

// Envio de PIN
{"command": "SUBMIT_PIN", "pin": "9876", "rodada": "Rodada 1", "matricula": "202301"}
```

---

## 📄 Formato CSV de Exportação

**Nome:** `presenca_smartpresence_20251120_193500.csv`  
**Localização:** `/storage/emulated/0/Downloads/`

```csv
"matricula","nome","data","rodada","status","gravado_em","notas","metodo_validacao"
"202301","João Silva","2025-11-20","Rodada 1","Presente","19:35:42","","SubnetCheck"
"202302","Maria Santos","2025-11-20","Rodada 1","Falhou PIN","19:36:10","3 tentativas","SubnetCheck + Rate Limit"
"202303","Pedro Oliveira","2025-11-20","Rodada 1","Ausente","20:00:00","Nenhuma tentativa","SubnetCheck"
"202301","João Silva","2025-11-20","Rodada 2","Presente","19:55:42","","SubnetCheck"
```

**Colunas:**
- `matricula` — ID do aluno
- `nome` — Nome completo
- `data` — Data (YYYY-MM-DD)
- `rodada` — Nome da rodada
- `status` — Presente, Ausente, Falhou PIN, Falhou PIN (Rede)
- `gravado_em` — Hora (HH:mm:ss)
- `notas` — Observações (opcional)
- `metodo_validacao` — SubnetCheck, Rate Limit, etc.

---

## 🧪 Testes

### Teste Rápido (5 min)

```bash
# Compilar para Android
flutter build apk

# Transferir para 2 dispositivos
adb -s <device1-id> install build/app/outputs/apk/release/app-release.apk
adb -s <device2-id> install build/app/outputs/apk/release/app-release.apk

# Executar em ambos
adb -s <device1-id> shell am start -n com.smartpresence/com.smartpresence.MainActivity
adb -s <device2-id> shell am start -n com.smartpresence/com.smartpresence.MainActivity
```

### Teste Completo

Vide **docs/plano_testes.md** para 12 casos de teste funcionais + non-funcionais.

### Checklist de Validação

- [ ] Dispositivos conectados na mesma WiFi
- [ ] Permissão de localização concedida
- [ ] NSD discovery funciona (< 5s)
- [ ] Aluno conecta com sucesso
- [ ] PIN correto aceito
- [ ] Rate limiting bloqueia após 3 tentativas
- [ ] CSV exportado com dados corretos
- [ ] Múltiplas rodadas funcionam
- [ ] Sem crashes ou erros de memória

---

## 🐛 Troubleshooting

### NSD Não Descobre Servidor

**Causa:** Dispositivos em redes diferentes ou permissão não concedida

**Solução:**
```
1. Verificar se ambos na mesma WiFi: Configurações → WiFi
2. Ambos com localização ON: Configurações → Localização
3. Fechar e reabrir app
4. Se persistir, usar fallback manual (IP:Porta)
```

### Rate Limiting Bloqueia Aluno Legítimo

**Causa:** 3+ tentativas de PIN errado na mesma rodada

**Solução:**
```
1. Aguardar próxima rodada (contador reset por rodada)
2. Ou professor encerra rodada e inicia nova
```

### CSV Não Aparece em Downloads

**Causa:** Permissão de storage não concedida

**Solução:**
```
1. Configurações → Aplicativos → SmartPresence → Permissões
2. Armazenamento: Ativar "Permitir acesso a todos os arquivos"
3. Tentar export novamente
```

### WebSocket Desconecta Abrupto

**Causa:** WiFi instável ou timeout de conexão

**Solução:**
```
1. Reconectar WiFi
2. Professor reinicia servidor
3. Aluno reconecta
```

---

## 📚 Documentação Completa

- **[requisitos_v2.md](docs/requisitos_v2.md)** — Especificação N3 (RFs/RNFs/RNs)
- **[antifraude.md](docs/antifraude.md)** — Ameaças, mitigações, trade-offs
- **[arquitetura.md](docs/arquitetura.md)** — Diagramas, componentes, fluxos
- **[csv_layout.md](docs/csv_layout.md)** — Formato detalhado de exportação
- **[plano_testes.md](docs/plano_testes.md)** — 15 casos de teste com checklist

---

## 📝 Melhorias Aplicadas (N2 → N3)

✅ Permissões de localização adicionadas (NSD em Android 11+)  
✅ Request de permissão em runtime (Permission.location)  
✅ WebSocket closure seguro (try/catch em dispose)  
✅ Rate limiting implementado (3 tentativas/rodada)  
✅ Mensagem de erro melhorada (matrícula duplicada)  
✅ Documentação completa (requisitos, antifraude, arquitetura, CSV, testes)  
✅ Diretório docs/ estruturado com suporte para diagramas e protótipos  

---

## 🎯 Próximos Passos (Após N3)

### Fase N4 (Refinamento)
- [ ] Adicionar diagramas UML (classe, componente, sequência)
- [ ] Protótipos de wireframe (screenshots/descriptions)
- [ ] Testes unitários (Dart test framework)
- [ ] Testes de integração em dispositivo real

### Fase N5-10 (Funcionalidades Avançadas)
- [ ] Firebase backend (persistência centralizada)
- [ ] Geofencing com GPS (maior precisão)
- [ ] QR Code dinâmico por rodada
- [ ] Device ID binding (antifraude)
- [ ] Dashboard web (professor visualizar remotamente)
- [ ] Integração com LMS (Moodle, Canvas)
- [ ] CAPTCHA para múltiplas tentativas

---

## 👥 Contribuidores

**CodeMonkeys Corp**
- José Henrique Bruhmuller (Desenvolvedor Principal)

---

## 📄 Licença

[Defina a licença apropriada — MIT, Apache 2.0, etc.]

---

## 📞 Suporte

Para dúvidas ou problemas:
1. Verifique [plano_testes.md](docs/plano_testes.md) para troubleshooting
2. Consulte [arquitetura.md](docs/arquitetura.md) para entender fluxos
3. Abra issue no GitHub ou entre em contato com o desenvolvedor

---

**SmartPresence v2.0 — Pronto para N3 (Teste em Dispositivo Real Recomendado)**
