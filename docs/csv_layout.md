# CSV Layout - SmartPresence

**Versão:** 2.0  
**Data:** 20 de Novembro de 2025

## Especificação do Arquivo CSV

### Propriedades Gerais

| Propriedade         | Valor                                                            |
| ------------------- | ---------------------------------------------------------------- |
| **Nome do Arquivo** | `presenca_smartpresence_YYYYMMDD_HHmmss.csv`                     |
| **Exemplo**         | `presenca_smartpresence_20251120_193500.csv`                     |
| **Codificação**     | UTF-8 (sem BOM)                                                  |
| **Delimitador**     | Vírgula (`,`)                                                    |
| **Quebra de Linha** | LF (Unix) ou CRLF (Windows)                                      |
| **Escape**          | Aspas duplas (`"`) para campos com virgula/quebra                |
| **Local**           | Downloads (Android `DOWNLOADS` ou `DOCUMENTS`)                   |
| **Permissão**       | Requer `WRITE_EXTERNAL_STORAGE` + `Permission.storage.request()` |

---

## Colunas

### 1. **matricula** (String)

- **Tipo:** Identificador único
- **Formato:** Alfanumérico (ex: `202301`, `A00123`, `MAT-001`)
- **Obrigatório:** Sim
- **Exemplo:** `202301`
- **Notas:** Deve corresponder ao inserido pelo aluno no JOIN

### 2. **nome** (String)

- **Tipo:** Nome completo do aluno
- **Formato:** Texto livre
- **Obrigatório:** Sim (ou "Nome Desconhecido" se não fornecido)
- **Exemplo:** `João Silva dos Santos`
- **Notas:** Salvo do JOIN ou atualizado se aluno reconectar

### 3. **data** (String)

- **Tipo:** Data da aula/sessão
- **Formato:** `YYYY-MM-DD` (ISO 8601)
- **Obrigatório:** Sim
- **Exemplo:** `2025-11-20`
- **Notas:** Data do dia em que o CSV foi exportado

### 4. **rodada** (String)

- **Tipo:** Identificador da rodada
- **Formato:** `Rodada 1`, `Rodada 2`, ..., `Rodada 4` (ou configurado)
- **Obrigatório:** Sim
- **Exemplo:** `Rodada 1`
- **Notas:** Deve corresponder ao nome configurado em `ConfiguracoesScreen`

### 5. **status** (String)

- **Tipo:** Status de presença
- **Formato:** Enumerado
  - `Presente` — PIN correto enviado dentro do prazo
  - `Ausente` — Nenhum PIN enviado ou rodada encerrada sem registro
  - `Falhou PIN` — PIN incorreto
  - `Falhou PIN (Rede)` — Validação SubnetCheck falhou
- **Obrigatório:** Sim
- **Exemplo:** `Presente`
- **Notas:** Define o resultado final da rodada para o aluno

### 6. **gravado_em** (String)

- **Tipo:** Timestamp de registro
- **Formato:** `HH:mm:ss` (hora:minuto:segundo em 24h)
- **Obrigatório:** Sim (pode usar hora da exportação se não houver registro)
- **Exemplo:** `19:35:42`
- **Notas:** Hora em que a presença foi registrada ou rodada foi encerrada

### 7. **notas** (String)

- **Tipo:** Campo livre para observações
- **Formato:** Texto livre (opcional)
- **Obrigatório:** Não
- **Exemplo:** `Atraso justificado`, `Ausência abonada`, `` (vazio)
- **Notas:** Deixar vazio se não aplicável; professor pode preencher manualmente

### 8. **metodo_validacao** (String)

- **Tipo:** Método antifraude aplicado
- **Formato:** Enumerado
  - `SubnetCheck` — Validação de IP na mesma sub-rede
  - `SubnetCheck + Rate Limit` — Passou por ambas
  - `Rate Limit Exceeded` — Bloqueado por muitas tentativas
  - `Localhost` — Conexão local (teste/emulador)
  - `Nenhum` — Sem validação especial
- **Obrigatório:** Sim
- **Exemplo:** `SubnetCheck`
- **Notas:** Rastreia método de validação usado para cada presença

---

## Estrutura Completa (Exemplo)

```csv
"matricula","nome","data","rodada","status","gravado_em","notas","metodo_validacao"
"202301","João Silva","2025-11-20","Rodada 1","Presente","19:35:42","","SubnetCheck"
"202302","Maria Santos","2025-11-20","Rodada 1","Falhou PIN","19:36:10","3 tentativas","SubnetCheck + Rate Limit"
"202303","Pedro Oliveira","2025-11-20","Rodada 1","Falhou PIN (Rede)","19:40:15","IP fora da rede","SubnetCheck"
"202304","Ana Costa","2025-11-20","Rodada 1","Ausente","20:00:00","Nenhuma tentativa","SubnetCheck"
"202301","João Silva","2025-11-20","Rodada 2","Presente","19:55:42","","SubnetCheck"
"202302","Maria Santos","2025-11-20","Rodada 2","Presente","19:56:05","","SubnetCheck"
"202303","Pedro Oliveira","2025-11-20","Rodada 2","Ausente","20:00:00","Saiu da sala","SubnetCheck"
"202304","Ana Costa","2025-11-20","Rodada 2","Presente","19:54:50","Reconectou","SubnetCheck"
"202301","João Silva","2025-11-20","Rodada 3","Presente","20:15:42","","SubnetCheck"
"202302","Maria Santos","2025-11-20","Rodada 3","Ausente","20:30:00","Desconectado","SubnetCheck"
"202303","Pedro Oliveira","2025-11-20","Rodada 3","Ausente","20:30:00","Desconectado","SubnetCheck"
"202304","Ana Costa","2025-11-20","Rodada 3","Presente","20:14:50","","SubnetCheck"
"202301","João Silva","2025-11-20","Rodada 4","Presente","20:35:42","","SubnetCheck"
"202302","Maria Santos","2025-11-20","Rodada 4","Ausente","20:50:00","Saiu","SubnetCheck"
"202303","Pedro Oliveira","2025-11-20","Rodada 4","Ausente","20:50:00","Saiu","SubnetCheck"
"202304","Ana Costa","2025-11-20","Rodada 4","Presente","20:34:50","","SubnetCheck"
```

---

## Instruções de Exportação

1. **Permissões Requeridas:**

   - `WRITE_EXTERNAL_STORAGE` e `READ_EXTERNAL_STORAGE` (manifest)
   - `Permission.storage.request()` em runtime (Android 6+)

2. **Processo:**

   - Professor clica em **"Exportar CSV"** em `ProfessorHostScreen`
   - Sistema gera arquivo com timestamp (ex: `presenca_smartpresence_20251120_193500.csv`)
   - Arquivo salvo em `Downloads` ou `Documents`
   - Notificação: "CSV exportado para: /storage/emulated/0/Downloads/presenca_smartpresence_20251120_193500.csv"

3. **Acesso ao Arquivo:**

   - Android 10+: Arquivo acessível via gerenciador de arquivos ou app de documentos
   - Compartilhamento: Via `share_plus` intent para email, Google Drive, etc.

4. **Validação:**
   - Abrir em planilha (Excel, Google Sheets, LibreOffice)
   - Validar codificação UTF-8
   - Conferir se colunas estão corretas

---

## Tratamento de Casos Especiais

### Caracteres Especiais

- Campos com `"`, `,` ou quebra de linha devem ser escapados com aspas duplas:
  ```csv
  "202301","Silva, João da Costa","2025-11-20","Rodada 1","Presente","19:35:42","Nota ""urgente""","SubnetCheck"
  ```

### Valores Vazios

- Notas: deixar vazio (`""`)
- Matrícula: nunca vazio (usar `"MATRICULA_INVALIDA"` se necessário)

### Aluno Sem Matrícula

- Usar placeholder: `"MATRICULA_INVALIDA"`
- Status: marcar como `Falhou PIN (Validação)`
- Notas: `"Aluno sem matrícula registrada"`

---

## Compatibilidade

| Software             | Status | Notas                              |
| -------------------- | ------ | ---------------------------------- |
| **Excel**            | ✅     | Abrir em Excel 2016+ ou Office 365 |
| **Google Sheets**    | ✅     | Importar como CSV (UTF-8)          |
| **LibreOffice Calc** | ✅     | Delimitador: vírgula               |
| **Numbers (Mac)**    | ✅     | Usar Open → CSV                    |
| **Python pandas**    | ✅     | `pd.read_csv('presenca_*.csv')`    |
| **PowerBI**          | ✅     | Import CSV like data source        |

---

## Geração no Código

```dart
// Em professor_host_screen.dart, _exportarCSV()
List<List<String>> rows = [];
rows.add(['matricula', 'nome', 'data', 'rodada', 'status', 'gravado_em', 'notas', 'metodo_validacao']);

for (var matricula in matriculas) {
  final nomeAluno = _alunoNomes[matricula] ?? 'Nome Desconhecido';
  for (var rodada in _rodadas) {
    final status = presencasRodadas[rodada.nome] ?? 'Ausente';
    rows.add([
      matricula,
      nomeAluno,
      dateFormat.format(now),
      rodada.nome,
      status,
      timeFormat.format(now),
      '', // notas
      'SubnetCheck', // metodo
    ]);
  }
}

String csvContent = rows.map(
  (row) => row.map((item) => '"${item.replaceAll('"', '""')}"').join(','),
).join('\n');
```

---

## Checklist de Validação (N3)

- [ ] Arquivo criado com nome correto (timestamp)
- [ ] Codificação UTF-8 sem BOM
- [ ] 8 colunas presentes com nomes exatos
- [ ] Dados separados por vírgula
- [ ] Campos com aspas duplas (escape correto)
- [ ] Todas as rodadas configuradas aparecem no CSV
- [ ] Status válidos (Presente, Ausente, Falhou PIN, Falhou PIN (Rede))
- [ ] Arquivo acessível em Downloads ou compartilhável via intent

---

**Especificação final para N3. Testar em dispositivo real antes da entrega.**
