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
import tempfile
import os
from datetime import datetime

# Imports para Relatórios PDF
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, PageBreak
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm
from reportlab.lib.enums import TA_CENTER

# Imports Opcionais para DWG
try:
    import ezdxf
    from ezdxf.addons.drawing import RenderContext, Frontend
    from ezdxf.addons.drawing.matplotlib import MatplotlibBackend
    import matplotlib
    matplotlib.use('Agg')  # Backend sem GUI
    import matplotlib.pyplot as plt
    DWG_SUPPORT = True
except ImportError:
    DWG_SUPPORT = False

# --- CONFIGURAÇÃO DA PÁGINA ---
st.set_page_config(
    page_title="JSJ Parser TURBO ⚡",
    page_icon="🚀",
    layout="wide"
)

# --- INICIALIZAÇÃO DO ESTADO (MEMÓRIA TEMPORÁRIA) ---
if 'master_data' not in st.session_state:
    st.session_state.master_data = []
if 'total_tokens' not in st.session_state:
    st.session_state.total_tokens = 0
if 'ordem_customizada' not in st.session_state:
    st.session_state.ordem_customizada = []

# --- BARRA LATERAL (CONFIGURAÇÃO) ---
with st.sidebar:
    st.header("⚙️ Configuração (TURBO)")
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
    st.success("⚡ MODO TURBO ATIVO\nRate Limit: 1000 req/min\nBatch Size: 50")
    
    # CONTADOR DE TOKENS E CUSTO
    if st.session_state.total_tokens > 0:
        st.divider()
        st.subheader("💰 Custo Estimado")
        input_tokens = st.session_state.total_tokens * 0.7
        output_tokens = st.session_state.total_tokens * 0.3
        custo_usd = (input_tokens * 0.075 / 1_000_000) + (output_tokens * 0.30 / 1_000_000)
        custo_eur = custo_usd * 0.95
        
        st.metric("Tokens Usados", f"{st.session_state.total_tokens:,}")
        st.metric("Custo Estimado", f"€{custo_eur:.4f}")
        st.caption(f"≈ ${custo_usd:.4f} USD")

    st.divider()

    if st.button("🗑️ Limpar Toda a Memória", type="primary"):
        st.session_state.master_data = []
        st.session_state.total_tokens = 0
        st.session_state.ordem_customizada = []
        st.rerun()

# --- FUNÇÕES DE PROCESSAMENTO (BACKEND) ---

class RateLimiter:
    """Rate limiter ajustado para MODO TURBO (Paid Tier)."""
    def __init__(self, max_requests=1000, time_window=60): # TURBO: 1000 req/min
        self.max_requests = max_requests
        self.time_window = time_window
        self.requests = deque()

    async def acquire(self):
        now = time.time()
        while self.requests and self.requests[0] < now - self.time_window:
            self.requests.popleft()

        if len(self.requests) >= self.max_requests:
            sleep_time = self.requests[0] + self.time_window - now + 0.1
            await asyncio.sleep(sleep_time)
            return await self.acquire()

        self.requests.append(now)

def get_image_from_page(doc, page_num):
    """Extrai a imagem (crop da legenda) de uma página específica."""
    page = doc.load_page(page_num)

    # CROP OTIMIZADO: Quadrante inferior direito completo (50% x 50%)
    rect = page.rect
    crop_rect = fitz.Rect(
        rect.width * 0.50,   
        rect.height * 0.50,  
        rect.width,
        rect.height
    )

    pix = page.get_pixmap(clip=crop_rect, matrix=fitz.Matrix(2, 2)) 
    img_data = pix.tobytes("png")

    return Image.open(io.BytesIO(img_data))

def get_image_from_dwg_layout(dwg_path, layout_name):
    """Extrai imagem de um layout DWG."""
    if not DWG_SUPPORT:
        raise ImportError("ezdxf não está instalado.")
    
    try:
        doc = ezdxf.readfile(dwg_path)
        if layout_name == 'Model':
            layout = doc.modelspace()
        else:
            layout = doc.paperspace(layout_name)
        
        fig = plt.figure(figsize=(16, 12), dpi=200, facecolor='white')
        ax = fig.add_axes([0, 0, 1, 1])
        ax.set_facecolor('white')
        
        ctx = RenderContext(doc)
        out = MatplotlibBackend(ax)
        Frontend(ctx, out).draw_layout(layout, finalize=True)
        
        ax.autoscale()
        ax.margins(0.05)
        
        buf = io.BytesIO()
        fig.savefig(buf, format='png', bbox_inches='tight', dpi=200, facecolor='white')
        buf.seek(0)
        plt.close(fig)
        
        img = Image.open(buf)
        width, height = img.size
        crop_box = (width // 2, height // 2, width, height)
        cropped = img.crop(crop_box)
        
        if cropped.mode != 'RGB':
            cropped = cropped.convert('RGB')
        
        return cropped
    except Exception as e:
        raise Exception(f"Erro DWG '{layout_name}': {str(e)}")

def get_dwg_layouts(dwg_path):
    """Retorna lista de layouts DWG."""
    if not DWG_SUPPORT: return []
    try:
        doc = ezdxf.readfile(dwg_path)
        layouts = [l.name for l in doc.layouts if l.name != 'Model']
        return sorted(layouts) if layouts else ['Model']
    except:
        return []

def create_pdf_export(df):
    """Cria PDF profissional."""
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=landscape(A4), rightMargin=1.5*cm, leftMargin=1.5*cm, topMargin=2*cm, bottomMargin=2*cm)
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle('CustomTitle', parent=styles['Heading1'], fontSize=18, textColor=colors.HexColor('#1f4788'), spaceAfter=20, alignment=TA_CENTER, fontName='Helvetica-Bold')
    subtitle_style = ParagraphStyle('CustomSubtitle', parent=styles['Heading2'], fontSize=14, textColor=colors.HexColor('#2c5aa0'), spaceAfter=12, spaceBefore=12, fontName='Helvetica-Bold')
    
    elements = []
    elements.append(Paragraph("LISTA DE DESENHOS JSJ", title_style))
    elements.append(Paragraph(f"Gerado em {datetime.now().strftime('%d/%m/%Y às %H:%M')}", styles['Normal']))
    elements.append(Spacer(1, 0.5*cm))
    
    for tipo in df['TIPO'].unique():
        df_tipo = df[df['TIPO'] == tipo]
        elements.append(Paragraph(f"TIPO: {tipo}", subtitle_style))
        elements.append(Spacer(1, 0.3*cm))
        
        table_data = [['Nº Desenho', 'Título', 'Rev', 'Data', 'Ficheiro', 'Obs']]
        for _, row in df_tipo.iterrows():
            table_data.append([
                str(row['Num. Desenho']),
                str(row['Titulo'])[:50] + '...' if len(str(row['Titulo'])) > 50 else str(row['Titulo']),
                str(row['Revisão']),
                str(row['Data']),
                str(row['Ficheiro'])[:30] + '...' if len(str(row['Ficheiro'])) > 30 else str(row['Ficheiro']),
                str(row['Obs'])[:30] + '...' if len(str(row['Obs'])) > 30 else str(row['Obs'])
            ])
        
        table = Table(table_data, colWidths=[3.5*cm, 6*cm, 1.5*cm, 2*cm, 5*cm, 4*cm])
        table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1f4788')),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
            ('ALIGN', (0, 0), (-1, 0), 'CENTER'),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, 0), 10),
            ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f0f4f8')]),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cccccc')),
            ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ]))
        elements.append(table)
        elements.append(Spacer(1, 0.8*cm))
        if tipo != df['TIPO'].unique()[-1]: elements.append(PageBreak())
    
    doc.build(elements)
    buffer.seek(0)
    return buffer

async def ask_gemini_async(image, file_context, rate_limiter):
    """Wrapper Assíncrono."""
    if not api_key: return {"error": "Sem API Key"}
    await rate_limiter.acquire()
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, _ask_gemini_sync, image, file_context)

def _ask_gemini_sync(image, file_context):
    """Chamada Síncrona ao Gemini."""
    genai.configure(api_key=api_key)
    models_to_try = ['gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-1.5-flash-latest', 'gemini-pro']

    prompt = """
    Age como um técnico de documentação. Analisa a LEGENDA VISUAL no canto inferior direito desta imagem.
    
    REGRAS ESTRITAS (FONTE DE VERDADE):
    1. IGNORA NOME DO FICHEIRO. Só olha para a imagem.
    2. Procura "Nº DESENHO" na legenda.
    
    3. TABELA DE REVISÕES (CRUCIAL):
       - Procura tabela acima da legenda.
       - Identifica a LETRA MAIS RECENTE (A < B < C).
       - Extrai a DATA dessa linha específica.
       - Se houver revisões, IGNORA a data base da legenda.
    
    4. Se tabela vazia: Assume Rev 0 e usa data base.

    Retorna JSON:
    {
        "num_desenho": "string",
        "titulo": "string",
        "revisao": "string",
        "data": "string",
        "obs": "string"
    }
    """

    last_error = ""
    for model_name in models_to_try:
        try:
            model = genai.GenerativeModel(model_name)
            response = model.generate_content([prompt, image])
            clean_text = response.text.replace("```json", "").replace("```", "").strip()
            
            total = 500
            if hasattr(response, 'usage_metadata'):
                total = response.usage_metadata.total_token_count
            
            return json.loads(clean_text), total
        except Exception as e:
            last_error = str(e)
            continue

    return {"error": f"Falha IA. Erro: {last_error}", "num_desenho": "ERRO", "titulo": file_context}, 0

# --- INTERFACE PRINCIPAL (FRONTEND) ---

st.title("⚡ Gestor de Desenhos JSJ (TURBO)")
st.markdown("---")

col_input, col_view = st.columns([1, 2])

with col_input:
    st.subheader("1. Novo Lote (High Speed)")
    batch_type = st.text_input("🏷️ Tipo deste lote", placeholder="Ex: BETAO, METALICA...", help="Aplica-se a todos os ficheiros.")
    
    file_types = ["pdf"]
    if DWG_SUPPORT: file_types.extend(["dwg", "dxf"])
    
    uploaded_files = st.file_uploader("📄 Carregar Ficheiros", type=file_types, accept_multiple_files=True)
    process_btn = st.button("⚡ Processar (TURBO MODE)", disabled=(not uploaded_files or not batch_type))

    if process_btn:
        if not api_key:
            st.error("⚠️ Falta a API Key!")
        else:
            progress_bar = st.progress(0)
            status_text = st.empty()
            
            all_tasks = []
            total_operations = 0
            
            # 1. Preparação (Rápida)
            for file in uploaded_files:
                file_ext = file.name.lower().split('.')[-1]
                try:
                    if file_ext == 'pdf':
                        bytes_data = file.read()
                        doc = fitz.open(stream=bytes_data, filetype="pdf")
                        for page_num in range(doc.page_count):
                            display_name = f"{file.name} (Pág. {page_num + 1})"
                            img = get_image_from_page(doc, page_num)
                            all_tasks.append({"image": img, "display_name": display_name, "batch_type": batch_type.upper()})
                            total_operations += 1
                        doc.close()
                    elif file_ext in ['dwg', 'dxf'] and DWG_SUPPORT:
                        with tempfile.NamedTemporaryFile(delete=False, suffix=f'.{file_ext}') as tmp:
                            tmp.write(file.read())
                            tmp_path = tmp.name
                        layouts = get_dwg_layouts(tmp_path)
                        for layout_name in layouts:
                            display_name = f"{file.name} (Layout: {layout_name})"
                            img = get_image_from_dwg_layout(tmp_path, layout_name)
                            all_tasks.append({"image": img, "display_name": display_name, "batch_type": batch_type.upper()})
                            total_operations += 1
                        try: os.unlink(tmp_path)
                        except: pass
                except Exception as e:
                    st.error(f"Erro ao ler {file.name}: {e}")
            
            # 2. Processamento Assíncrono (TURBO)
            async def process_all_pages():
                # TURBO SETTINGS: 1000 req/min
                rate_limiter = RateLimiter(max_requests=1000, time_window=60)
                new_records = []
                
                async_tasks = []
                for task_data in all_tasks:
                    async_tasks.append(ask_gemini_async(task_data["image"], task_data["display_name"], rate_limiter))
                
                # TURBO BATCH: 50 de cada vez
                batch_size = 50
                completed = 0
                
                for i in range(0, len(async_tasks), batch_size):
                    batch = async_tasks[i:i + batch_size]
                    status_text.text(f"🔥 A processar batch {i//batch_size + 1} ({len(batch)} desenhos em paralelo)...")
                    
                    results = await asyncio.gather(*batch, return_exceptions=True)
                    
                    for idx, result in enumerate(results):
                        task_info = all_tasks[i + idx]
                        if isinstance(result, tuple):
                            data, tokens = result
                            st.session_state.total_tokens += tokens
                        else:
                            data, tokens = {"error": str(result)}, 0

                        record = {
                            "TIPO": task_info["batch_type"],
                            "Num. Desenho": data.get("num_desenho", "N/A"),
                            "Titulo": data.get("titulo", "N/A"),
                            "Revisão": data.get("revisao", "-"),
                            "Data": data.get("data", "-"),
                            "Ficheiro": task_info["display_name"],
                            "Obs": data.get("obs", "")
                        }
                        if "error" in data: record["Obs"] = f"Erro: {data['error']}"
                        new_records.append(record)
                        completed += 1
                        progress_bar.progress(completed / total_operations)
                return new_records
            
            try:
                new_records = asyncio.run(process_all_pages())
                st.session_state.master_data.extend(new_records)
                status_text.success(f"✅ Concluído! ({len(new_records)} desenhos)")
                time.sleep(1)
                st.rerun()
            except Exception as e:
                st.error(f"Erro: {e}")

with col_view:
    st.subheader("2. Lista Completa")
    if len(st.session_state.master_data) > 0:
        df = pd.DataFrame(st.session_state.master_data)
        
        st.markdown("### 🔄 Reordenar")
        tipos_unicos = sorted(df['TIPO'].unique().tolist())
        col_pills, col_btn = st.columns([4, 1])
        
        with col_pills:
            cols = st.columns(len(tipos_unicos))
            for idx, tipo in enumerate(tipos_unicos):
                if cols[idx].button(tipo, key=f"t_{tipo}"):
                    if tipo in st.session_state.ordem_customizada: st.session_state.ordem_customizada.remove(tipo)
                    else: st.session_state.ordem_customizada.append(tipo)
                    st.rerun()
            st.caption(f"Ordem: {' → '.join(st.session_state.ordem_customizada) if st.session_state.ordem_customizada else 'Alfabética'}")

        with col_btn:
            if st.button("Reset"):
                st.session_state.ordem_customizada = []
                st.rerun()
        
        if st.session_state.ordem_customizada:
            ordem_completa = st.session_state.ordem_customizada + [t for t in tipos_unicos if t not in st.session_state.ordem_customizada]
            ordem_map = {tipo: idx for idx, tipo in enumerate(ordem_completa)}
            df['_ordem'] = df['TIPO'].map(ordem_map)
            df = df.sort_values(by=['_ordem', 'Num. Desenho']).drop('_ordem', axis=1)
        else:
            df = df.sort_values(by=["TIPO", "Num. Desenho"])
        
        st.dataframe(df, use_container_width=True, hide_index=True)
        
        st.markdown("### 📥 Exportar")
        c1, c2, c3 = st.columns(3)
        
        with c1:
            bx = io.BytesIO()
            with pd.ExcelWriter(bx, engine='xlsxwriter') as w:
                df.to_excel(w, index=False, sheet_name='JSJ')
                w.sheets['JSJ'].set_column(0, 6, 20)
            st.download_button("📊 Excel", data=bx.getvalue(), file_name="lista_jsj.xlsx", mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
            
        with c2:
            st.download_button("📝 Markdown", data=df.to_csv(sep='|', index=False), file_name="lista_jsj.md", mime="text/markdown")
            
        with c3:
            st.download_button("📄 PDF", data=create_pdf_export(df).getvalue(), file_name="lista_jsj.pdf", mime="application/pdf")