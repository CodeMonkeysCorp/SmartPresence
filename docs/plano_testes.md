# Plano de Testes - SmartPresence N3

**Versão:** 2.0  
**Data:** 20 de Novembro de 2025  
**Executores:** CodeMonkeys Corp (José Henrique Bruhmuller)  
**Ambiente:** 2 dispositivos Android reais (mín. API 28, recomendado API 30+)

---

## 1. Setup Pré-teste

### 1.1 Requisitos de Ambiente

```
✅ 2 Dispositivos Android reais (não emulador)
  - Professor: API 28+ (recomendado 30+), 4GB RAM mín.
  - Aluno: API 28+ (recomendado 30+), 4GB RAM mín.

✅ Conectados à mesma rede WiFi
  - SSID: mesmo nome
  - Frequência: 2.4 GHz (mais compatível)
  - IP na mesma sub-rede (ex: 192.168.1.x)

✅ Permissões Concedidas
  - Professor: Location (para NSD), Storage (CSV export)
  - Aluno: Location (para NSD)

✅ App Compilado
  - Versão de release ou debug
  - Sem erros de compilação
  - Versão 2.0 com melhorias aplicadas

✅ Documentação Disponível
  - requisitos_v2.md
  - antifraude.md
  - arquitetura.md
  - csv_layout.md
  - Este documento (testes)
```

### 1.2 Checklist Pré-teste

- [ ] Ambos os dispositivos na mesma rede WiFi
- [ ] Ambos com localização habilitada (Location Services ON)
- [ ] App instalado e compilado sem erros
- [ ] Tinta/papel para anotar resultados
- [ ] Câmera/vídeo para documentar (opcional)
- [ ] Git repository limpo (`git status` sem mudanças incommitted)

---

## 2. Testes Funcionais (Cobertura RF)

### T1: Inicialização e Seleção de Papel (RF01)

**Descrição:** App inicia corretamente e permite seleção de papel.

| Passo | Ação                     | Esperado                                      | Status        |
| ----- | ------------------------ | --------------------------------------------- | ------------- |
| 1     | Abrir app no dispositivo | Tela de seleção (RoleSelectionScreen) exibida | ☐ Pass ☐ Fail |
| 2     | Taps "Professor"         | Navega para ProfessorHostScreen               | ☐ Pass ☐ Fail |
| 3     | Volta (back button)      | Retorna para seleção                          | ☐ Pass ☐ Fail |
| 4     | Taps "Aluno"             | Navega para AlunoJoinScreen                   | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

### T2: Discovery e Conexão de Aluno (RF02, RF03)

**Descrição:** Aluno descobre servidor professor via NSD e conecta.

**Pré-requisito:** Professor iniciado e aguardando conexões

| Passo | Ação                           | Esperado                                              | Status        |
| ----- | ------------------------------ | ----------------------------------------------------- | ------------- |
| 1     | Aluno: AlunoJoinScreen aparece | Tela com lista de serviços descobertos                | ☐ Pass ☐ Fail |
| 2     | Aluno: Aguarda 3-5s            | SmartPresence-Professor aparece na lista              | ☐ Pass ☐ Fail |
| 3     | Aluno: Seleciona servidor      | IP e Porta populados automaticamente                  | ☐ Pass ☐ Fail |
| 4     | Aluno: Digita nome e matrícula | Campos aceitam entrada (ex: João Silva, 202301)       | ☐ Pass ☐ Fail |
| 5     | Aluno: Taps "CONECTAR"         | Navega para AlunoWaitScreen                           | ☐ Pass ☐ Fail |
| 6     | Professor: UI atualiza         | "+1 aluno conectado" ou "João Silva (202301)" aparece | ☐ Pass ☐ Fail |
| 7     | Aluno: AlunoWaitScreen         | Exibe "Aguardando rodada..."                          | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

### T3: Permissão de Localização (RF03 - Antifraude)

**Descrição:** Aplicativo pede e respeita permissão de localização.

| Passo | Ação                              | Esperado                                      | Status        |
| ----- | --------------------------------- | --------------------------------------------- | ------------- |
| 1     | Aluno: Abre app pela primeira vez | Dialog de permissão: "Allow location access?" | ☐ Pass ☐ Fail |
| 2     | Aluno: Taps "Deny"                | UI exibe erro; Discovery não inicia           | ☐ Pass ☐ Fail |
| 3     | Aluno: Volta e taps "Allow"       | Discovery inicia; servidores descobertos      | ☐ Pass ☐ Fail |
| 4     | Professor: Permissão já concedida | Sem dialog; NSD publica imediatamente         | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

### T4: Rodada e PIN (RF05, RF06)

**Descrição:** Professor inicia rodada, aluno recebe PIN, envia resposta.

**Pré-requisito:** 1+ alunos conectados

| Passo | Ação                                 | Esperado                                   | Status        |
| ----- | ------------------------------------ | ------------------------------------------ | ------------- |
| 1     | Professor: Taps "Iniciar Rodada 1"   | UI exibe "Rodada 1 ativa (PIN: 9876)"      | ☐ Pass ☐ Fail |
| 2     | Aluno: Recebe RODADA_ABERTA          | Countdown iniciado (ex: 120s → 119s → ...) | ☐ Pass ☐ Fail |
| 3     | Aluno: Vê teclado numérico           | Teclado com 0-9 e LIMPAR/CONFIRMAR         | ☐ Pass ☐ Fail |
| 4     | Aluno: Digita PIN correto (ex: 9876) | Campo mostra 4 dígitos                     | ☐ Pass ☐ Fail |
| 5     | Aluno: Taps "CONFIRMAR"              | Envia SUBMIT_PIN; aguarda resposta         | ☐ Pass ☐ Fail |
| 6     | Aluno: Recebe PRESENCA_OK            | Exibe ✅ "Presença registrada!"            | ☐ Pass ☐ Fail |
| 7     | Aluno: Haptic feedback               | Vibração sentida no dispositivo            | ☐ Pass ☐ Fail |
| 8     | Professor: Histórico atualiza        | Status de João Silva (202301) → "Presente" | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

### T5: Rate Limiting (RF09 - Antifraude)

**Descrição:** Após 3 PIN incorretos, aluno é bloqueado.

**Pré-requisito:** Rodada ativa

| Passo | Ação                                             | Esperado                                                            | Status        |
| ----- | ------------------------------------------------ | ------------------------------------------------------------------- | ------------- |
| 1     | Aluno: Digita PIN errado (ex: 1234)              | Feedback: ❌ "PIN incorreto. Tentativas restantes: 2"               | ☐ Pass ☐ Fail |
| 2     | Aluno: Limpa e digita novo PIN errado (ex: 5678) | Feedback: ❌ "PIN incorreto. Tentativas restantes: 1"               | ☐ Pass ☐ Fail |
| 3     | Aluno: Digita novo PIN errado (ex: 9999)         | Feedback: ❌ "Máximo de tentativas (3) excedido. Acesso bloqueado." | ☐ Pass ☐ Fail |
| 4     | Aluno: Tenta novamente nesta rodada              | Botão CONFIRMAR desativado ou msg de bloqueio                       | ☐ Pass ☐ Fail |
| 5     | Professor: Histórico                             | Status → "Falhou PIN" para este aluno                               | ☐ Pass ☐ Fail |
| 6     | Professor: Inicia Rodada 2                       | Aluno pode tentar novamente (rate limit reset)                      | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

### T6: Validação de Sub-rede (RF10 - Antifraude)

**Descrição:** Se aluno conecta de IP fora da rede, presença é rejeitada.

**Pré-requisito:** Professor em 192.168.1.x (exemplo)

| Passo | Ação                                       | Esperado                                     | Status        |
| ----- | ------------------------------------------ | -------------------------------------------- | ------------- |
| 1     | Professor: IP do servidor = 192.168.1.50   | Mostrado em ProfessorHostScreen              | ☐ Pass ☐ Fail |
| 2     | Aluno: Conecta com IP = 192.168.1.100      | Conexão aceita (mesmo /24)                   | ☐ Pass ☐ Fail |
| 3     | Aluno: Envia PIN correto                   | PRESENCA_OK recebido                         | ☐ Pass ☐ Fail |
| 4     | _Simulação_: Editar req. com IP = 10.0.0.1 | SubnetCheck retorna false                    | ☐ Pass ☐ Fail |
| 5     | Feedback: "Validação de rede falhou"       | Presença registrada como "Falhou PIN (Rede)" | ☐ Pass ☐ Fail |

**Nota:** Requer emulação de IP ou teste com dois WiFis diferentes.

**Resultado:** ☐ Passou ☐ Falhou

---

### T7: Matrícula Duplicada (RF11 - Antifraude)

**Descrição:** Rejeitar segunda conexão com mesma matrícula.

**Pré-requisito:** Aluno A conectado com matrícula 202301

| Passo | Ação                                         | Esperado                                           | Status        |
| ----- | -------------------------------------------- | -------------------------------------------------- | ------------- |
| 1     | Aluno B: Tenta conectar com matrícula 202301 | Erro: ❌ "Matrícula '202301' já está conectada..." | ☐ Pass ☐ Fail |
| 2     | Aluno B: Desconecta (back/close app)         | Aluno A pode continuar                             | ☐ Pass ☐ Fail |
| 3     | Aluno B: Reconecta com mesma matrícula       | Conexão aceita (socket anterior foi liberado)      | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

### T8: Encerramento de Rodada (RF12)

**Descrição:** Após timeout, rodada encerra automaticamente.

**Pré-requisito:** Rodada iniciada com duração 30s (para teste rápido)

| Passo | Ação                                       | Esperado                                 | Status        |
| ----- | ------------------------------------------ | ---------------------------------------- | ------------- |
| 1     | Professor: Inicia rodada (duração 30s)     | Timer começou                            | ☐ Pass ☐ Fail |
| 2     | Aluno: Countdown visível (30s → 29s → ...) | UI atualiza a cada segundo               | ☐ Pass ☐ Fail |
| 3     | Aluno: NÃO envia PIN                       | Aguarda encerramento                     | ☐ Pass ☐ Fail |
| 4     | Após 30s: Rodada encerra                   | Mensagem: "Rodada 1 finalizada"          | ☐ Pass ☐ Fail |
| 5     | Professor: Histórico                       | Status aluno = "Ausente"                 | ☐ Pass ☐ Fail |
| 6     | Aluno: Aguarda próxima rodada              | Mensagem: "Aguardando próxima rodada..." | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

### T9: Múltiplas Rodadas (RF13 - Antifraude)

**Descrição:** Sistema suporta 4 rodadas e detecta padrão de ausências.

**Pré-requisito:** Configurações com 4 rodadas de 30s cada

| Passo | Ação                       | Esperado                             | Status        |
| ----- | -------------------------- | ------------------------------------ | ------------- |
| 1     | Professor: Inicia Rodada 1 | Aluno A não participa (ausente)      | ☐ Pass ☐ Fail |
| 2     | Professor: Inicia Rodada 2 | Aluno A não participa (ausente)      | ☐ Pass ☐ Fail |
| 3     | Professor: Inicia Rodada 3 | Aluno A participa (PIN correto)      | ☐ Pass ☐ Fail |
| 4     | Professor: Inicia Rodada 4 | Aluno A não participa (ausente)      | ☐ Pass ☐ Fail |
| 5     | Histórico: Exibe padrão    | 3 ausências + 1 presente = suspeito? | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

### T10: Histórico e Visualização (RF14)

**Descrição:** HistoricoScreen exibe histórico de presença corretamente.

**Pré-requisito:** 2+ rodadas completas com 2+ alunos

| Passo | Ação                        | Esperado                                       | Status        |
| ----- | --------------------------- | ---------------------------------------------- | ------------- |
| 1     | Professor: Taps "Histórico" | HistoricoScreen abre                           | ☐ Pass ☐ Fail |
| 2     | Interface: Lista expandível | Alunos listad com nome/matrícula               | ☐ Pass ☐ Fail |
| 3     | Expand: João Silva (202301) | Exibe todas as rodadas e status                | ☐ Pass ☐ Fail |
| 4     | Status corretos             | Rodada 1: Presente, Rodada 2: Falhou PIN, etc. | ☐ Pass ☐ Fail |
| 5     | Expandir outro aluno        | Dados diferentes exibidos corretamente         | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

### T11: Exportação CSV (RF15)

**Descrição:** Exportar histórico para CSV em Downloads.

**Pré-requisito:** 4 rodadas completas, 2+ alunos

| Passo | Ação                                    | Esperado                                                                      | Status        |
| ----- | --------------------------------------- | ----------------------------------------------------------------------------- | ------------- |
| 1     | Professor: Taps "Exportar CSV"          | Dialog de permissão (se primeira vez)                                         | ☐ Pass ☐ Fail |
| 2     | Professor: Concede permissão de storage | Arquivo criado                                                                | ☐ Pass ☐ Fail |
| 3     | Notificação                             | "CSV exportado para: /storage/.../presenca_smartpresence_YYYYMMDD_HHmmss.csv" | ☐ Pass ☐ Fail |
| 4     | Acesse arquivo (gerenciador)            | Arquivo existe em Downloads                                                   | ☐ Pass ☐ Fail |
| 5     | Abra CSV (planilha)                     | Codificação UTF-8 OK; 8 colunas visíveis                                      | ☐ Pass ☐ Fail |
| 6     | Validar colunas                         | matricula, nome, data, rodada, status, gravado_em, notas, metodo_validacao    | ☐ Pass ☐ Fail |
| 7     | Validar dados                           | 2 alunos × 4 rodadas = 8 linhas (+ header)                                    | ☐ Pass ☐ Fail |
| 8     | Status corretos                         | Presente, Falhou PIN, Ausente preenchidos                                     | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

### T12: Desconexão Segura (RF16 - Antifraude)

**Descrição:** WebSocket fecha adequadamente ao sair.

| Passo | Ação                              | Esperado                                           | Status        |
| ----- | --------------------------------- | -------------------------------------------------- | ------------- |
| 1     | Aluno: Em AlunoWaitScreen         | Conexão ativa                                      | ☐ Pass ☐ Fail |
| 2     | Aluno: Taps "Sair" ou back button | AlunoWaitScreen dispose() chamado                  | ☐ Pass ☐ Fail |
| 3     | Aluno: WebSocket fechado          | Sem erro "double close" no console                 | ☐ Pass ☐ Fail |
| 4     | Professor: Aluno saiu             | Mensagem "Aluno desconectado" ou removido da lista | ☐ Pass ☐ Fail |
| 5     | Professor: Taps "Sair"            | HttpServer encerrado; NSD deregistrado             | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

## 3. Testes Não-Funcionais (Cobertura RNF)

### RNF1: Usabilidade (Interface Intuitiva)

| Critério             | Teste            | Esperado                                   | Status        |
| -------------------- | ---------------- | ------------------------------------------ | ------------- |
| **Teclado Numérico** | Aluno digita PIN | Dígitos aparecem em tempo real             | ☐ Pass ☐ Fail |
| **Botão CONFIRMAR**  | Aluno clica      | PIN é enviado imediatamente                | ☐ Pass ☐ Fail |
| **Countdown**        | Timer atualiza   | Cada segundo é visível (120s → 119s → ...) | ☐ Pass ☐ Fail |
| **Feedback Visual**  | Sucesso/falha    | Cores e ícones (✅/❌) diferenciam         | ☐ Pass ☐ Fail |
| **Haptic Feedback**  | PIN correto      | Vibração sentida                           | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

### RNF2: Performance (Latência Baixa)

| Métrica               | Teste                    | Esperado                    | Status        |
| --------------------- | ------------------------ | --------------------------- | ------------- |
| **Descoberta NSD**    | Aluno aguarda servidores | < 5 segundos                | ☐ Pass ☐ Fail |
| **Conexão WebSocket** | Aluno conecta            | < 2 segundos                | ☐ Pass ☐ Fail |
| **Envio de PIN**      | Aluno envia PIN          | Resposta < 1 segundo        | ☐ Pass ☐ Fail |
| **Atualização UI**    | Professor envia rodada   | Aluno recebe < 1 segundo    | ☐ Pass ☐ Fail |
| **CSV Export**        | 4 alunos × 4 rodadas     | Arquivo criado < 5 segundos | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

### RNF3: Reliability (Sem Crashes)

| Cenário                  | Teste                 | Esperado                               | Status        |
| ------------------------ | --------------------- | -------------------------------------- | ------------- |
| **Conexão Fraca**        | WiFi instável         | App não trava; reconecta ou exibe erro | ☐ Pass ☐ Fail |
| **Múltiplas Rodadas**    | 4 rodadas seguidas    | App permanece estável                  | ☐ Pass ☐ Fail |
| **Muitos Alunos**        | 5+ alunos conectados  | Sem memory leak ou crash               | ☐ Pass ☐ Fail |
| **Encerramento Abrupto** | Desligar app sem sair | Professor detecta desconexão           | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

### RNF4: Segurança (Validações)

| Ameaça                   | Teste                | Mitigação                  | Status        |
| ------------------------ | -------------------- | -------------------------- | ------------- |
| **Força Bruta (3 PINs)** | 3 tentativas erradas | Bloqueado                  | ☐ Pass ☐ Fail |
| **Aluno Remoto**         | IP fora sub-rede     | Rejeitado (SubnetCheck)    | ☐ Pass ☐ Fail |
| **Matrícula Duplicada**  | 2x mesma matrícula   | 2ª desconectada            | ☐ Pass ☐ Fail |
| **Data Inconsistência**  | Múltiplas rodadas    | Presença rastreável em CSV | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

### RNF5: Compatibilidade (Android 11+)

| Recurso                   | Teste                         | Esperado             | Status        |
| ------------------------- | ----------------------------- | -------------------- | ------------- |
| **Localização (API 28+)** | Permission.location.request() | Dialog exibido       | ☐ Pass ☐ Fail |
| **Storage (Android 11+)** | CSV export                    | Arquivo em Downloads | ☐ Pass ☐ Fail |
| **WebSocket**             | Comunicação ativa             | Sem TimeoutException | ☐ Pass ☐ Fail |

**Resultado:** ☐ Passou ☐ Falhou

---

## 4. Testes de Integração

### I1: Fluxo Completo Professor + Aluno (5 min)

```
1. Professor inicia app → ProfessorHostScreen
2. Aguarda 5s (NSD publishe)
3. Aluno inicia app → AlunoJoinScreen
4. Aluno descobre servidor
5. Aluno conecta com dados fictícios
6. Professor vê aluno conectado
7. Professor configura 2 rodadas de 30s
8. Professor inicia Rodada 1
9. Aluno recebe PIN
10. Aluno envia PIN correto
11. Professor vê "Presente"
12. Professor inicia Rodada 2
13. Aluno envia PIN incorreto 3x (bloqueado)
14. Professor vê "Falhou PIN"
15. Professor taps "Exportar CSV"
16. CSV criado em Downloads com 2 alunos × 2 rodadas
17. Aluno sai (back)
18. Professor encerra

ESPERADO: ✅ Fluxo completo sem erros
```

**Resultado:** ☐ Passou ☐ Falhou

---

### I2: Múltiplos Alunos Simultâneos (10 min)

```
1. Professor inicia + configura 2 rodadas
2. Aluno A conecta
3. Aluno B conecta (dispositivo 2 ou emulador)
4. Professor inicia Rodada 1
5. Aluno A envia PIN correto
6. Aluno B envia PIN errado 3x
7. Rodada encerra
8. Professor vê: A=Presente, B=Falhou PIN
9. Professor inicia Rodada 2
10. Aluno A não envia (ausente)
11. Aluno B envia PIN correto (reset)
12. Rodada encerra
13. CSV export: 2 alunos × 2 rodadas = 4 registros

ESPERADO: Ambos alunos rastreados independentemente
```

**Resultado:** ☐ Passou ☐ Falhou

---

## 5. Testes de Regressão (Após Correções)

### RG1: Verificar Alterações Anteriores

- [ ] Permissões Android (ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION) adicionadas
- [ ] AlunoJoinScreen pede `Permission.location.request()` antes de NSD
- [ ] AlunoWaitScreen fecha WebSocket em `dispose()` (try/catch)
- [ ] Rate limiting implementado (3 tentativas por matricula_rodada)
- [ ] Mensagem de matrícula duplicada melhorada

**Resultado:** ☐ Todas OK ☐ Falhas encontradas

---

## 6. Documentação de Resultados

### Formato de Relatório

```markdown
## Teste T1: Inicialização e Seleção de Papel

**Data:** 2025-11-20
**Dispositivo:** Samsung Galaxy A13 (Android 13)
**Resultado:** ✅ PASSOU

| Passo | Ação             | Esperado                        | Resultado | Observações  |
| ----- | ---------------- | ------------------------------- | --------- | ------------ |
| 1     | Abrir app        | Tela seleção exibida            | ✅        | Rápido, < 2s |
| 2     | Taps "Professor" | Navega para ProfessorHostScreen | ✅        | -            |
| 3     | Volta (back)     | Retorna para seleção            | ✅        | -            |
| 4     | Taps "Aluno"     | Navega para AlunoJoinScreen     | ✅        | -            |

**Observações Gerais:**

- App respondeu bem
- Sem crashes
- UI fluida

**Testes Seguintes:** T2 (Discovery)
```

---

## 7. Checklist Final

### Antes da Entrega

- [ ] Todos os testes funcionais (T1-T12) passaram
- [ ] Testes não-funcionais (RNF1-5) validados
- [ ] Testes de integração (I1-2) executados
- [ ] Testes de regressão (RG1) verificados
- [ ] CSV export validado em Excel/Sheets
- [ ] Permissões funcionam em dispositivo real
- [ ] Sem erros no console (logcat)
- [ ] Git repository atualizado com todas as melhorias
- [ ] Documentação completa (requisitos_v2.md, antifraude.md, arquitetura.md, csv_layout.md, testes.md)

### Para Apresentação

- [ ] Video (~20 min) demonstrando fluxo completo
- [ ] Slides PPTX explicando arquitetura e antifraude
- [ ] Demo ao vivo (2 dispositivos, 2 rodadas, CSV export)
- [ ] Código aberto no GitHub (privado ou público)
- [ ] README.md com instruções de execução

---

## 8. Referências

- **requisitos_v2.md:** Especificação de requisitos e acceptance criteria
- **antifraude.md:** Documentação de ameaças e mitigações
- **arquitetura.md:** Diagramas e decisões arquiteturais
- **csv_layout.md:** Especificação do formato de exportação

---

**Plano de testes final para N3. Executar em dispositivo real antes da apresentação.**
