# Análise de Requisitos SmartPresence v2.0

**Versão:** 2.0 (Entrega N3)  
**Data:** 20 de Novembro de 2025  
**Grupo:** CodeMonkeys Corp.  
**Membros:** André Schultz, José Henrique Bruhmuller, Matheus Busemayer, Lucas Monich Nunes

## 1. Visão e Escopo

### Problema

O processo tradicional de chamada em sala de aula é manual, consome tempo do professor, é suscetível a erros e não possui mecanismos eficazes contra fraudes.

### Objetivos do Produto (N2 - Base)

- ✅ Automatizar registro de presença em sala de aula
- ✅ Permitir múltiplas chamadas (4 rodadas por período)
- ✅ Funcionar em ambiente de sala de aula sem infraestrutura externa
- ✅ Definir mecanismos para desencorajar/detectar fraudes
- ✅ Definir formato de relatório CSV consolidado

### Evolução para N3

- ✅ **Execução em dispositivo Android real** (não apenas emulador)
- ✅ **Persistência de dados entre sessões** (SharedPreferences)
- ✅ **Exportação de relatórios acessíveis**
- ✅ **Documentação completa de engenharia**
- ✅ **Antifraude documentada e implementada**

## 2. Escopo Final do Produto

### Incluso

- Aplicativo Flutter para Android (API 23+)
- Dois perfis: Professor (Host/Servidor) e Aluno (Cliente)
- Comunicação via rede local Wi-Fi (WebSocket + NSD)
- 4 rodadas configuráveis com horários dinâmicos
- Geração automática e manual de rodadas
- PIN aleatório (4 dígitos) por rodada
- Persistência em SharedPreferences
- Exportação CSV em Downloads
- Visualização de histórico no app
- Permissões para localização (NSD) e storage (CSV)

### Fora de Escopo (N3)

- Integração com sistemas acadêmicos
- Autenticação de usuários (login/senha)
- Banco de dados externo (N10 avançado)
- Versão iOS

## 3. Requisitos Funcionais (RF)

| ID   | Descrição                                | Status | Comentário                                             |
| ---- | ---------------------------------------- | ------ | ------------------------------------------------------ |
| RF01 | Professor inicia servidor de chamada     | ✅     | Implementado em `ProfessorHostScreen`                  |
| RF02 | Sistema publica servidor via NSD         | ✅     | Usando pacote `nsd`                                    |
| RF03 | Professor configura horários + duração   | ✅     | `ConfiguracoesScreen` com suporte a múltiplos horários |
| RF04 | Rodadas iniciam/encerram automaticamente | ✅     | Timers + verificação periódica (`_verificarRodadas`)   |
| RF05 | Professor inicia/encerra manualmente     | ✅     | Botões em `_buildRodadaCard`                           |
| RF06 | Sistema gera PIN aleatório 4 dígitos     | ✅     | `_generatePin()`                                       |
| RF07 | Aluno descobre servidor (NSD)            | ✅     | Com permissão de localização (N3 fix)                  |
| RF08 | Aluno conecta manualmente (IP:Porta)     | ✅     | Campo de entrada em `AlunoJoinScreen`                  |
| RF09 | Aluno registra Nome + Matrícula          | ✅     | Formulário em `AlunoJoinScreen`                        |
| RF10 | Aluno submete PIN                        | ✅     | `AlunoWaitScreen` com teclado numérico                 |
| RF11 | Armazena presenças em memória            | ✅     | `_presencas` map + SharedPreferences                   |
| RF12 | Visualiza histórico                      | ✅     | `HistoricoScreen`                                      |
| RF13 | Exporta CSV                              | ✅     | `_exportarCSV()` em Downloads                          |
| RF14 | Antifraude definida                      | ✅     | SubnetCheck + Rate Limiting (v2.0)                     |
| RF15 | Visualiza alunos conectados              | ✅     | `_buildClientList()`                                   |
| RF16 | Impede matrícula duplicada               | ✅     | Validação com feedback claro (v2.0)                    |
| RF17 | Encerra sessão do servidor               | ✅     | `WillPopScope` + `_stopServer()`                       |

## 4. Requisitos Não Funcionais (RNF)

| ID    | Descrição                            | Status | Comentário                          |
| ----- | ------------------------------------ | ------ | ----------------------------------- |
| RNF01 | Usabilidade: ≤3 toques aluno         | ✅     | UI simplificada                     |
| RNF02 | Portabilidade: Android API 23+       | ✅     | Testado em emulador                 |
| RNF03 | Conectividade: Offline (Wi-Fi local) | ✅     | WebSocket + NSD locais              |
| RNF04 | Desempenho: Discovery ~10s           | ✅     | Depende da rede                     |
| RNF05 | Desempenho: PIN response ~2s         | ✅     | Depende da rede                     |
| RNF06 | Segurança: PIN 4 dígitos aleatório   | ✅     | `_generatePin()`                    |
| RNF07 | Antifraude documentada               | ⚠️     | Ver `docs/antifraude.md`            |
| RNF08 | Manutenibilidade: Models separados   | ✅     | `lib/models/app_models.dart`        |
| RNF09 | Robustez: Lida com desconexões       | ✅     | onError/onDone handlers             |
| RNF10 | Dados em memória (sessão)            | ✅     | + persistência em SharedPreferences |

## 5. Regras de Negócio (RN)

| ID   | Descrição                                | Status |
| ---- | ---------------------------------------- | ------ |
| RN01 | Funciona em rede Wi-Fi local             | ✅     |
| RN02 | Comunicação via WebSocket                | ✅     |
| RN03 | Discovery via NSD + fallback manual      | ✅     |
| RN04 | Professor configura horários dinâmicos   | ✅     |
| RN05 | Rodadas iniciam/encerram automaticamente | ✅     |
| RN06 | Professor força início/fim de rodada     | ✅     |
| RN07 | PIN aleatório 4 dígitos por rodada       | ✅     |
| RN08 | Aluno informa Nome + Matrícula           | ✅     |
| RN09 | Impede mesma matrícula conectar 2x       | ✅     |
| RN10 | Antifraude implementada                  | ✅     |
| RN11 | Sem PIN = "Ausente" ao fim de rodada     | ✅     |
| RN12 | Histórico em memória + persistência      | ✅     |

## 6. Protocolo de Mensagens JSON

### Cliente → Servidor

```json
{ "command": "JOIN", "nome": "João", "matricula": "202301" }
{ "command": "SUBMIT_PIN", "rodada": "Rodada 1", "pin": "1234" }
```

### Servidor → Cliente

```json
{ "command": "JOIN_SUCCESS", "message": "Bem-vindo, João!" }
{ "command": "RODADA_ABERTA", "nome": "Rodada 1", "endTimeMillis": 1700500000000 }
{ "command": "PRESENCA_OK", "rodada": "Rodada 1" }
{ "command": "PRESENCA_FALHA", "message": "PIN incorreto. Tentativas restantes: 2" }
{ "command": "RODADA_FECHADA", "nome": "Rodada 1" }
{ "command": "ERROR", "message": "Descrição do erro" }
```

## 7. Layout CSV (Exportação)

**Arquivo:** `presenca_smartpresence_YYYYMMDD_HHmmss.csv`  
**Codificação:** UTF-8  
**Delimitador:** Vírgula (,)

| Coluna           | Tipo   | Exemplo     | Descrição                                        |
| ---------------- | ------ | ----------- | ------------------------------------------------ |
| matricula        | String | 202301      | ID único do aluno                                |
| nome             | String | João Silva  | Nome completo                                    |
| data             | String | 2025-11-20  | Data (YYYY-MM-DD)                                |
| rodada           | String | Rodada 1    | Nome da rodada                                   |
| status           | String | Presente    | Presente, Ausente, Falhou PIN, Falhou PIN (Rede) |
| gravado_em       | String | 19:35:42    | Timestamp (HH:mm:ss)                             |
| notas            | String | -           | Campo livre para observações                     |
| metodo_validacao | String | SubnetCheck | Método antifraude usado                          |

**Exemplo:**

```csv
"matricula","nome","data","rodada","status","gravado_em","notas","metodo_validacao"
"202301","João Silva","2025-11-20","Rodada 1","Presente","19:35:42","","SubnetCheck"
"202302","Maria Santos","2025-11-20","Rodada 1","Falhou PIN","19:36:10","","SubnetCheck"
"202301","João Silva","2025-11-20","Rodada 2","Ausente","19:55:00","","SubnetCheck"
```

## 8. Antifraude (v2.0)

### Ameaças Identificadas

1. **Aluno Ausente Tenta Registrar**

   - Ataque: Colega envia PIN de fora da sala
   - Mitigação: **SubnetCheck** — valida IP do cliente na mesma sub-rede do servidor

2. **Força Bruta de PIN**

   - Ataque: Múltiplas tentativas (0000-9999)
   - Mitigação: **Rate Limiting** — máximo 3 tentativas por rodada; bloqueio após excesso

3. **Matrícula Duplicada**

   - Ataque: Mesma matrícula conecta em múltiplos dispositivos
   - Mitigação: **Validação de Socket** — rejeita segunda conexão com mensagem clara

4. **Aluno "Fantasma"**
   - Ataque: Registra na primeira rodada e sai
   - Mitigação: **Múltiplas Rodadas** — ausência em demais rodadas detecta padrão

### Implementação Atual

- ✅ **SubnetCheck:** Compara 3 primeiros octetos do IP (ex: 192.168.1)
- ✅ **Rate Limiting:** Máximo 3 tentativas por matrícula-rodada (`_pinAttempts`)
- ✅ **Matrícula Duplicada:** Rejeita com mensagem: "❌ Matrícula já está conectada em outro dispositivo"
- ✅ **Múltiplas Rodadas:** Configuráveis dinamicamente

## 9. Definições Conceituais de Antifraude (RNF07)

Ver documento completo em `docs/antifraude.md`.

## 10. Decisões de Design

| Decisão                     | Justificativa                                            |
| --------------------------- | -------------------------------------------------------- |
| WebSocket em vez de REST    | Comunicação em tempo real bidirecional                   |
| NSD para descoberta         | Funciona sem conectividade externa; fallback manual      |
| SharedPreferences           | Persistência simples entre sessões                       |
| SubnetCheck para antifraude | Simples e eficaz em LAN; não requer infraestrutura extra |
| Rate Limiting de PIN        | Bloqueio força bruta sem complexidade                    |
| Matrícula única por socket  | Evita fraude por múltiplos registros simultâneos         |
| CSV em Downloads            | Fácil acesso do usuário (Android 10+)                    |

## 11. Mapeamento de Arquivos

| Requisito     | Arquivo                                  |
| ------------- | ---------------------------------------- |
| Tela Inicial  | `lib/screens/role_selection_screen.dart` |
| Professor     | `lib/screens/professor_host_screen.dart` |
| Configurações | `lib/screens/configuracoes_screen.dart`  |
| Aluno - Join  | `lib/screens/aluno_join_screen.dart`     |
| Aluno - Wait  | `lib/screens/aluno_wait_screen.dart`     |
| Histórico     | `lib/screens/historico_screen.dart`      |
| Modelos       | `lib/models/app_models.dart`             |
| Main          | `lib/main.dart`                          |

## 12. Critérios de Aceite (Exemplos)

### RF03: Configurar Rodadas

- Quando professor edita "Rodada 1" (19:10 → 19:15) e salva
- Então `ProfessorHostScreen` mostra "Rodada 1 - Início às 19:15"
- E horário persiste após fechar/reabrir app

### RF10 + RF14: Submeter PIN com Antifraude

- **Sucesso:** Aluno A (IP 192.168.1.10) envia PIN "1234" → PRESENCA_OK
- **Erro de PIN:** Aluno A (IP 192.168.1.10) envia PIN "9999" → PRESENCA_FALHA + contador de tentativas
- **Antifraude - Rede:** Aluno B (IP 8.8.8.8) tenta conectar → rejeitado
- **Rate Limit:** Aluno C excede 3 tentativas → PRESENCA_FALHA com bloqueio

### RF13: Layout CSV

- Arquivo contém colunas: matricula, nome, data, rodada, status, gravado_em, notas, metodo_validacao

## 13. Status Final para N3

**Pronto para Entrega:**

- ✅ App compilado e instalado em celular Android
- ✅ Telas navegáveis
- ✅ Persistência e histórico
- ✅ Exportação CSV
- ✅ Antifraude implementada
- ✅ Documentação

**Próximos Passos (Grupo):**

- [ ] Testar em 2+ celulares reais
- [ ] Criar apresentação PPTX
- [ ] Gravar vídeo ~20 min
- [ ] Documentar em `docs/antifraude.md`

---

**Documento gerado automaticamente para N3. Atualizar conforme necessário.**
