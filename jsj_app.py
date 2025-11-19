import streamlit as st
import fitz  # PyMuPDF
import pandas as pd
import google.generativeai as genai
from PIL import Image
import io
import json
import time
import asyncio
from collections import deque

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

    # PAINEL DE LOTES CARREGADOS
    st.subheader("📦 Lotes em Memória")
    if len(st.session_state.master_data) > 0:
        # Agrupar por TIPO e contar
        df_temp = pd.DataFrame(st.session_state.master_data)
        summary = df_temp.groupby('TIPO').size().sort_index()

        for tipo, count in summary.items():
            st.metric(label=tipo, value=f"{count} desenhos")

        st.caption(f"**Total:** {len(st.session_state.master_data)} desenhos")
    else:
        st.info("Nenhum lote carregado ainda.")

    st.divider()
    st.caption("A tabela de revisões visual é a fonte de verdade.")

    if st.button("🗑️ Limpar Toda a Memória", type="primary"):
        st.session_state.master_data = []
        st.rerun()

# --- FUNÇÕES DE PROCESSAMENTO (BACKEND) ---

class RateLimiter:
    """Rate limiter inteligente para respeitar limites da API Gemini.

    Gemini Flash v2.5/v2.0: 15 requests/minuto
    Implementa sliding window para máxima eficiência.
    """
    def __init__(self, max_requests=15, time_window=60):
        self.max_requests = max_requests
        self.time_window = time_window
        self.requests = deque()

    async def acquire(self):
        """Aguarda até que seja seguro fazer um novo request."""
        now = time.time()

        # Remove requests antigos fora da janela
        while self.requests and self.requests[0] < now - self.time_window:
            self.requests.popleft()

        # Se atingiu o limite, espera o tempo mínimo necessário
        if len(self.requests) >= self.max_requests:
            sleep_time = self.requests[0] + self.time_window - now + 0.1
            await asyncio.sleep(sleep_time)
            return await self.acquire()  # Re-check após espera

        # Registra o novo request
        self.requests.append(now)

def get_image_from_page(doc, page_num):
    """Extrai a imagem (crop da legenda) de uma página específica do documento."""
    page = doc.load_page(page_num)

    # CROP OTIMIZADO: Quadrante inferior direito completo (50% x 50%)
    # Captura a zona da legenda e tabela de revisões de forma mais abrangente
    rect = page.rect
    crop_rect = fitz.Rect(
        rect.width * 0.50,   # Começa a 50% da largura (metade direita)
        rect.height * 0.50,  # Começa a 50% da altura (metade inferior)
        rect.width,
        rect.height
    )

    pix = page.get_pixmap(clip=crop_rect, matrix=fitz.Matrix(2, 2)) # 2x zoom para clareza
    img_data = pix.tobytes("png")

    return Image.open(io.BytesIO(img_data))

async def ask_gemini_async(image, file_context, rate_limiter):
    """O Cérebro Assíncrono: Processa requests em paralelo com rate limiting."""
    if not api_key:
        return {"error": "Sem API Key"}

    # Aguarda permissão do rate limiter
    await rate_limiter.acquire()

    # Executa a chamada síncrona da API em thread separada
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, _ask_gemini_sync, image, file_context)

def _ask_gemini_sync(image, file_context):
    """Wrapper síncrono para chamada ao Gemini (executado em thread pool)."""
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
    Age como um técnico de documentação. Analisa a LEGENDA VISUAL no canto inferior direito desta imagem de desenho técnico.

    REGRAS ESTRITAS (FONTE DE VERDADE - SÓ A IMAGEM CONTA):
    1. **IGNORA COMPLETAMENTE O NOME DO FICHEIRO.** Só olha para o que está DESENHADO/ESCRITO na imagem.
    2. Na LEGENDA (canto inferior direito), procura o campo "Nº DESENHO" ou "DESENHO Nº" ou similar.
    3. Extrai o NÚMERO DO DESENHO escrito nesse campo da legenda (ex: "2025-EST-001", "DIM-001", "PIL-2025-01").
    
    4. **TABELA DE REVISÕES (CRUCIAL):**
       - Procura a tabela de revisões (geralmente acima da legenda, com colunas REV/DATA/DESCRIÇÃO ou similar)
       - Identifica TODAS as linhas preenchidas na tabela
       - A revisão MAIS RECENTE é aquela com a letra MAIS AVANÇADA alfabeticamente (ex: se existe A, B, C → a mais recente é C)
       - Extrai a DATA que está NESSA LINHA ESPECÍFICA da revisão mais recente
       - ATENÇÃO: NÃO uses a data base da legenda se houver revisões! Usa SEMPRE a data da linha da tabela!
    
    5. **Se a tabela de revisões estiver completamente vazia ou não existir:**
       - Assume "1ª Emissão" (Rev 0)
       - Neste caso SIM, usa a data base que está na legenda principal
    
    **EXEMPLO PRÁTICO:**
    - Tabela tem linhas: A (10/01/2025), B (15/02/2025), C (20/03/2025)
    - Revisão mais recente = "C"
    - Data a extrair = "20/03/2025" (a data da linha C, NÃO a data base!)

    Retorna APENAS JSON válido com este formato:
    {
        "num_desenho": "string (O NÚMERO escrito na legenda visual, ex: 2025-EST-001)",
        "titulo": "string (título principal do desenho na legenda)",
        "revisao": "string (A LETRA mais avançada encontrada na tabela de revisões ou '0' se vazia)",
        "data": "string (A DATA da linha dessa revisão específica, ou data base se Rev 0)",
        "obs": "string (Avisos se ilegível ou campo em falta, senão vazio)"
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
            
            # Pré-processamento: Extrair todas as páginas
            all_tasks = []
            total_operations = 0
            
            for pdf_file in uploaded_files:
                try:
                    bytes_data = pdf_file.read()
                    doc = fitz.open(stream=bytes_data, filetype="pdf")
                    
                    for page_num in range(doc.page_count):
                        display_name = f"{pdf_file.name} (Pág. {page_num + 1})"
                        img = get_image_from_page(doc, page_num)
                        
                        all_tasks.append({
                            "image": img,
                            "display_name": display_name,
                            "batch_type": batch_type.upper()
                        })
                        total_operations += 1
                    
                    doc.close()
                except Exception as e:
                    st.error(f"Erro ao ler {pdf_file.name}: {e}")
            
            # Processamento Assíncrono em Paralelo
            async def process_all_pages():
                """Processa todas as páginas em paralelo com rate limiting."""
                rate_limiter = RateLimiter(max_requests=15, time_window=60)
                new_records = []
                
                # Criar tasks assíncronas para todas as páginas
                async_tasks = []
                for task_data in all_tasks:
                    async_tasks.append(
                        ask_gemini_async(
                            task_data["image"], 
                            task_data["display_name"],
                            rate_limiter
                        )
                    )
                
                # Processar em batches de 5 para não sobrecarregar
                batch_size = 5
                completed = 0
                
                for i in range(0, len(async_tasks), batch_size):
                    batch = async_tasks[i:i + batch_size]
                    batch_names = [all_tasks[j]["display_name"] for j in range(i, min(i + batch_size, len(all_tasks)))]
                    
                    status_text.text(f"A processar batch {i//batch_size + 1} ({len(batch)} páginas)...")
                    
                    # Executar batch em paralelo
                    results = await asyncio.gather(*batch, return_exceptions=True)
                    
                    # Processar resultados
                    for idx, data in enumerate(results):
                        task_idx = i + idx
                        task_info = all_tasks[task_idx]
                        
                        if isinstance(data, Exception):
                            data = {"error": str(data), "num_desenho": "ERRO", "titulo": task_info["display_name"]}
                        
                        record = {
                            "TIPO": task_info["batch_type"],
                            "Num. Desenho": data.get("num_desenho", "N/A"),
                            "Titulo": data.get("titulo", "N/A"),
                            "Revisão": data.get("revisao", "-"),
                            "Data": data.get("data", "-"),
                            "Ficheiro": task_info["display_name"],
                            "Obs": data.get("obs", "")
                        }
                        
                        if "error" in data:
                            record["Obs"] = f"Erro IA: {data['error']}"
                        
                        new_records.append(record)
                        completed += 1
                        progress_bar.progress(completed / total_operations)
                
                return new_records
            
            # Executar processamento assíncrono
            try:
                new_records = asyncio.run(process_all_pages())
                st.session_state.master_data.extend(new_records)
                status_text.success(f"✅ Processado! ({len(new_records)} desenhos extraídos)")
                time.sleep(1)
                st.rerun()
            except Exception as e:
                st.error(f"Erro no processamento: {e}")

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