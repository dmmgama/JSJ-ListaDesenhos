🏗️ CONTEXTO DO PROJETO: Gestor de Desenhos JSJ

🎯 Objetivo

Sistema local (Python + Streamlit) para ler PDFs técnicos, extrair metadados de legendas (especialmente datas de revisão) e gerar listas de emissão em Excel.

🛠️ Stack Tecnológica

Interface: Streamlit (jsj_app.py)

PDF Engine: PyMuPDF (fitz) - Leitura página a página

AI Engine: Google Gemini API (google-generativeai)

Dados: Pandas + XlsxWriter

⚠️ REGRAS DE OURO (Critérios de Aceitação)

Fonte da Verdade: A Tabela de Revisões Visual (desenhada na imagem) sobrepõe-se a qualquer texto ou metadado.

Lógica de Extração:

Identificar a letra de revisão mais alta na tabela (ex: C).

Extrair a data dessa linha específica.

Se a tabela estiver vazia, usar a data base (1ª emissão).

Gestão de Erros 404: Usar SEMPRE a lista de modelos prioritária: gemini-2.5-flash, gemini-2.0-flash, gemini-1.5-flash. (A conta atual só suporta v2.5/v2.0).

Multi-Página: Cada página de um PDF conta como um desenho independente.

📍 Estado Atual (Branch: feature/fase2-melhorias)

Funcional: Leitura em batch, loop multi-página, conexão Gemini v2.5, exportação básica.

Em Desenvolvimento (Fase 2):

UI de Lotes: Painel para ver que tipos (DIM, PIL) estão em memória.

Ordenação Mista: Ordenar primeiro por TIPO (Alfabetico) e depois por NÚMERO (Lógica natural).

Exportação Final: Botão dedicado para gerar o Excel final formatado.

📝 Estrutura de Dados (session_state)

Lista de dicionários com chaves: TIPO, Num. Desenho, Titulo, Revisão, Data, Ficheiro (com pág), Obs.