# JSJ Extração de Legendas

Aplicação Streamlit para extração automática de dados de legendas de desenhos técnicos.

## 🎯 O que faz

Extrai metadados de legendas de desenhos técnicos de engenharia civil (JSJ - Sistemas Estruturais) e exporta para CSV/XLSX normalizado com 34 colunas.

**Fontes de dados suportadas:**
- **PDF** → Análise via Google Gemini (OCR + IA)
- **JSON** → Exportado de AutoCAD via LISP (zero custo API)
- **DWG/DXF** → Extração nativa de blocos LEGENDA_JSJ_V1 ou fallback Gemini

---

## 📋 Requisitos

| Requisito | Versão | Notas |
|-----------|--------|-------|
| Python | 3.10+ | Recomendado 3.11/3.12 |
| OS | Windows 10/11 | Testado |
| Google Gemini API Key | - | [Obter aqui](https://aistudio.google.com/app/apikey) |

---

## 🚀 Instalação

```powershell
# 1. Clonar/copiar pasta
git clone https://github.com/seu-usuario/JSJ-LISTADESENHOS.git
cd JSJ-LISTADESENHOS

# 2. Criar e ativar venv
python -m venv venv
.\venv\Scripts\Activate.ps1

# 3. Instalar dependências
pip install -r requirements.txt
```

### Suporte DWG/DXF (opcional)

Para processar ficheiros DWG/DXF nativamente:
```powershell
pip install ezdxf matplotlib
```

---

## ▶️ Uso

```powershell
# Ativar venv (se não estiver)
.\venv\Scripts\Activate.ps1

# Executar
streamlit run JSJ_LEGENDAS_app.py
```

Abre automaticamente em `http://localhost:8501`

### Workflow básico

1. Inserir **API Key** na sidebar
2. (Opcional) Preencher **Dados do Projeto** globais
3. Selecionar **Tipo de Ficheiro** (PDF/JSON/DWG)
4. Carregar ficheiros
5. **Processar Lote**
6. **Exportar** XLSX ou CSV

---

## 📁 Estrutura do Projeto

```
JSJ-LISTADESENHOS/
├── JSJ_LEGENDAS_app.py   # Aplicação principal (único ponto de entrada)
├── requirements.txt      # Dependências Python
├── README.md             # Este ficheiro
├── ARCHITECTURE.md       # Documentação técnica para devs/LLMs
├── CHANGELOG.md          # Histórico de versões
├── .gitignore            # Ficheiros ignorados
└── venv/                 # Ambiente virtual (local, não versionado)
```

---

## 📊 Schema de Output (34 colunas)

```
PROJ_NUM, PROJ_NOME, CLIENTE, OBRA, LOCALIZACAO, ESPECIALIDADE,
PROJETOU, FASE, FASE_PFIX, EMISSAO, DATA, PFIX, LAYOUT,
DES_NUM, TIPO, ELEMENTO, TITULO, REV_A, DATA_A, DESC_A,
REV_B, DATA_B, DESC_B, REV_C, DATA_C, DESC_C, REV_D,
DATA_D, DESC_D, REV_E, DATA_E, DESC_E, DWG_SOURCE, ID_CAD
```

---

## ⚙️ Modos de Operação

| Modo | Rate Limit | Batch Size | Requisito |
|------|------------|------------|-----------|
| Standard | 15 req/min | 5 | Free tier Gemini |
| TURBO | 1000 req/min | 50 | Conta Google Cloud paga |

---

## 🔧 Configuração Avançada

### Área de Crop (PDFs)

A sidebar permite configurar que região da página é analisada:
- `Canto Inf. Direito (50%)` — Padrão, legendas típicas
- `Canto Inf. Direito (30-70%)` — Ajuste fino
- `Metade Inferior` — Legendas largas
- `Página Inteira` — Fallback

### Ficheiros JSON (LISP AutoCAD)

Suporta dois formatos:
1. **Array direto**: `[{atributos: {...}}, ...]`
2. **Wrapper**: `{desenhos: [...], metadata: {...}}`

---

## 📝 Notas

- Ficheiro exportado: `{DWG_SOURCE}-LD.xlsx` ou `lista_desenhos_jsj.xlsx`
- Logs em `jsj_parser.log`
- Encoding CSV: UTF-8 com BOM (compatível Excel PT)

---

## 📄 Licença

Uso interno JSJ Engenharia.
