import streamlit as st
import fitz  # PyMuPDF
import pandas as pd
import google.generativeai as genai
from PIL import Image
import io
import json
import time

# --- CONFIGURAÇÃO DA PÁGINA ---
st.set_page_config(
    page_title="JSJ Parser v1",
    page_icon="🏗️",
    layout="wide"
)

# --- INICIALIZAÇÃO DO ESTADO (MEMÓRIA TEMPORÁRIA) ---
if 'master_data' not in st.session_state:
    st.session_state.master_data = []

# --- BARRA LATERAL (CONFIGURAÇÃO) ---
with st.sidebar:
    st.header("⚙️ Configuração")
    api_key = st.text_input("Google Gemini API Key", type="password")
    
    st.divider()
    st.caption("A tabela de revisões visual é a fonte de verdade.")
    
    if st.button("🗑️ Limpar Toda a Memória", type="primary"):
        st.session_state.master_data = []
        st.rerun()

# --- FUNÇÕES DE PROCESSAMENTO (BACKEND) ---

def get_image_from_page(doc, page_num):
    """Extrai a imagem (crop da legenda) de uma página específica do documento."""
    page = doc.load_page(page_num)
    
    # Crop inteligente: Pega nos 40% inferiores e 60% à direita
    rect = page.rect
    crop_rect = fitz.Rect(rect.width * 0.4, rect.height * 0.4, rect.width, rect.height)
    
    pix = page.get_pixmap(clip=crop_rect, matrix=fitz.Matrix(2, 2)) # 2x zoom para clareza
    img_data = pix.tobytes("png")
    
    return Image.open(io.BytesIO(img_data))

def ask_gemini(image, file_context):
    """O Cérebro: Tenta modelos confirmados na tua conta (v2.5/v2.0)."""
    if not api_key:
        return {"error": "Sem API Key"}

    genai.configure(api_key=api_key)
    
    # LISTA DE MODELOS ATUALIZADA
    models_to_try = [
        'gemini-2.5-flash',          # PRIORIDADE 1
        'gemini-2.0-flash',          # PRIORIDADE 2
        'gemini-1.5-flash',          # Fallback Standard
        'gemini-1.5-flash-latest',   # Fallback Alias
        'gemini-pro'                 # Legacy
    ]

    prompt = """
    Age como um técnico de documentação. Analisa a Legenda e a Tabela de Revisões desta imagem.
    
    REGRAS ESTRITAS (FONTE DE VERDADE):
    1. Ignora o nome do ficheiro. Olha apenas para a imagem.
    2. Procura a "Tabela de Revisões" (geralmente acima da legenda).
    3. Identifica a letra da revisão MAIS RECENTE preenchida (ex: Se tiver A, B e C, a mais recente é C).
    4. Extrai a DATA escrita nessa linha específica da tabela (linha da revisão mais recente).
    5. Se a tabela estiver vazia, assume que é "1ª Emissão" (Rev 0) e usa a data base da legenda.

    Retorna APENAS JSON válido com este formato:
    {
        "num_desenho": "string (ex: 2025-EST-001)",
        "titulo": "string (titulo principal)",
        "revisao": "string (A letra encontrada na tabela ou '0')",
        "data": "string (A data encontrada na linha correspondente à revisão)",
        "obs": "string (Qualquer aviso se a imagem estiver ilegível, senão vazio)"
    }
    """

    last_error = ""

    # LOOP DE TENTATIVAS (ROBUST FALLBACK)
    for model_name in models_to_try:
        try:
            model = genai.GenerativeModel(model_name)
            response = model.generate_content([prompt, image])
            
            # Se chegou aqui, funcionou!
            clean_text = response.text.replace("```json", "").replace("```", "").strip()
            return json.loads(clean_text)
            
        except Exception as e:
            last_error = str(e)
            continue

    return {"error": f"Falha IA. Último erro: {last_error}", "num_desenho": "ERRO", "titulo": file_context}

# --- INTERFACE PRINCIPAL (FRONTEND) ---

st.title("🏗️ Gestor de Desenhos JSJ")
st.markdown("---")

col_input, col_view = st.columns([1, 2])

with col_input:
    st.subheader("1. Novo Lote")
    batch_type = st.text_input("🏷️ Tipo deste lote", placeholder="Ex: BETAO, METALICA, PIL...", help="Aplica-se a todos os PDFs carregados agora.")
    uploaded_files = st.file_uploader("📄 Carregar PDFs", type="pdf", accept_multiple_files=True)
    process_btn = st.button("⚡ Processar Lote", disabled=(not uploaded_files or not batch_type))

    if process_btn:
        if not api_key:
            st.error("⚠️ Falta a API Key na barra lateral!")
        else:
            progress_bar = st.progress(0)
            status_text = st.empty()
            new_records = []
            
            total_operations = 0
            # Pré-cálculo para a barra de progresso (contar páginas totais)
            files_data = []
            for pdf_file in uploaded_files:
                try:
                    bytes_data = pdf_file.read()
                    doc = fitz.open(stream=bytes_data, filetype="pdf")
                    total_operations += doc.page_count
                    files_data.append({"name": pdf_file.name, "doc": doc})
                except:
                    pass
            
            current_op = 0
            
            # LOOP PRINCIPAL
            for file_item in files_data:
                doc = file_item["doc"]
                fname = file_item["name"]
                
                # ITERAR POR TODAS AS PÁGINAS DO PDF
                for page_num in range(doc.page_count):
                    current_op += 1
                    display_name = f"{fname} (Pág. {page_num + 1})"
                    status_text.text(f"A analisar: {display_name}...")
                    
                    try:
                        # 1. Imagem da página específica
                        img = get_image_from_page(doc, page_num)
                        
                        # 2. IA
                        data = ask_gemini(img, display_name)
                        
                        # 3. Montar Registo
                        record = {
                            "TIPO": batch_type.upper(),
                            "Num. Desenho": data.get("num_desenho", "N/A"),
                            "Titulo": data.get("titulo", "N/A"),
                            "Revisão": data.get("revisao", "-"),
                            "Data": data.get("data", "-"),
                            "Ficheiro": display_name, # Nome + Página
                            "Obs": data.get("obs", "")
                        }
                        if "error" in data:
                            record["Obs"] = f"Erro IA: {data['error']}"

                        new_records.append(record)
                        
                        # Delay para não exceder Rate Limit (1.5s)
                        time.sleep(1.5)
                        
                    except Exception as e:
                        st.error(f"Erro em {display_name}: {e}")
                    
                    progress_bar.progress(current_op / total_operations)
                
                doc.close()

            st.session_state.master_data.extend(new_records)
            status_text.success(f"✅ Processado! ({len(new_records)} desenhos extraídos)")
            time.sleep(1)
            st.rerun()

with col_view:
    st.subheader("2. Lista Completa")
    if len(st.session_state.master_data) > 0:
        df = pd.DataFrame(st.session_state.master_data)
        if "Num. Desenho" in df.columns and "TIPO" in df.columns:
            df = df.sort_values(by=["TIPO", "Num. Desenho"])
        
        st.dataframe(
            df, 
            use_container_width=True,
            column_config={"Ficheiro": st.column_config.TextColumn("Origem"), "Obs": st.column_config.TextColumn("Obs", width="small")},
            hide_index=True
        )
        
        buffer = io.BytesIO()
        with pd.ExcelWriter(buffer, engine='xlsxwriter') as writer:
            df.to_excel(writer, index=False, sheet_name='Lista Mestra JSJ')
            writer.sheets['Lista Mestra JSJ'].set_column(0, 5, 20)
            
        st.download_button("📥 Descarregar Excel", data=buffer.getvalue(), file_name="lista_desenhos_jsj.xlsx", mime="application/vnd.ms-excel")
    else:
        st.info("Define um 'Tipo' e carrega ficheiros.")