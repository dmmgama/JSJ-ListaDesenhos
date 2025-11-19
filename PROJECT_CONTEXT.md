# 🏗️ CONTEXTO DO PROJETO: Gestor de Desenhos JSJ

## 🎯 Objetivo

Sistema local (Python + Streamlit) para ler PDFs técnicos e DWG/DXF, extrair metadados de legendas (especialmente datas de revisão) usando IA, e gerar listas de emissão profissionais em múltiplos formatos (Excel, PDF, Markdown).

---

## 🛠️ Stack Tecnológica

- **Interface:** Streamlit (jsj_app.py v2 Unified)
- **PDF Engine:** PyMuPDF (fitz) - Leitura página a página com crop configurável
- **CAD Engine:** ezdxf + matplotlib (opcional) - Suporte DWG/DXF
- **AI Engine:** Google Gemini API (gemini-2.5-flash, gemini-2.0-flash)
- **Dados:** Pandas + XlsxWriter
- **Export:** ReportLab (PDF profissional), XlsxWriter (Excel), Markdown
- **Logging:** Python logging → jsj_parser.log

---

## ⚠️ REGRAS DE OURO (Critérios de Aceitação)

### 1. Fonte da Verdade
**A Tabela de Revisões Visual** (desenhada na imagem) sobrepõe-se a qualquer texto ou metadado do ficheiro.

### 2. Lógica de Extração
1. Identificar a **letra de revisão mais alta** na tabela de revisões (ex: A, B, C → escolher C)
2. Extrair a **data dessa linha específica** (NÃO a data base da legenda)
3. Se a tabela estiver vazia → usar data base (1ª emissão, Rev 0)

### 3. Gestão de Erros 404
Lista prioritária de modelos Gemini:
1. `gemini-2.5-flash` (prioridade 1)
2. `gemini-2.0-flash` (prioridade 2)
3. `gemini-1.5-flash` (fallback)

### 4. Multi-Página/Multi-Layout
- **PDFs:** Cada página = 1 desenho independente
- **DWGs:** Cada layout Paper Space = 1 desenho (Model space deve ser ignorado)

---

## 📍 Estado Atual

### Branch Ativo
**`claude/implement-priorities-01WmA3k5LU9sjcStbtjV5iRf`**

### Versão
**JSJ Parser v2 (Unified)** - Unificação de jsj_app.py e jsjturbo.py num único ficheiro

### Última Atualização
**2025-11-19** - Implementação completa das 3 prioridades

---

## ✅ Funcionalidades Implementadas

### PRIORIDADE 1 - Integridade de Dados ✅ COMPLETO
- ✅ Validação robusta pós-IA (datas DD/MM/YYYY, revisões A-Z, números de desenho)
- ✅ Logging estruturado em `jsj_parser.log` para auditoria
- ✅ Try-except específico no JSON parsing com fallback
- ✅ Correção de bug de scoping da API key (agora passada como parâmetro)
- ✅ Substituição de bare excepts por exceções específicas

### PRIORIDADE 2 - Consolidação ✅ COMPLETO
- ✅ Unificação jsj_app.py + jsjturbo.py → ficheiro único
- ✅ Modo TURBO configurável (checkbox no sidebar)
  - Standard: 15 req/min, batch 5
  - TURBO: 1000 req/min, batch 50
- ✅ Versões pinadas no requirements.txt
- ✅ Remoção de dependências não utilizadas (watchdog, openpyxl)
- ✅ ezdxf/matplotlib marcados como opcionais

### PRIORIDADE 3 - UX ✅ COMPLETO
- ✅ Crop configurável com 5 presets:
  - Canto Inf. Direito (50%) - padrão
  - Canto Inf. Direito (30%) - área menor
  - Canto Inf. Direito (70%) - área maior
  - Metade Inferior (100% largura)
  - Página Inteira
- ✅ Preview visual do crop antes de processar
- ✅ Métricas por tipo no sidebar

### Outras Funcionalidades
- ✅ UI de Lotes em memória (sidebar)
- ✅ Ordenação customizável por TIPO
- ✅ Exportação multi-formato (XLSX, PDF, Markdown)
- ✅ Contador de tokens e custo estimado
- ✅ Suporte DWG/DXF (Paper Space layouts)

---

## 🐛 Problemas Conhecidos (Em Investigação)

### 1. Preview de Crop bloqueia processamento
**Status:** 🔴 Em debug
**Descrição:** Quando "Mostrar preview do crop" está ativo, após mostrar o preview a aplicação não processa o batch (Streamlit rerun perde estado do botão)

### 2. Data sendo lida da legenda base em vez da tabela de revisões
**Status:** 🔴 CRÍTICO - Em debug
**Descrição:** Com crop configurável ativo, IA está a ler data do campo "DATA" da legenda base em vez da data da linha da revisão mais recente na tabela. Preview mostra área correta (tabela visível), mas processamento lê errado.

**Comportamento esperado:** Ler data da tabela de revisões (Regra de Ouro #2)
**Comportamento atual:** Lê data base da legenda

### 3. DWG Model Space não é filtrado
**Status:** ⚠️ Conhecido
**Descrição:** `get_dwg_layouts()` retorna `['Model']` como fallback quando não há Paper Space. Deve retornar lista vazia e avisar utilizador.

---

## 📂 Estrutura de Ficheiros

```
/home/user/JSJ-ListaDesenhos/
├── jsj_app.py              (v2 Unified) - Aplicação principal
├── jsjturbo.py             (obsoleto, pode ser removido)
├── requirements.txt        - Dependências com versões pinadas
├── PROJECT_CONTEXT.md      - Este ficheiro
├── jsj_parser.log          - Log de execução (gerado automaticamente)
└── .gitignore
```

---

## 📝 Estrutura de Dados (session_state)

```python
st.session_state = {
    'master_data': [
        {
            'TIPO': 'BETAO',              # Tipo do lote (user input)
            'Num. Desenho': '2025-EST-001', # Extraído da legenda
            'Titulo': 'Foundation Plan',   # Extraído da legenda
            'Revisão': 'C',                # Letra mais alta da tabela
            'Data': '20/03/2025',          # Data da linha dessa revisão
            'Ficheiro': 'file.pdf (Pág. 1)', # Nome + contexto
            'Obs': ''                      # Avisos/erros de validação
        },
        # ... mais registos
    ],
    'total_tokens': 4250,
    'ordem_customizada': ['BETAO', 'METALICA', ...]
}
```

---

## 🔧 Configuração da Aplicação

### Sidebar (Configurações)
1. **Google Gemini API Key** (obrigatório)
2. **Modo TURBO** (opcional, requer paid tier)
3. **Área de Crop** (5 presets)
4. **Preview do Crop** (checkbox)
5. **Lotes em Memória** (visualização)
6. **Custo Estimado** (tokens + EUR/USD)

### Interface Principal
- **Esquerda:** Upload de ficheiros + processamento
- **Direita:** Tabela de dados + reordenação + export

---

## 🚀 Como Executar

```bash
# 1. Instalar dependências
pip install -r requirements.txt

# 2. (Opcional) Ativar suporte DWG
# Descomentar no requirements.txt:
# ezdxf==1.1.4
# matplotlib==3.8.2
pip install ezdxf matplotlib

# 3. Executar
streamlit run jsj_app.py

# 4. Ver logs
tail -f jsj_parser.log
```

---

## 📊 Métricas de Qualidade

| Aspeto | Estado | Nota |
|--------|--------|------|
| Conformidade c/ Regras de Ouro | ⚠️ 8/10 | Problema #2 viola Regra #2 |
| Validação de Dados | ✅ 10/10 | Robusta |
| Error Handling | ✅ 9/10 | Try-except específicos |
| Logging | ✅ 10/10 | Completo |
| UX | ⚠️ 7/10 | Problema #1 afeta usabilidade |
| Manutenibilidade | ✅ 9/10 | Código unificado |

---

## 🎯 Próximos Passos

### Debugging Urgente (Em Curso)
1. 🔴 Resolver Problema #2 (data errada da tabela)
2. 🔴 Resolver Problema #1 (preview bloqueia processamento)

### Melhorias Pendentes
3. ⚠️ Filtrar Model Space em DWGs (Problema #3)
4. 📝 Adicionar testes unitários
5. 🔍 Implementar histórico de batches (SQLite)

---

## 📚 Contexto para Novos Assistentes

Se estás a ler isto pela primeira vez:

1. **Branch atual:** `claude/implement-priorities-01WmA3k5LU9sjcStbtjV5iRf`
2. **Ficheiro principal:** `jsj_app.py` (v2 Unified)
3. **Problemas ativos:** Ver secção "Problemas Conhecidos"
4. **Não alterar:** Regras de Ouro (section ⚠️)
5. **Log crítico:** `jsj_parser.log` tem info de debug

**IMPORTANTE:** Antes de fazer alterações, ler REGRAS DE OURO e testar que não violam a Regra #2 (data da tabela de revisões).

---

## 📖 Histórico de Branches

| Branch | Estado | Descrição |
|--------|--------|-----------|
| `claude/implement-priorities-...` | ✅ Ativo | v2 Unified com 3 prioridades |
| `claude/analyze-repo-code-...` | ✅ Estável | v1 com jsj_app.py + jsjturbo.py separados |
| `claude/claude-md-...` | 🗑️ Obsoleto | Fase 1 inicial (pode eliminar) |

---

**Última atualização:** 2025-11-19 18:00
**Autor:** Claude (Anthropic)
**Status:** 🔴 Em debug ativo (Problemas #1 e #2)
