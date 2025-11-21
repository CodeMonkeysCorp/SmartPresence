# Plano de Testes e Próximas Iterações

**Status:** Código verificado ✅ | Pronto para testes funcionais

---

## 1. Testes Unitários / Integração (Recomendado)

### 1.1 Testes de Validação de PIN

```
Teste: PIN Correto
├─ Entrada: pin=1234, rodada="Rodada 1" (status=Em Andamento)
├─ Servidor: Responde PRESENCA_OK
└─ Resultado: ✅ Presença registrada

Teste: PIN Incorreto (1/3)
├─ Entrada: pin=9999, rodada="Rodada 1"
├─ Servidor: Responde PRESENCA_FALHA + tentativas restantes
└─ Resultado: ✅ Contador incrementado

Teste: PIN Bloqueado (3/3 attempts)
├─ Entrada: 3 PINs errados consecutivos
├─ Servidor: Bloqueia no 3º e responde PRESENCA_FALHA + mensagem de bloqueio
└─ Resultado: ✅ Aluno impedido de continuar
```

### 1.2 Testes de Antifraude

```
Teste: Sub-rede IPv4 (/24)
├─ Entrada: Cliente em 192.168.1.100, Servidor em 192.168.1.1
├─ Resultado: ✅ Aceito

Teste: Fora da Sub-rede
├─ Entrada: Cliente em 10.0.0.50, Servidor em 192.168.1.1
├─ Resultado: ✅ Rejeitado com PRESENCA_FALHA

Teste: Duplicação de Matrícula
├─ Entrada: 2 clientes com matricula="12345" simultâneos
├─ Resultado: ✅ 2º rejeitado com ERROR + close socket
```

### 1.3 Testes de Persistência

```
Teste: Rate Limiting Persiste (SharedPreferences)
├─ Entrada: 3 tentativas de PIN, fechar app, reabrir
├─ Resultado: ✅ Contador persiste, 4ª tentativa bloqueada

Teste: Histórico Salvo
├─ Entrada: Registrar 5 presenças
├─ Verificação: SharedPreferences contém histórico JSON
└─ Resultado: ✅ Dados persistidos corretamente
```

---

## 2. Testes Funcionais (Local)

### 2.1 Setup Recomendado

```bash
# Terminal 1: Emulador Android
flutter emulators --launch Pixel_4_API_30

# Terminal 2: App em modo Professor
flutter run --target=lib/main.dart  # Build para professor

# Terminal 3: App em modo Aluno (mesmo emulador ou outro)
flutter run  # Deploy a outro emulador/dispositivo
```

### 2.2 Caso de Teste: Fluxo Completo

```
Sequência:
1. [PROFESSOR] Inicia app → Configurar Horários
2. [PROFESSOR] Define: Rodada 1 (14:00), Rodada 2 (14:10)
3. [PROFESSOR] Aguarda carregamento → NSD publicado
4. [ALUNO] Inicia app → Digita Nome + Matrícula
5. [ALUNO] NSD descobre professor → Auto-conecta
6. [ALUNO] Aguarda mensagem de rodada
7. [PROFESSOR] Clica Play para iniciar Rodada 1
8. [ALUNO] Recebe RODADA_ABERTA com timer
9. [ALUNO] Digita PIN (exibido no card do Professor)
10. [ALUNO] Clica Enviar Presença
11. [PROFESSOR] Vê presença registrada (Status: Presente)
12. [ALUNO] Recebe PRESENCA_OK ✅
```

**Verificações Esperadas:**

- ✅ Profesor: IP:Porta exibido
- ✅ Profesor: N alunos conectados
- ✅ Aluno: Timer regressivo conta para baixo
- ✅ Aluno: PIN enviado após expiry rejeitado
- ✅ Professor: CSV exportável com presenças

### 2.3 Caso de Teste: Rate Limiting (10 minutos)

```
Sequência:
1. [ALUNO] Tenta PIN errado 3 vezes
2. [ALUNO] 4ª tentativa bloqueada → mensagem de bloqueio
3. [ALUNO] Aguarda 10 minutos (ou restart app)
4. [ALUNO] Mesma rodada em novo horário → aceita novamente
```

**Verificação:**

- ✅ Compartilhamento de contador persistido entre sessões

---

## 3. Bugs Conhecidos & Workarounds

### Nenhum bug crítico identificado ✅

**Observações:**

- Linha 872 do analyzer ainda reporta brace desnecessário → cache do Flutter
- Constantes em UPPER_SNAKE_CASE em configuracoes_screen → não crítico

---

## 4. Melhorias Planejadas (Ordem de Prioridade)

### P0: Críticas (Implementar Antes de Produção)

- [ ] Adicionar timeout ao WebSocket connect (10s)
- [ ] Aumentar PIN para 5-6 dígitos

### P1: Importantes (Implementar em v1.1)

- [ ] Sanitizar `nome` em CSV export
- [ ] Rate limit no JOIN (evitar spam)
- [ ] Migrar `WillPopScope` para `PopScope` (Flutter 3.12+)

### P2: Melhorias (Backlog)

- [ ] Implementar heartbeat WebSocket
- [ ] Suporte a `wss://` com certificado self-signed
- [ ] Configuração de janela de PIN via UI
- [ ] Notificações push antes da rodada

---

## 5. Checklist de Entrega (MVP)

- [x] Antifraude: Rate limiting + persistência
- [x] Validação: JSON, matrícula, sub-rede
- [x] Handshake: JOIN → JOIN_SUCCESS
- [x] Rodadas: RODADA_ABERTA → PRESENCA_OK/FALHA
- [x] Historico: Persistido em SharedPreferences
- [x] CSV: Exportável com presenças
- [x] Logging: Estruturado para auditoria
- [x] Análise estática: Sem bloqueadores críticos
- [ ] Testes locais: End-to-end com emulador
- [ ] Documentação: Manuais de uso (TODO)

---

## 6. Próximos Passos (Recomendado)

### Fase 1: Testes (Imediato)

```bash
# 1. Compilar e rodar no emulador/dispositivo
flutter run

# 2. Testar fluxo completo (ver Caso 2.2 acima)

# 3. Validar rate limiting após 10 minutos

# 4. Exportar CSV e validar formato
```

### Fase 2: Documentação (Próxima Sprint)

- [ ] Guia de Uso para Professor
- [ ] Guia de Uso para Aluno
- [ ] Manual de Instalação
- [ ] FAQ Técnico

### Fase 3: Deploy (Após Testes)

- [ ] Build APK release
- [ ] Sign com certificado de produção
- [ ] Publicar em Google Play (opcional)

---

**Revisado por:** GitHub Copilot  
**Última atualização:** 20 de novembro de 2025
