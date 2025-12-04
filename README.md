# JSJ Extração de Legendas

Aplicação Streamlit para extração automática de dados de legendas de desenhos técnicos (PDF, DXF, DWG, JSON).

## 🎯 O que faz

- **Extrai dados de legendas** de desenhos técnicos usando IA (Google Gemini)
- **Suporta múltiplos formatos**: PDF, DXF, DWG, JSON (exportado de AutoCAD via LISP)
- **Exporta para CSV/XLSX** com 34 colunas normalizadas
- **Campos globais**: Preenche automaticamente dados do projeto em todas as linhas

## 📋 Requisitos do Sistema

- **Python 3.10+** (recomendado 3.11 ou 3.12)
- **Google Gemini API Key** (obter em https://aistudio.google.com/app/apikey)
- **Windows 10/11** (testado)

## 🚀 Instalação

### 1. Clonar ou copiar a pasta

```bash
# Se usar git:
git clone https://github.com/dmmgama/JSJ-ListaDesenhos.git
cd JSJ-ListaDesenhos

# Ou simplesmente copiar a pasta JSJ-ExtracaoLegendas para o PC
```

### 2. Criar ambiente virtual

```powershell
# No PowerShell, dentro da pasta:
python -m venv venv
```

### 3. Ativar o ambiente virtual

```powershell
.\venv\Scripts\Activate.ps1
```

### 4. Instalar dependências

```powershell
pip install -r requirements.txt
```

## ▶️ Como Usar

### 1. Ativar o ambiente virtual (se não estiver ativo)

```powershell
.\venv\Scripts\Activate.ps1
```

### 2. Executar a aplicação

```powershell
streamlit run JSJ_LEGENDAS_app.py
```

### 3. Abrir no browser

A aplicação abre automaticamente em `http://localhost:8501`

### 4. Configurar API Key

- Na barra lateral, inserir a **Google Gemini API Key**
- Ativar **Modo TURBO** se tiver conta Google Cloud paga

### 5. Processar desenhos

1. Preencher os **Dados do Projeto** (opcional - aplicados a todas as linhas)
2. Selecionar o **Tipo de Ficheiro** (PDF, JSON, DWG/DXF)
3. Carregar os ficheiros
4. Clicar em **⚡ Processar Lote**
5. Exportar para **XLSX** ou **CSV**

## 📁 Estrutura de Ficheiros

```
JSJ-ExtracaoLegendas/
├── JSJ_LEGENDAS_app.py   # Aplicação principal
├── requirements.txt      # Dependências Python
├── README.md             # Este ficheiro
├── .gitignore            # Ficheiros ignorados pelo git
└── venv/                 # Ambiente virtual (criado localmente)
```

## 🔧 Dependências Principais

- `streamlit` - Interface web
- `google-generativeai` - API Google Gemini
- `pandas` - Manipulação de dados
- `PyMuPDF (fitz)` - Leitura de PDFs
- `ezdxf` - Leitura de DXF/DWG
- `xlsxwriter` - Exportação Excel
- `reportlab` - Geração de PDFs

## 📊 Colunas Exportadas (34)

```
PROJ_NUM, PROJ_NOME, CLIENTE, OBRA, LOCALIZACAO, ESPECIALIDADE,
PROJETOU, FASE, FASE_PFIX, EMISSAO, DATA, PFIX, LAYOUT,
DES_NUM, TIPO, ELEMENTO, TITULO, REV_A, DATA_A, DESC_A,
REV_B, DATA_B, DESC_B, REV_C, DATA_C, DESC_C, REV_D,
DATA_D, DESC_D, REV_E, DATA_E, DESC_E, DWG_SOURCE, ID_CAD
```

## ⚠️ Notas

- O ficheiro exportado tem o nome `{DWG_SOURCE}-LD.xlsx` ou `{DWG_SOURCE}-LD.csv`
- Se DWG_SOURCE estiver vazio, usa `lista_desenhos_jsj` como nome
- A API Gemini tem limites de uso (15 req/min no free tier, 1000 req/min no paid tier)

## 📝 Licença

Uso interno JSJ Engenharia.
