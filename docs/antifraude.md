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

| Ameaça                     | Medida                       | Status | Força |
| -------------------------- | ---------------------------- | ------ | ----- |
| MC01 - Aluno Ausente       | SubnetCheck (IP validation)  | ✅     | Média |
| MC02 - Força Bruta         | Rate Limiting (3 tentativas) | ✅     | Alta  |
| MC03 - Matrícula Duplicada | Socket Validation            | ✅     | Alta  |
| MC04 - Aluno Fantasma      | Múltiplas Rodadas            | ✅     | Média |

---

## 3. Recomendações para Futuras Versões

### N3 Avançada (se tempo permitir)

- [ ] Implementar QR Code dinâmico por rodada
- [ ] Adicionar geofencing simples (GPS com grande margem)
- [ ] Device ID binding

### N10+ (Banco Externo)

- [ ] Integração com banco de dados externo (Firebase/Supabase)
- [ ] Audit trail com timestamps precisos
- [ ] Análise comportamental (padrões de ausência)
- [ ] Integração com sistema acadêmico

---

## 4. Termos e Defini ções

- **Matrícula:** ID único do aluno (ex: 202301)
- **SubnetCheck:** Validação de que cliente e servidor estão na mesma rede local (3 primeiros octetos do IP)
- **Rate Limiting:** Limite de tentativas (3 PINs por rodada)
- **Socket:** Conexão WebSocket entre cliente e servidor
- **Device ID:** UUID único gerado no dispositivo
- **Geofencing:** Validação de localização via GPS

---

## 5. Requisitos Atendidos (RNF07)

✅ **RNF07 - Documentação antifraude (3+ ameaças/mitigações):**

- MC01: Aluno Ausente → SubnetCheck + Geofencing (proposta)
- MC02: Força Bruta → Rate Limiting + Timeout (proposta)
- MC03: Matrícula Duplicada → Socket Validation + Device ID (proposta)
- MC04: Aluno Fantasma → Múltiplas Rodadas + Heurística (proposta)

---

**Documento final para entrega N3. Atualizar conforme testes em dispositivo real.**
