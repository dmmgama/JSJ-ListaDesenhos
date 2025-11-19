# 🏗️ CONTEXTO DO PROJETO: Gestor de Desenhos JSJ v3.0

## 🎯 Objetivo

Sistema local (Python + Streamlit) para ler desenhos técnicos em **PDF e DWG/DXF**, extrair metadados de legendas (número, título, revisão, data) usando IA, e gerar listas de emissão em múltiplos formatos (Excel, Markdown, PDF).

---

## 🛠️ Stack Tecnológica

| Componente | Tecnologia | Descrição |
|------------|-----------|-----------|
| **Interface** | Streamlit | Web UI responsiva com gestão de estado em sessão |
| **PDF Engine** | PyMuPDF (fitz) | Leitura, crop e renderização de páginas PDF |
| **DWG/DXF Engine** | ezdxf + matplotlib | Leitura de layouts CAD e renderização para imagem |
| **AI Engine** | Google Gemini API | Modelos v2.5-flash (prioritário), v2.0-flash (fallback) |
| **Rate Limiting** | asyncio + deque | Sliding window: 15 req/min (limite Gemini) |
| **Dados** | Pandas | Manipulação de tabelas e ordenação |
| **Export XLSX** | XlsxWriter | Excel formatado com colunas ajustadas |
| **Export PDF** | ReportLab | PDFs profissionais com tabelas estilizadas |

---

## ⚙️ Funcionalidades Principais

### 📄 **Processamento de Ficheiros**
- ✅ **PDF:** Multi-página (cada página = 1 desenho)
- ✅ **DWG/DXF:** Multi-layout (cada layout = 1 desenho)
- ✅ **Crop Inteligente:** 50% x 50% quadrante inferior direito (legenda + tabela revisões)
- ✅ **Processamento Assíncrono:** Batches de 5 páginas em paralelo (3x mais rápido)

### 🧠 **Extração de Metadados (IA)**
- ✅ Prompt otimizado para ler legendas visuais
- ✅ Extração de: Número Desenho, Título, Revisão (letra mais avançada), Data (da linha específica)
- ✅ Fallback multi-modelo: v2.5-flash → v2.0-flash → v1.5-flash
- ✅ Contagem de tokens com estimativa de custo (EUR/USD)

### 📊 **Gestão de Dados**
- ✅ **Lotes em Memória:** Acumular múltiplas sessões de upload
- ✅ **Reordenação por Tipo:** Sistema de cliques para ordem customizada
- ✅ **Exportação:**
  - **XLSX:** Formatado com colunas ajustadas
  - **Markdown:** Agrupado por tipo
  - **PDF:** Layout landscape A4, tabelas com cores corporativas, linhas alternadas

### 🎨 **UI/UX**
- ✅ Painel lateral com resumo de lotes (contador por tipo)
- ✅ Barra de progresso em tempo real
- ✅ Contador de tokens e custo estimado
- ✅ Botão de reset global

---

## ⚠️ REGRAS DE OURO (Critérios de Aceitação)

### 📋 **Fonte da Verdade**
> **A Tabela de Revisões Visual (desenhada na imagem) sobrepõe-se a qualquer texto, metadado ou nome de ficheiro.**

### 🔍 **Lógica de Extração**
1. **Ignorar completamente o nome do ficheiro**
2. Procurar campo "Nº DESENHO" na legenda (canto inferior direito)
3. Na tabela de revisões:
   - Identificar a **letra mais avançada** alfabeticamente (ex: se existe A, B, C → usar C)
   - Extrair a **data dessa linha específica** (NÃO a data base!)
4. Se tabela vazia → Rev "0" e data base da legenda

### 📄 **Multi-Página/Layout**
- **PDF:** Cada página = desenho independente
- **DWG:** Cada layout (paperspace) = desenho independente

### 🚨 **Gestão de Erros**
- Rate limiting automático (15 req/min)
- Fallback de modelos em cascata
- Mensagens de erro individuais por página/layout (não bloqueia batch)

---

## 📁 Arquitetura do Código

### **jsj_app.py** (Versão Completa - 728 linhas)
```
📦 Imports
├─ streamlit, fitz, pandas, genai, ezdxf, matplotlib, reportlab
│
📦 Classes
├─ RateLimiter: Sliding window para controlar requests/min
│
📦 Funções de Extração
├─ get_image_from_page(doc, page_num): PDF → crop 50%x50%
├─ get_image_from_dwg_layout(path, layout): DWG → render → crop
├─ get_dwg_layouts(path): Lista layouts de um DWG
│
📦 Funções de IA
├─ ask_gemini_async(): Wrapper assíncrono para Gemini
├─ _ask_gemini_sync(): Chamada síncrona com fallback multi-modelo
│
📦 Funções de Export
├─ create_pdf_export(df): Gera PDF profissional com ReportLab
│
📦 UI
├─ Sidebar: API Key, resumo de lotes, contador de tokens/custo
├─ Coluna Input: Upload de ficheiros, seleção de tipo, botão processar
├─ Coluna View: Tabela, reordenação, botões de export (XLSX/MD/PDF)
```

### **jsjturbo.py** (Versão Otimizada)
- Variante mais leve para testes rápidos
- Menos features, foco em performance

---

## 🐛 Issues Conhecidos (v3.0)

### ⚠️ **DWG Support - Em Bug**
- **Problema:** Renderização de layouts DWG não está 100% confiável
- **Sintomas:** 
  - Alguns layouts não renderizam corretamente
  - Erros ocasionais com paperspace vs modelspace
- **Workaround:** Usar PDF quando possível
- **Status:** Funcionalidade experimental

### ⚠️ **Deprecation Warning**
- Streamlit `use_container_width` será removido após 31/12/2025
- **Fix pendente:** Substituir por `width='stretch'`

---

## 📦 Dependências (requirements.txt)

```
streamlit          # Web framework
pymupdf           # PDF processing
pandas            # Data manipulation
openpyxl          # Excel read support
xlsxwriter        # Excel write with formatting
google-generativeai  # Gemini API
watchdog          # File watching (Streamlit)
ezdxf             # DWG/DXF reading
matplotlib        # DWG rendering
pillow            # Image processing
reportlab         # PDF generation
```

---

## 🚀 Como Usar

### 1️⃣ **Setup Inicial**
```powershell
# Ativar venv
.\venv\Scripts\Activate.ps1

# Instalar dependências
pip install -r requirements.txt

# Executar app
streamlit run jsj_app.py
```

### 2️⃣ **Workflow**
1. Colar **Google Gemini API Key** na barra lateral
2. Definir **Tipo** do lote (ex: "BETAO", "METALICA")
3. **Upload** de ficheiros PDF/DWG
4. Clicar **⚡ Processar Lote**
5. (Opcional) **Reordenar** tipos clicando nos botões
6. **Exportar** para XLSX/MD/PDF

### 3️⃣ **Gestão de Lotes**
- Carregar vários lotes sequencialmente (acumulam em memória)
- Reordenar tipos conforme necessário
- Limpar tudo com botão **🗑️ Limpar Toda a Memória**

---

## 📊 Estrutura de Dados

### **session_state.master_data** (Lista de Dicionários)
```python
{
    "TIPO": "BETAO",              # Definido pelo utilizador
    "Num. Desenho": "2025-EST-001",  # Extraído da legenda
    "Titulo": "Planta de Fundações",
    "Revisão": "C",               # Letra mais avançada da tabela
    "Data": "20/03/2025",         # Data da linha C (não data base!)
    "Ficheiro": "desenho.pdf (Pág. 1)",
    "Obs": ""                     # Erros/avisos da IA
}
```

### **session_state.total_tokens**
- Contador global de tokens consumidos
- Usado para calcular custo estimado

### **session_state.ordem_customizada**
- Lista ordenada de tipos clicados
- Controla ordem de apresentação na tabela

---

## 🏷️ Versões e Tags

| Tag | Descrição | Features |
|-----|-----------|----------|
| **v1.0** | Versão inicial | Leitura básica de PDF + Gemini |
| **v2.0** | Melhorias de performance | Async, rate limiting, reordering, token counter |
| **v3.0** | **Atual** | + DWG support (experimental), + Export PDF, jsjturbo.py |

---

## 🔐 Segurança

- ⚠️ **check_api.py contém API Key hardcoded** - usar apenas para testes locais
- ✅ Na app principal, API Key é input manual (não persistido)
- 🚫 Nunca fazer commit de ficheiros com chaves reais

---

## 📝 Notas de Desenvolvimento

### **Prompt Engineering**
O prompt do Gemini foi otimizado com:
- Instruções explícitas para ignorar nome de ficheiro
- Exemplo prático de extração de revisão
- Formato JSON estruturado para resposta

### **Rate Limiting**
- Implementação com sliding window (mais eficiente que fixed window)
- Ajustável via parâmetros da classe `RateLimiter`

### **Export PDF**
- Cores corporativas: `#1f4788` (azul escuro)
- Fonte: Helvetica (standard PDF)
- DPI: 200 para clareza
- Auto-truncate de campos longos

---

## 🎓 Lições Aprendidas

1. **Matplotlib precisa de backend 'Agg' em ambientes headless**
2. **DWG paperspace ≠ modelspace** - precisa de handling separado
3. **Streamlit multiselect não preserva ordem** - botões são melhores para reordering
4. **Gemini metadata pode não existir em todas as versões** - sempre validar `hasattr()`

---

## 🔮 Roadmap Futuro

- [ ] Fix completo de DWG rendering
- [ ] Suporte para DXF v2024+
- [ ] Cache de respostas IA (evitar re-processar mesmas páginas)
- [ ] Sistema de templates para diferentes formatos de legenda
- [ ] Integração com bases de dados (SQLite/PostgreSQL)
- [ ] API REST para integrações externas

---

**Última atualização:** v3.0 (19/11/2025)  
**Branch principal:** `main`  
**Autor:** JSJ AI Team
