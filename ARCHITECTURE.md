# Arquitetura — JSJ Extração de Legendas

Documentação técnica para desenvolvedores e LLMs que precisem manter/estender o código.

---

## 📐 Visão Geral

```
┌─────────────────────────────────────────────────────────────────┐
│                        STREAMLIT UI                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │ Sidebar  │  │  Input   │  │  Table   │  │  Export  │        │
│  │ Config   │  │  Panel   │  │  View    │  │  Buttons │        │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      PROCESSING LAYER                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ PDF Handler │  │ JSON Handler│  │ DWG Handler │              │
│  │ (PyMuPDF)   │  │ (native)    │  │ (ezdxf)     │              │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘              │
│         │                │                │                     │
│         ▼                ▼                ▼                     │
│  ┌─────────────────────────────────────────────────┐           │
│  │              HYBRID EXTRACTION                   │           │
│  │  ┌─────────────────┐  ┌─────────────────┐       │           │
│  │  │ Native (DXF/JSON)│  │ Gemini AI (PDF) │       │           │
│  │  │ Zero cost        │  │ API cost        │       │           │
│  │  └─────────────────┘  └─────────────────┘       │           │
│  └─────────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      DATA LAYER                                 │
│  ┌─────────────────────────────────────────────────┐           │
│  │ st.session_state.master_data (list[dict])       │           │
│  │ Schema: 34 colunas normalizadas (COLUNAS_NORM.) │           │
│  └─────────────────────────────────────────────────┘           │
│                              │                                  │
│              ┌───────────────┼───────────────┐                  │
│              ▼               ▼               ▼                  │
│         ┌────────┐     ┌────────┐     ┌────────┐               │
│         │  XLSX  │     │  CSV   │     │  PDF   │               │
│         │ Export │     │ Export │     │ Export │               │
│         └────────┘     └────────┘     └────────┘               │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🧩 Componentes Principais

### 1. `JSJ_LEGENDAS_app.py` (único ficheiro)

| Secção | Linhas | Responsabilidade |
|--------|--------|------------------|
| Imports & Config | 1-80 | Dependências, logging, feature flags |
| `validate_extracted_data()` | 81-160 | Validação de dados pós-extração |
| `RateLimiter` class | ~200 | Sliding window rate limiting async |
| `get_crop_coordinates()` | ~230 | Cálculo de crop baseado em preset |
| `get_image_from_page()` | ~260 | Extração de imagem de PDF |
| `extract_dwg_native_blocks()` | ~290 | Extração nativa de blocos DWG |
| `get_image_from_dwg_layout()` | ~370 | Rendering DWG para imagem |
| `get_dwg_layouts()` | ~430 | Lista Paper Space layouts |
| `create_pdf_export()` | ~470 | Geração de PDF com ReportLab |
| `ask_gemini_async()` | ~550 | Wrapper async para Gemini |
| `_ask_gemini_sync()` | ~580 | Chamada síncrona ao Gemini |
| UI: Sidebar | ~700 | Configuração, API key, modos |
| UI: Input Panel | ~800 | Upload, tipo, campos globais |
| UI: Processing | ~950 | Loop principal de processamento |
| UI: Table View | ~1200 | DataFrame, ordenação, export |

---

## 🔄 Fluxo de Dados

### Input → Processing

```python
# 1. Upload de ficheiros
uploaded_files = st.file_uploader(...)

# 2. Pré-processamento: construir lista de tasks
all_tasks = []
for file in files:
    if file.ext == 'json':
        # Parse JSON, criar native_data tasks
        all_tasks.append({"native_data": {...}, "is_native": True})
    elif file.ext == 'pdf':
        # Extrair imagem por página
        all_tasks.append({"image": img, "is_native": False})
    elif file.ext in ['dwg', 'dxf']:
        # Tentar extração nativa, fallback para imagem
        blocks = extract_dwg_native_blocks(path, layout)
        if blocks:
            all_tasks.append({"native_data": block, "is_native": True})
        else:
            all_tasks.append({"image": img, "is_native": False})

# 3. Processamento assíncrono
native_tasks = [t for t in all_tasks if t["is_native"]]
gemini_tasks = [t for t in all_tasks if not t["is_native"]]

# Native: instantâneo
for task in native_tasks:
    records.append(normalize(task["native_data"]))

# Gemini: async com rate limiting
results = await asyncio.gather(*[ask_gemini_async(t) for t in gemini_tasks])
```

### Processing → Output

```python
# 4. Normalização para schema fixo
COLUNAS_NORMALIZADAS = [
    'PROJ_NUM', 'PROJ_NOME', 'CLIENTE', 'OBRA', ...  # 34 colunas
]

# 5. Merge com campos globais
record = {
    "PROJ_NUM": global_fields.get('PROJ_NUM', ''),
    "DES_NUM": extracted_data.get('num_desenho', 'N/A'),
    ...
}

# 6. Append ao session_state
st.session_state.master_data.append(record)

# 7. Export
df = pd.DataFrame(st.session_state.master_data)
df[COLUNAS_NORMALIZADAS].to_excel(buffer)
```

---

## 🎯 Pontos de Extensão

### Adicionar novo formato de input

```python
# Em ~linha 950, dentro do loop de ficheiros:
elif file_ext == 'novo_formato':
    # 1. Parse do ficheiro
    data = parse_novo_formato(file.read())
    
    # 2. Criar task (native ou image)
    all_tasks.append({
        "native_data": data,  # ou "image": img
        "is_native": True,    # ou False para Gemini
        "display_name": f"{file.name}",
        "batch_type": batch_type
    })
```

### Adicionar nova coluna ao schema

1. Adicionar a `COLUNAS_NORMALIZADAS` (linha ~100)
2. Mapear no record de processamento (linhas ~1000 e ~1100)
3. Adicionar ao prompt Gemini se necessário (linha ~600)

### Modificar prompt Gemini

Localização: função `_ask_gemini_sync()`, variável `prompt` (~linha 600)

```python
prompt = """
    # Adicionar/modificar campos aqui
    📋 CAMPOS A EXTRAIR DA LEGENDA:
    ...
"""
```

---

## ⚠️ Regras de Negócio Críticas

1. **Model Space ignorado** — Apenas Paper Space layouts são processados (DWG)
2. **Revisões A→E** — Ordem crescente, última preenchida é a atual
3. **Extração híbrida** — Nativa (zero custo) tem prioridade sobre Gemini
4. **Rate limiting** — 15 req/min free tier, 1000 req/min paid
5. **Validação** — Dados extraídos são validados antes de adicionar

---

## 🔧 Dependências Críticas

| Pacote | Uso | Alternativa |
|--------|-----|-------------|
| `streamlit` | UI | - |
| `google-generativeai` | OCR/extração PDF | OpenAI Vision (requer refactor) |
| `pymupdf` (fitz) | Leitura PDF | pdf2image + poppler |
| `ezdxf` | Leitura DWG/DXF | ODA File Converter (externo) |
| `pandas` | Data manipulation | - |
| `xlsxwriter` | Export Excel | openpyxl |

---

## 🐛 Debugging

### Logs

```powershell
# Ver logs em tempo real
Get-Content jsj_parser.log -Wait -Tail 50
```

### Session State

```python
# Adicionar temporariamente no código para debug:
st.write("DEBUG master_data:", st.session_state.master_data)
st.write("DEBUG global_fields:", st.session_state.global_fields)
```

### Gemini Response

```python
# Em _ask_gemini_sync(), após response:
logger.debug(f"Resposta bruta Gemini: {response.text[:500]}")
```

---

## 📝 TODO / Melhorias Futuras

- [ ] Testes unitários (pytest)
- [ ] Cache de resultados Gemini (evitar re-processamento)
- [ ] Suporte multi-idioma no prompt
- [ ] Preview de extração antes de confirmar
- [ ] Integração com base de dados (SQLite/PostgreSQL)
