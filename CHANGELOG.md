# Changelog

Todas as alterações notáveis neste projeto serão documentadas aqui.

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/).

---

## [1.0.0] - 2025-12-04

### Adicionado
- Documentação completa (README, ARCHITECTURE, CHANGELOG)
- Suporte a 3 formatos de input: PDF, JSON (LISP), DWG/DXF
- Extração híbrida: nativa (zero custo) + Gemini AI (fallback)
- Rate limiting inteligente (sliding window)
- Modo TURBO para contas pagas (1000 req/min)
- Validação de dados extraídos
- Campos globais (batch fill) para projeto
- Exportação XLSX/CSV com 34 colunas normalizadas
- Reordenação customizada por tipo de desenho
- Preview de crop antes de processar
- Logging completo em `jsj_parser.log`
- Contador de tokens e custo estimado

### Alterado
- Unificação de `jsj_app.py` e `JSJ_LEGENDAS_app.py` (ficheiros duplicados)
- README reescrito com documentação clara

### Removido
- `jsj_app.py` deprecated (substituído por stub com erro)

---

## [0.9.0] - 2025-XX-XX (versão anterior não documentada)

### Funcionalidades iniciais
- Extração de legendas via Gemini
- Suporte PDF básico
- Exportação CSV
