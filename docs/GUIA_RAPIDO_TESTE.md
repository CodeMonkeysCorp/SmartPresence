# Guia Rápido de Teste - SmartPresence N3

**Versão:** 2.0  
**Data:** 20 de Novembro de 2025  
**Tempo Estimado:** 30-45 minutos (teste completo)

---

## ⚡ 5 Minutos: Setup Rápido

### Pré-requisitos

```
✅ 2 dispositivos Android reais (API 28+)
✅ Ambos conectados na mesma WiFi 2.4 GHz
✅ Ambos com localização ativada (Settings > Location)
✅ App compilada (flutter build apk --release) ou flutter run
```

### Instalação

```bash
# Terminal 1: Compilar
cd ~/Desktop/Projetos/SmartPresence
flutter build apk --release

# Terminal 2: Instalar em Professor (Device 1)
adb -s <device1-id> install -r build/app/outputs/apk/release/app-release.apk

# Terminal 3: Instalar em Aluno (Device 2)
adb -s <device2-id> install -r build/app/outputs/apk/release/app-release.apk

# Ou usar flutter run para debug:
flutter run -d <device1-id>  # Em outro terminal
flutter run -d <device2-id>
```

---

## 🚀 10 Minutos: Teste Básico (T4 - PIN Correto)

### Professor (Device 1)

| Passo | Ação                             | Esperado                         | ✓   |
| ----- | -------------------------------- | -------------------------------- | --- |
| 1     | Abrir app                        | RoleSelectionScreen              | ☐   |
| 2     | Taps "Professor"                 | ProfessorHostScreen carrega      | ☐   |
| 3     | Concede permissão de localização | Dialog desaparece                | ☐   |
| 4     | Aguarda 3-5s                     | NSD publicado (sem erro visível) | ☐   |
| 5     | Vê botão "Configurações"         | Acessa ConfiguracoesScreen       | ☐   |
| 6     | Taps "+" → Adiciona rodada       | Nome: "Rodada 1", Duração: 30s   | ☐   |
| 7     | Volta para tela principal        | Vê "Iniciar Rodada 1"            | ☐   |

### Aluno (Device 2)

| Passo | Ação                             | Esperado                                   | ✓   |
| ----- | -------------------------------- | ------------------------------------------ | --- |
| 1     | Abrir app                        | RoleSelectionScreen                        | ☐   |
| 2     | Taps "Aluno"                     | AlunoJoinScreen carrega                    | ☐   |
| 3     | Concede permissão de localização | Dialog desaparece                          | ☐   |
| 4     | Aguarda 3-5s                     | "SmartPresence-Professor" aparece na lista | ☐   |
| 5     | Taps no servidor                 | IP e Porta populados                       | ☐   |
| 6     | Digita nome e matrícula          | "João Silva", "202301"                     | ☐   |
| 7     | Taps "CONECTAR"                  | Navega para AlunoWaitScreen                | ☐   |
| 8     | Vê mensagem                      | "Aguardando rodada..."                     | ☐   |

### Professor (Device 1) - Inicia Rodada

| Passo | Ação                    | Esperado                                      | ✓   |
| ----- | ----------------------- | --------------------------------------------- | --- |
| 1     | Vê aluno conectado      | "+1 aluno conectado" ou "João Silva (202301)" | ☐   |
| 2     | Taps "Iniciar Rodada 1" | PIN gerado (ex: 9876)                         | ☐   |
| 3     | Vê mensagem             | "Rodada 1 ativa (PIN: 9876)"                  | ☐   |

### Aluno (Device 2) - Responde PIN

| Passo | Ação               | Esperado                                         | ✓   |
| ----- | ------------------ | ------------------------------------------------ | --- |
| 1     | Recebe rodada      | "Rodada 1 aberta!" + Countdown (30s → 29s → ...) | ☐   |
| 2     | Vê teclado         | Dígitos 0-9, LIMPAR, CONFIRMAR                   | ☐   |
| 3     | Digita PIN correto | "9876"                                           | ☐   |
| 4     | Taps "CONFIRMAR"   | Aguarda resposta do servidor                     | ☐   |
| 5     | Recebe sucesso     | ✅ "Presença registrada!"                        | ☐   |
| 6     | Sente vibração     | Haptic feedback (vibração)                       | ☐   |

### Professor (Device 1) - Vê Resultado

| Passo | Ação        | Esperado                          | ✓   |
| ----- | ----------- | --------------------------------- | --- |
| 1     | UI atualiza | Status "João Silva" → "Presente"  | ☐   |
| 2     | Vê feedback | Indicador visual (cor verde ou ✓) | ☐   |

---

## 🔒 5 Minutos: Teste Rate Limiting (T5)

**Pré-requisito:** Rodada 1 completa. Professor inicia Rodada 2 com novo PIN (ex: 1234)

| Passo | Ação                               | Esperado                                                  | ✓   |
| ----- | ---------------------------------- | --------------------------------------------------------- | --- |
| 1     | Aluno digita PIN errado (ex: 0000) | "PIN incorreto. Tentativas restantes: 2"                  | ☐   |
| 2     | Aluno digita PIN errado (ex: 5555) | "PIN incorreto. Tentativas restantes: 1"                  | ☐   |
| 3     | Aluno digita PIN errado (ex: 9999) | "❌ Máximo de tentativas (3) excedido. Acesso bloqueado." | ☐   |
| 4     | Aluno tenta novamente              | Bloqueado (botão desativado ou mensagem)                  | ☐   |
| 5     | Professor termina Rodada 2         | Status aluno → "Falhou PIN"                               | ☐   |
| 6     | Professor inicia Rodada 3          | Aluno pode tentar novamente (reset)                       | ☐   |

---

## 📊 10 Minutos: Teste CSV Export (T11)

**Pré-requisito:** 2 rodadas completadas (Rodada 1: Presente, Rodada 2: Falhou PIN)

| Passo | Ação                            | Esperado                                                                      | ✓   |
| ----- | ------------------------------- | ----------------------------------------------------------------------------- | --- |
| 1     | Professor taps "Exportar CSV"   | Dialog de permissão (primeira vez)                                            | ☐   |
| 2     | Professor concede permissão     | Storage Permission granted                                                    | ☐   |
| 3     | Aguarda 2-3s                    | Notificação: "CSV exportado para: /storage/.../presenca*smartpresence*\*.csv" | ☐   |
| 4     | Abra gerenciador de arquivos    | Navegue para Downloads                                                        | ☐   |
| 5     | Veja arquivo CSV                | "presenca_smartpresence_YYYYMMDD_HHmmss.csv"                                  | ☐   |
| 6     | Abra em planilha (Excel/Sheets) | Arquivo abre sem erro                                                         | ☐   |
| 7     | Valide colunas                  | matricula, nome, data, rodada, status, gravado_em, notas, metodo_validacao    | ☐   |
| 8     | Valide dados                    | 1 aluno × 2 rodadas = 2 linhas (+ header)                                     | ☐   |
| 9     | Valide status                   | Rodada 1: Presente, Rodada 2: Falhou PIN                                      | ☐   |

---

## 🎯 Cenário Completo (30 min)

```
TEMPO TOTAL: ~30-40 minutos

T4 (5 min):    ✅ PIN Correto
T5 (5 min):    🔒 Rate Limiting
T1-T3 (5 min): 🚀 Inicialização + Discovery + Permissões
T8 (5 min):    ⏱️ Encerramento Automático (se duração 30s)
T11 (5 min):   📊 CSV Export
T12 (2 min):   🔌 Desconexão Segura
BUFFER (3 min):Troubleshooting

TOTAL: ~30 min
```

### Checklist Mínimo (para aprovação)

- [ ] T1 (Inicialização) → ✅
- [ ] T2-T3 (Discovery + Permissões) → ✅
- [ ] T4 (PIN Correto) → ✅
- [ ] T5 (Rate Limiting) → ✅
- [ ] T11 (CSV Export) → ✅
- [ ] CSV validado em planilha → ✅

**Se todos acima passarem: ✅ PROJETO FUNCIONA**

---

## 🐛 Troubleshooting Rápido

### ❌ "SmartPresence não aparece na descoberta"

```
1. Verifique se ambos na mesma WiFi 2.4 GHz
2. Verifique se localização está ON em ambos
3. Feche e reabra app do Aluno
4. Se persistir, use fallback: taps em "Conexão Manual" e digita IP:Porta
```

### ❌ "Permissão de localização não foi pedida"

```
1. Vá para Settings → Apps → SmartPresence → Permissions
2. Ative Location (Localização)
3. Reabra app
```

### ❌ "CSV não aparece em Downloads"

```
1. Vá para Settings → Apps → SmartPresence → Permissions
2. Ative Storage (Armazenamento)
3. Tente export novamente
```

### ❌ "WebSocket desconectou"

```
1. Aluno taps "Reconectar"
2. Ou feche app e reabra
3. Professor verifica se está ainda rodando (não foi encerrado acidentalmente)
```

### ❌ "Rate limit bloqueia aluno legítimo"

```
1. Professor inicia nova rodada (contador reset por rodada)
2. Aluno pode tentar novamente em Rodada 2+
```

---

## 📸 Screenshots para Documentação

### O que fotografar/descrever

```
1. RoleSelectionScreen → "Professor" selecionado
2. ProfessorHostScreen → "+1 aluno conectado"
3. AlunoJoinScreen → "SmartPresence-Professor" descoberto
4. AlunoWaitScreen → PIN input com countdown
5. Sucesso → ✅ "Presença registrada!"
6. Rate Limit → ❌ "Tentativas restantes: 1"
7. CSV em Downloads → nome e conteúdo visível
8. CSV em Excel → 8 colunas, dados corretos
```

---

## ✅ Validação Final

Após completar teste, preencha:

```
DATA: ___/___/2025
DISPOSITIVO PROFESSOR: _________________ (modelo)
DISPOSITIVO ALUNO: _________________ (modelo)
VERSÃO ANDROID: _____ (API) em ambos

TESTES EXECUTADOS:
[ ] T1 - Inicialização
[ ] T2-T3 - Discovery + Permissões
[ ] T4 - PIN Correto
[ ] T5 - Rate Limiting
[ ] T8 - Encerramento
[ ] T11 - CSV Export
[ ] T12 - Desconexão

RESULTADO FINAL: ✅ PASSOU / ❌ FALHOU / ⚠️ COM RESSALVAS

OBSERVAÇÕES:
_________________________________________________________________
_________________________________________________________________

ASSINADO: __________________________ DATA: ___/___/2025
```

---

## 📚 Referências Rápidas

- **Plano Completo de Testes:** `docs/plano_testes.md`
- **CSV Layout:** `docs/csv_layout.md`
- **Antifraude:** `docs/antifraude.md`
- **Troubleshooting Detalhado:** `docs/README.md` (seção Troubleshooting)

---

**Guia Rápido de Teste — SmartPresence v2.0**

_Tempo estimado: 30-45 minutos | Complexidade: Baixa | Resultado esperado: ✅ PASSOU_
