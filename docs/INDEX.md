# Índice de Documentação - SmartPresence N3

**Versão:** 2.0  
**Data:** 20 de Novembro de 2025  
**Status:** ✅ Documentação Completa (~3.100 linhas)

---

## 📚 Mapa de Documentação

### 1. **COMEÇAR AQUI** 🎯

#### 1.1 [RESUMO_EXECUTIVO.md](RESUMO_EXECUTIVO.md)

- **Tamanho:** ~450 linhas
- **Tempo de leitura:** 10 minutos
- **Conteúdo:**
  - Visão do projeto (problema/solução)
  - Métricas: 17 RFs, 10 RNFs, 12 RNs (100% implementados)
  - Arquitetura em 30 segundos
  - 4 camadas de antifraude resumidas
  - Código: pontos-chave (com snippets)
  - Checklist de entrega N3
  - Próximos passos imediatos
  - Critério de sucesso (mínimo/esperado/excelente)
- **Público:** Gerentes, professores, revisores rápidos
- **Próximo:** Depende do interesse — vá para Testes, Requisitos ou Antifraude

#### 1.2 [CHECKLIST_ENTREGA.md](CHECKLIST_ENTREGA.md)

- **Tamanho:** ~400 linhas
- **Tempo de leitura:** 5 minutos
- **Conteúdo:**
  - Checklist executivo (código ✅, documentação ✅, testes ⏳, apresentação ⏳)
  - Resumo quantitativo (métricas)
  - Critério de sucesso (mínimo/esperado/bônus)
  - Plano de ação imediato
  - Risco mais alto (WiFi 5GHz)
- **Público:** Desenvolvedores finalizando projeto
- **Próximo:** GUIA_RAPIDO_TESTE.md (para começar testes)

#### 1.3 [GUIA_RAPIDO_TESTE.md](GUIA_RAPIDO_TESTE.md) ⚡ **RECOMENDADO PARA HOJE**

- **Tamanho:** ~200 linhas
- **Tempo de execução:** 30-45 minutos
- **Conteúdo:**
  - 5 minutos: Setup rápido (instalação)
  - 10 minutos: Teste básico (PIN correto)
  - 5 minutos: Rate limiting
  - 10 minutos: CSV export
  - Cenário completo (30 min) com checklist
  - Troubleshooting rápido
  - Checklist de validação final
- **Público:** Desenvolvedores testando agora
- **Ação:** Execute os passos em paralelo com 2 dispositivos

---

### 2. **ESPECIFICAÇÃO** 📋

#### 2.1 [requisitos_v2.md](requisitos_v2.md)

- **Tamanho:** ~350 linhas
- **Tempo de leitura:** 15 minutos
- **Conteúdo:**
  - Seção 1: Visão e Escopo
  - Seção 2: Requisitos Funcionais (17 RFs)
    - RF01-16 com descrição, aceite e arquivo
    - Status (✅ implementado)
  - Seção 3: Requisitos Não-Funcionais (10 RNFs)
    - RNF01-10 com criticidade
  - Seção 4: Regras de Negócio (12 RNs)
    - PIN de 4 dígitos, máximo 3 tentativas, validação IP, etc.
  - Seção 5: Protocolo JSON Detalhado
    - Exemplos de mensagens (JOIN, RODADA_ABERTA, PRESENCA_OK, etc.)
  - Seção 6: Formato CSV
    - 8 colunas detalhadas
  - Seção 7: Critério de Aceitação (exemplos para RF03, RF10, RF14, RF13)
- **Público:** Testers, QA, professores avaliadores
- **Próximo:** csv_layout.md (se precisa detalhe de CSV) ou plano_testes.md (para aceitar testes)

#### 2.2 [csv_layout.md](csv_layout.md)

- **Tamanho:** ~250 linhas
- **Tempo de leitura:** 8 minutos
- **Conteúdo:**
  - Propriedades gerais (nome arquivo, codificação, delimitador, escape)
  - 8 Colunas detalhadas (matricula, nome, data, rodada, status, gravado_em, notas, metodo_validacao)
  - Estrutura completa com exemplo (16 linhas)
  - Instruções de exportação (passo-a-passo)
  - Tratamento de casos especiais (caracteres, valores vazios)
  - Compatibilidade (Excel, Sheets, LibreOffice, Python, PowerBI)
  - Geração no código (snippet Dart)
  - Checklist de validação (9 itens)
- **Público:** Desenvolvedor (gerar CSV), Professor (ler CSV)
- **Próximo:** plano_testes.md (seção T11 sobre CSV export)

---

### 3. **IMPLEMENTAÇÃO** 🔧

#### 3.1 [arquitetura.md](arquitetura.md)

- **Tamanho:** ~600 linhas
- **Tempo de leitura:** 25 minutos
- **Conteúdo:**
  - Seção 1: Visão Geral
  - Seção 2: Componentes Principais (6 screens + camadas)
    - RoleSelectionScreen (seleção)
    - ProfessorHostScreen (servidor, 1511 linhas)
    - ConfiguracoesScreen (settings)
    - HistoricoScreen (visualização)
    - AlunoJoinScreen (descoberta)
    - AlunoWaitScreen (PIN submission)
    - Camada de Comunicação (WebSocket + NSD + JSON)
    - Camada de Persistência (SharedPreferences + CSV)
    - Camada de Modelos (Rodada, AlunoConectado)
  - Seção 3: Fluxo de Dados (4 fluxos principais)
    - Fluxo de Conexão (JOIN)
    - Fluxo de Rodada (PRESENÇA)
    - Fluxo de Encerramento
    - Fluxo de Exportação CSV
  - Seção 4: Antifraude (4 camadas com código)
    - SubnetCheck (linhas)
    - Rate Limiting (linhas)
    - Socket Uniqueness (linhas)
    - Multiple Rounds Detection (CSV)
  - Seção 5: Diagrama de Classe
  - Seção 6: Tecnologias e Dependências (tabela)
  - Seção 7: 7 Decisões Arquiteturais Justificadas
  - Seção 8: Segurança (ameaças + mitigações)
  - Seção 9: Testes Manuais (5 cenários)
  - Seção 10: Roadmap Futuro
- **Público:** Desenvolvedores, arquitetos, avaliadores técnicos
- **Próximo:** antifraude.md (detalhe de segurança) ou plano_testes.md (plano de validação)

#### 3.2 [antifraude.md](antifraude.md) 🔒 **CRÍTICO PARA N3**

- **Tamanho:** ~400 linhas
- **Tempo de leitura:** 20 minutos
- **Conteúdo:**
  - Visão Geral (4 misuse cases, 4 implementadas)
  - Seção 1: MC01 - Aluno Ausente
    - Cenário de ataque
    - Impacto/Probabilidade
    - Mitigação 1: SubnetCheck ✅ (implementado)
    - Mitigação 2: Geofencing 🔶 (proposto)
    - Mitigação 3: QR Code 🟡 (proposto)
  - Seção 2: MC02 - Força Bruta
    - Rate Limiting ✅
    - Exponential Backoff 🔶
    - CAPTCHA 🔶
  - Seção 3: MC03 - Matrícula Duplicada
    - Socket Validation ✅
    - Device ID Binding 🔶
  - Seção 4: MC04 - Aluno Fantasma
    - Múltiplas Rodadas ✅
    - Heurística de Saída 🔶
  - Seção 5: Resumo (tabela com força de cada medida)
  - Recomendações Futuras (N3 avançado, N10)
- **Público:** Avaliadores de segurança, professores
- **Próximo:** arquitetura.md (contexto) ou plano_testes.md (validação)

---

### 4. **TESTE** 🧪

#### 4.1 [plano_testes.md](plano_testes.md)

- **Tamanho:** ~400 linhas
- **Tempo de leitura:** 20 minutos (planejar), 90 minutos (executar todos)
- **Conteúdo:**
  - Seção 1: Setup Pré-teste (requisitos, checklist)
  - Seção 2: 12 Testes Funcionais (T1-T12)
    - T1: Inicialização
    - T2-T3: Discovery + Permissões
    - T4: Rodada e PIN
    - T5: Rate Limiting (3 tentativas)
    - T6: Validação de sub-rede
    - T7: Matrícula duplicada
    - T8: Encerramento automático
    - T9: Múltiplas rodadas
    - T10: Histórico
    - T11: CSV export
    - T12: Desconexão segura
    - Cada teste tem: Passo | Ação | Esperado | Status
  - Seção 3: 5 Testes Não-Funcionais (RNF1-5)
    - RNF1: Usabilidade
    - RNF2: Performance
    - RNF3: Reliability
    - RNF4: Segurança
    - RNF5: Compatibilidade
  - Seção 4: 2 Testes de Integração (I1-2)
    - I1: Fluxo completo 5 min
    - I2: Múltiplos alunos 10 min
  - Seção 5: Testes de Regressão
  - Seção 6: Documentação de Resultados (template)
  - Seção 7: Checklist Final (antes de entrega)
  - Seção 8: Referências (links)
- **Público:** QA, testers, desenvolvedores validando
- **Próximo:** GUIA_RAPIDO_TESTE.md (execute versão rápida hoje)

---

### 5. **SETUP E USO** 📱

#### 5.1 [README.md](README.md)

- **Tamanho:** ~300 linhas
- **Tempo de leitura:** 12 minutos
- **Conteúdo:**
  - Seção 1: Visão Geral
    - Características principais (5 pontos)
  - Seção 2: Como Usar
    - Instalação (git clone, flutter pub get, flutter run)
    - Primeira execução (4 passos: Professor, Aluno, Rodada, CSV)
  - Seção 3: Estrutura do Projeto (árvore de arquivos)
  - Seção 4: Dependências Principais (tabela 10 pacotes)
  - Seção 5: Requisitos do Dispositivo
    - Mínimo (API 28)
    - Recomendado (API 30+)
    - Permissões requeridas (8 permissões XML)
  - Seção 6: Segurança e Antifraude (resumo das 4 camadas)
  - Seção 7: Protocolo WebSocket (JSON)
  - Seção 8: Formato CSV de Exportação
  - Seção 9: Testes (rápido + completo + checklist)
  - Seção 10: Troubleshooting (5 problemas comuns)
  - Seção 11: Documentação Completa (links)
  - Seção 12: Melhorias N2→N3 (checklist)
  - Seção 13: Próximos Passos
- **Público:** Novos usuários, instalação, troubleshooting
- **Próximo:** GUIA_RAPIDO_TESTE.md ou plano_testes.md

---

### 6. **ESTE ARQUIVO** 📖

#### 6.1 [INDEX.md](INDEX.md) ← **Você está aqui**

- **Tamanho:** ~250 linhas
- **Conteúdo:**
  - Mapa completo da documentação
  - Descrição de cada arquivo
  - Tamanho, tempo de leitura, público-alvo, próximo arquivo
  - Questões rápidas (abaixo)
  - Checklist de completude

---

## 🎯 Questões Rápidas — Qual Documento Ler?

### "Tenho 5 minutos. O que devo ler?"

→ [RESUMO_EXECUTIVO.md](RESUMO_EXECUTIVO.md) (seções 1-4)

### "Quero começar testes agora."

→ [GUIA_RAPIDO_TESTE.md](GUIA_RAPIDO_TESTE.md) (30-45 min, 2 dispositivos)

### "Quero entender os requisitos."

→ [requisitos_v2.md](requisitos_v2.md) (17 RFs, 10 RNFs, 12 RNs)

### "Como faço para instalar e usar?"

→ [README.md](README.md) (seções 2-5)

### "Quais são as falhas de segurança possíveis?"

→ [antifraude.md](antifraude.md) (4 misuse cases + mitigações)

### "Qual é a arquitetura detalhada?"

→ [arquitetura.md](arquitetura.md) (componentes, fluxos, decisões)

### "Como testo tudo isso?"

→ [plano_testes.md](plano_testes.md) (15 casos de teste com checklist)

### "Qual é o formato do CSV exportado?"

→ [csv_layout.md](csv_layout.md) (8 colunas, exemplos, compatibilidade)

### "Estou pronto para entregar. O que falta?"

→ [CHECKLIST_ENTREGA.md](CHECKLIST_ENTREGA.md) (status de código, docs, testes, apresentação)

---

## 📊 Estatísticas de Documentação

| Arquivo              | Linhas     | Leitura        | Tipo          | Status |
| -------------------- | ---------- | -------------- | ------------- | ------ |
| RESUMO_EXECUTIVO.md  | ~450       | 10 min         | Visão         | ✅     |
| CHECKLIST_ENTREGA.md | ~400       | 5 min          | Progresso     | ✅     |
| GUIA_RAPIDO_TESTE.md | ~200       | 30-45 min exec | Teste         | ✅     |
| requisitos_v2.md     | ~350       | 15 min         | Especificação | ✅     |
| csv_layout.md        | ~250       | 8 min          | Especificação | ✅     |
| arquitetura.md       | ~600       | 25 min         | Implementação | ✅     |
| antifraude.md        | ~400       | 20 min         | Segurança     | ✅     |
| plano_testes.md      | ~400       | 20 min         | Teste         | ✅     |
| README.md            | ~300       | 12 min         | Setup         | ✅     |
| INDEX.md (este)      | ~250       | 8 min          | Navegação     | ✅     |
| **TOTAL**            | **~3.600** | **~123 min**   | -             | **✅** |

**Nota:** Tempo de leitura é linear. Você não precisa ler tudo — escolha por interesse/papel.

---

## 📁 Estrutura de Diretórios

```
docs/
├── RESUMO_EXECUTIVO.md          ← Comece aqui (executivo)
├── CHECKLIST_ENTREGA.md         ← Status do projeto
├── GUIA_RAPIDO_TESTE.md         ← Execute hoje (30-45 min)
├── requisitos_v2.md             ← 17 RFs, 10 RNFs, 12 RNs
├── csv_layout.md                ← Formato de exportação
├── arquitetura.md               ← Componentes + fluxos
├── antifraude.md                ← Segurança (4 camadas)
├── plano_testes.md              ← 15 casos de teste
├── README.md                    ← Setup + troubleshooting
├── INDEX.md                     ← Você está aqui (navegação)
│
├── diagramas/                   ← Pronto para UML (vazio)
│   └── (adicionar: classe.png, sequencia.png, componentes.png, atividade.png)
│
└── prototipos/                  ← Pronto para wireframes (vazio)
    └── (adicionar: telas_1-6.png ou descrições.md)
```

---

## ✅ Checklist de Completude Documentação

- [x] Visão do projeto (RESUMO_EXECUTIVO.md)
- [x] Requisitos (requisitos_v2.md)
- [x] Antifraude (antifraude.md)
- [x] Arquitetura (arquitetura.md)
- [x] CSV Layout (csv_layout.md)
- [x] Testes Planejados (plano_testes.md)
- [x] Setup (README.md)
- [x] Índice de navegação (INDEX.md)
- [x] Guia rápido de teste (GUIA_RAPIDO_TESTE.md)
- [x] Checklist de entrega (CHECKLIST_ENTREGA.md)
- [ ] Diagramas UML (diagramas/ — pronto)
- [ ] Wireframes (prototipos/ — pronto)

---

## 🎯 Recomendações por Papel

### 👨‍💼 Professor / Avaliador

**Leia em ordem:**

1. [RESUMO_EXECUTIVO.md](RESUMO_EXECUTIVO.md) — Entender visão
2. [requisitos_v2.md](requisitos_v2.md) — Validar cobertura (17 RFs, 10 RNFs)
3. [antifraude.md](antifraude.md) — Avaliar segurança (RNF07)
4. [GUIA_RAPIDO_TESTE.md](GUIA_RAPIDO_TESTE.md) — Testar ao vivo

**Tempo total:** ~60 min (leitura + teste rápido)

### 👨‍💻 Desenvolvedor (Testando)

**Leia em ordem:**

1. [CHECKLIST_ENTREGA.md](CHECKLIST_ENTREGA.md) — Entender status
2. [GUIA_RAPIDO_TESTE.md](GUIA_RAPIDO_TESTE.md) — Teste rápido (30-45 min)
3. [plano_testes.md](plano_testes.md) — Teste completo (opcional)
4. [README.md](README.md) — Troubleshooting se necessário

**Tempo total:** ~45 min (teste rápido) a 2 horas (teste completo)

### 👨‍💻 Desenvolvedor (Implementando)

**Leia em ordem:**

1. [arquitetura.md](arquitetura.md) — Entender design
2. [antifraude.md](antifraude.md) — Segurança
3. [requisitos_v2.md](requisitos_v2.md) — Especificação
4. [README.md](README.md) — Setup local

**Tempo total:** ~80 min (compreensão completa)

### 🎤 Apresentador (PPTX / Video)

**Leia em ordem:**

1. [RESUMO_EXECUTIVO.md](RESUMO_EXECUTIVO.md) — Argumento central
2. [arquitetura.md](arquitetura.md) — Diagrama para slide
3. [antifraude.md](antifraude.md) — Detalhe de segurança
4. [GUIA_RAPIDO_TESTE.md](GUIA_RAPIDO_TESTE.md) — Demo script

**Tempo total:** ~50 min (preparação)

---

## 🚀 Próximas Ações (Por Prioridade)

### 🔴 CRÍTICO (Hoje/Amanhã)

- [ ] **Teste em dispositivo real**
  - Siga [GUIA_RAPIDO_TESTE.md](GUIA_RAPIDO_TESTE.md)
  - Tempo: 30-45 min
  - Resultado esperado: ✅ PASSOU

### 🟠 IMPORTANTE (Antes de Apresentar)

- [ ] **Criar PPTX**

  - Use [RESUMO_EXECUTIVO.md](RESUMO_EXECUTIVO.md) + [arquitetura.md](arquitetura.md)
  - 5-7 slides
  - Tempo: 1-2 horas

- [ ] **Gravar video ou preparar demo**
  - Use [GUIA_RAPIDO_TESTE.md](GUIA_RAPIDO_TESTE.md) como script
  - ~20 minutos de duração
  - Tempo: 1-2 horas (gravação + edição)

### 🟡 DESEJÁVEL (Após N3)

- [ ] **Adicionar diagramas UML**

  - Pasta: `docs/diagramas/`
  - Tipos: classe, sequência, componentes, atividade
  - Referenciar em [arquitetura.md](arquitetura.md)

- [ ] **Adicionar wireframes**
  - Pasta: `docs/prototipos/`
  - Telas: 6 (RoleSelection, Professor, Config, Aluno Join, Aluno Wait, Histórico)
  - Referenciar em [README.md](README.md)

---

## 🎓 Conclusão

Você tem **~3.600 linhas de documentação profissional** cobrindo:

✅ **Visão e Escopo** (RESUMO_EXECUTIVO.md)  
✅ **Especificação Completa** (requisitos_v2.md)  
✅ **Segurança Documentada** (antifraude.md — RNF07)  
✅ **Arquitetura Detalhada** (arquitetura.md)  
✅ **Testes Planejados** (plano_testes.md + GUIA_RAPIDO_TESTE.md)  
✅ **Setup e Troubleshooting** (README.md)

**Próximo passo:** Execute [GUIA_RAPIDO_TESTE.md](GUIA_RAPIDO_TESTE.md) **hoje** em 2 dispositivos.

---

**Índice de Documentação — SmartPresence v2.0**

_Última atualização: 20 de Novembro de 2025_

_Documentação completa ✅ | Código implementado ✅ | Testes planejados ✅ | Apresentação ⏳_
