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
import logging
import re
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, PageBreak
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from datetime import datetime

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

# --- CONFIGURAÇÃO DE LOGGING ---
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('jsj_parser.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# --- FUNÇÃO DE VALIDAÇÃO DE DADOS ---
def validate_extracted_data(data, filename=""):
    """Valida dados extraídos pela IA para garantir integridade.

    Retorna: (is_valid: bool, errors: list, warnings: list)
    """
    errors = []
    warnings = []

    # 1. Validar número de desenho (obrigatório e não vazio)
    num_desenho = data.get('num_desenho', '').strip()
    if not num_desenho or num_desenho == 'ERRO':
        errors.append("Número de desenho vazio ou inválido")
    elif len(num_desenho) < 3:
        warnings.append(f"Número de desenho muito curto: '{num_desenho}'")

    # 2. Validar data (formato DD/MM/YYYY ou variações comuns)
    data_str = data.get('data', '').strip()
    if data_str:
        # Aceitar formatos: DD/MM/YYYY, DD-MM-YYYY, DD.MM.YYYY
        date_patterns = [
            r'^\d{2}[/\-\.]\d{2}[/\-\.]\d{4}$',  # DD/MM/YYYY
            r'^\d{1}[/\-\.]\d{2}[/\-\.]\d{4}$',  # D/MM/YYYY
            r'^\d{2}[/\-\.]\d{1}[/\-\.]\d{4}$',  # DD/M/YYYY
        ]

        if not any(re.match(pattern, data_str) for pattern in date_patterns):
            # Verificar se não é placeholder comum
            if data_str.lower() in ['n/d', 'n/a', '?', '??/??/????', 'ilegível']:
                warnings.append(f"Data ilegível ou não disponível: '{data_str}'")
            else:
                errors.append(f"Formato de data inválido: '{data_str}' (esperado DD/MM/YYYY)")
        else:
            # Validar valores numéricos
            parts = re.split(r'[/\-\.]', data_str)
            if len(parts) == 3:
                dia, mes, ano = parts
                try:
                    dia_int, mes_int, ano_int = int(dia), int(mes), int(ano)
                    if not (1 <= dia_int <= 31):
                        errors.append(f"Dia inválido: {dia_int}")
                    if not (1 <= mes_int <= 12):
                        errors.append(f"Mês inválido: {mes_int}")
                    if not (2000 <= ano_int <= 2100):
                        warnings.append(f"Ano fora do range esperado: {ano_int}")
                except ValueError:
                    errors.append(f"Data contém valores não numéricos: '{data_str}'")
    else:
        warnings.append("Data vazia")

    # 3. Validar revisão (letra A-Z maiúscula ou '0' para primeira emissão)
    revisao = data.get('revisao', '').strip()
    if revisao:
        if not re.match(r'^[A-Z0]$', revisao):
            # Aceitar também minúsculas e converter
            if re.match(r'^[a-z]$', revisao):
                warnings.append(f"Revisão em minúscula: '{revisao}' (esperado maiúscula)")
            else:
                errors.append(f"Revisão inválida: '{revisao}' (esperado letra A-Z ou '0')")
    else:
        warnings.append("Revisão vazia")

    # 4. Validar título (opcional mas recomendado)
    titulo = data.get('titulo', '').strip()
    if not titulo:
        warnings.append("Título vazio")
    elif len(titulo) < 3:
        warnings.append(f"Título muito curto: '{titulo}'")

    # 5. Verificar se há erro reportado pela própria IA
    if 'error' in data:
        errors.append(f"IA reportou erro: {data['error']}")

    is_valid = len(errors) == 0

    # Log de validação
    if errors:
        logger.error(f"Validação FALHOU para {filename}: {errors}")
    if warnings:
        logger.warning(f"Validação com avisos para {filename}: {warnings}")
    if is_valid and not warnings:
        logger.info(f"Validação OK para {filename}: Rev={revisao}, Data={data_str}")

    return is_valid, errors, warnings

# --- CONFIGURAÇÃO DA PÁGINA ---
st.set_page_config(
    page_title="JSJ Parser v2 (Unified)",
    page_icon="🏗️",
    layout="wide"
)

# --- INICIALIZAÇÃO DO ESTADO (MEMÓRIA TEMPORÁRIA) ---
if 'master_data' not in st.session_state:
    st.session_state.master_data = []
if 'total_tokens' not in st.session_state:
    st.session_state.total_tokens = 0
if 'ordem_customizada' not in st.session_state:
    st.session_state.ordem_customizada = []
if 'crop_validated' not in st.session_state:
    st.session_state.crop_validated = False
if 'pending_tasks' not in st.session_state:
    st.session_state.pending_tasks = None
if 'should_process' not in st.session_state:
    st.session_state.should_process = False

# --- BARRA LATERAL (CONFIGURAÇÃO) ---
with st.sidebar:
    st.header("⚙️ Configuração")
    api_key = st.text_input("Google Gemini API Key", type="password")

    # Modo TURBO (unifica jsj_app.py e jsjturbo.py)
    turbo_mode = st.checkbox(
        "🚀 Modo TURBO (Paid Tier)",
        value=False,
        help="Aumenta rate limit de 15 para 1000 req/min e batch size de 5 para 50. Requer conta Google Cloud paga."
    )

    if turbo_mode:
        st.info("⚡ Modo TURBO ativo: 1000 req/min, batch 50")
    else:
        st.info("🐢 Modo Standard: 15 req/min, batch 5")

    st.divider()

    # Configuração de Crop (Prioridade 3)
    st.subheader("✂️ Área de Crop")
    crop_preset = st.selectbox(
        "Posição da Legenda",
        [
            "Canto Inf. Direito (50%)",
            "Canto Inf. Direito (40%)",
            "Canto Inf. Direito (30%)",
            "Canto Inf. Direito (70%)",
            "Metade Inferior (100% largura)",
            "Página Inteira"
        ],
        index=0,
        help="Define que parte da página será analisada pela IA"
    )

    # Mostrar preview do crop
    show_crop_preview = st.checkbox(
        "👁️ Validar crop antes de processar",
        value=False,
        help="Mostra preview do crop para validação antes de processar (recomendado para primeiro uso)"
    )

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
    
    # CONTADOR DE TOKENS E CUSTO
    if st.session_state.total_tokens > 0:
        st.divider()
        st.subheader("💰 Custo Estimado")
        # Gemini Flash 2.5: $0.075 / 1M tokens input, $0.30 / 1M tokens output
        # Estimativa conservadora: 70% input, 30% output
        input_tokens = st.session_state.total_tokens * 0.7
        output_tokens = st.session_state.total_tokens * 0.3
        custo_usd = (input_tokens * 0.075 / 1_000_000) + (output_tokens * 0.30 / 1_000_000)
        custo_eur = custo_usd * 0.95  # Conversão aproximada USD->EUR
        
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

def get_crop_coordinates(preset, rect):
    """Calcula as coordenadas de crop baseadas no preset selecionado.

    Args:
        preset: String com o preset selecionado
        rect: fitz.Rect da página

    Returns:
        tuple: (x_start_pct, y_start_pct, x_end_pct, y_end_pct) em percentagens
    """
    if preset == "Canto Inf. Direito (50%)":
        return (0.50, 0.50, 1.0, 1.0)  # Quadrante inferior direito (padrão)
    elif preset == "Canto Inf. Direito (40%)":
        return (0.60, 0.60, 1.0, 1.0)  # 40% da área (60% offset)
    elif preset == "Canto Inf. Direito (30%)":
        return (0.70, 0.70, 1.0, 1.0)  # Área menor, mais focada
    elif preset == "Canto Inf. Direito (70%)":
        return (0.30, 0.30, 1.0, 1.0)  # Área maior
    elif preset == "Metade Inferior (100% largura)":
        return (0.0, 0.50, 1.0, 1.0)  # Toda a metade inferior
    elif preset == "Página Inteira":
        return (0.0, 0.0, 1.0, 1.0)  # Página completa
    else:
        return (0.50, 0.50, 1.0, 1.0)  # Padrão

def get_image_from_page(doc, page_num, crop_preset="Canto Inf. Direito (50%)"):
    """Extrai a imagem (crop da legenda) de uma página específica do documento.

    Args:
        doc: Documento PyMuPDF
        page_num: Número da página
        crop_preset: Preset de crop selecionado

    Returns:
        PIL.Image: Imagem extraída
    """
    page = doc.load_page(page_num)
    rect = page.rect

    # Calcular coordenadas do crop
    x_start, y_start, x_end, y_end = get_crop_coordinates(crop_preset, rect)

    crop_rect = fitz.Rect(
        rect.width * x_start,
        rect.height * y_start,
        rect.width * x_end,
        rect.height * y_end
    )

    logger.debug(f"Crop preset '{crop_preset}': ({x_start:.0%}, {y_start:.0%}) -> ({x_end:.0%}, {y_end:.0%})")

    pix = page.get_pixmap(clip=crop_rect, matrix=fitz.Matrix(2, 2)) # 2x zoom para clareza
    img_data = pix.tobytes("png")

    return Image.open(io.BytesIO(img_data))

def get_image_from_dwg_layout(dwg_path, layout_name):
    """Extrai imagem de um layout específico de um ficheiro DWG."""
    if not DWG_SUPPORT:
        raise ImportError("ezdxf não está instalado. Instala com: pip install ezdxf matplotlib")
    
    try:
        # Carregar o DWG/DXF
        doc = ezdxf.readfile(dwg_path)
        
        # Obter o layout
        if layout_name == 'Model':
            msp = doc.modelspace()
            layout = msp
        else:
            layout = doc.paperspace(layout_name)
        
        # Configurar figura com fundo branco
        fig = plt.figure(figsize=(16, 12), dpi=200, facecolor='white')
        ax = fig.add_axes([0, 0, 1, 1])
        ax.set_facecolor('white')
        
        # Configurar contexto de renderização
        ctx = RenderContext(doc)
        out = MatplotlibBackend(ax)
        
        # Renderizar o layout
        Frontend(ctx, out).draw_layout(layout, finalize=True)
        
        # Ajustar limites do gráfico
        ax.autoscale()
        ax.margins(0.05)
        
        # Converter para bytes
        buf = io.BytesIO()
        fig.savefig(buf, format='png', bbox_inches='tight', dpi=200, facecolor='white')
        buf.seek(0)
        plt.close(fig)
        
        # Carregar imagem completa
        img = Image.open(buf)
        width, height = img.size
        
        # CROP: Quadrante inferior direito (50% x 50%)
        crop_box = (
            width // 2,      # left (50% da largura)
            height // 2,     # top (50% da altura)
            width,           # right (100%)
            height           # bottom (100%)
        )
        
        cropped = img.crop(crop_box)
        
        # Garantir que a imagem está em RGB
        if cropped.mode != 'RGB':
            cropped = cropped.convert('RGB')
        
        return cropped
        
    except Exception as e:
        raise Exception(f"Erro ao processar DWG layout '{layout_name}': {str(e)}")

def get_dwg_layouts(dwg_path):
    """Retorna lista de nomes de layouts num ficheiro DWG."""
    if not DWG_SUPPORT:
        return []
    
    try:
        doc = ezdxf.readfile(dwg_path)
        
        # Obter todos os paperspace layouts
        paperspace_layouts = []
        for layout in doc.layouts:
            if layout.name != 'Model':
                paperspace_layouts.append(layout.name)
        
        # Se não houver paperspace layouts, usar Model
        if not paperspace_layouts:
            return ['Model']
        
        return sorted(paperspace_layouts)
        
    except Exception as e:
        # Em caso de erro, retorna lista vazia
        return []

def create_pdf_export(df):
    """Cria PDF profissional com a lista de desenhos."""
    buffer = io.BytesIO()
    
    # Configurar documento em landscape A4
    doc = SimpleDocTemplate(
        buffer,
        pagesize=landscape(A4),
        rightMargin=1.5*cm,
        leftMargin=1.5*cm,
        topMargin=2*cm,
        bottomMargin=2*cm
    )
    
    # Estilos
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=18,
        textColor=colors.HexColor('#1f4788'),
        spaceAfter=20,
        alignment=TA_CENTER,
        fontName='Helvetica-Bold'
    )
    
    subtitle_style = ParagraphStyle(
        'CustomSubtitle',
        parent=styles['Heading2'],
        fontSize=14,
        textColor=colors.HexColor('#2c5aa0'),
        spaceAfter=12,
        spaceBefore=12,
        fontName='Helvetica-Bold'
    )
    
    # Elementos do documento
    elements = []
    
    # Cabeçalho
    elements.append(Paragraph("LISTA DE DESENHOS JSJ", title_style))
    elements.append(Paragraph(f"Gerado em {datetime.now().strftime('%d/%m/%Y às %H:%M')}", styles['Normal']))
    elements.append(Spacer(1, 0.5*cm))
    
    # Processar por tipo
    for tipo in df['TIPO'].unique():
        df_tipo = df[df['TIPO'] == tipo]
        
        # Subtítulo do tipo
        elements.append(Paragraph(f"TIPO: {tipo}", subtitle_style))
        elements.append(Spacer(1, 0.3*cm))
        
        # Preparar dados da tabela
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
        
        # Criar tabela
        table = Table(table_data, colWidths=[3.5*cm, 6*cm, 1.5*cm, 2*cm, 5*cm, 4*cm])
        
        # Estilo da tabela
        table.setStyle(TableStyle([
            # Cabeçalho
            ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1f4788')),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
            ('ALIGN', (0, 0), (-1, 0), 'CENTER'),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, 0), 10),
            ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
            
            # Dados
            ('BACKGROUND', (0, 1), (-1, -1), colors.white),
            ('TEXTCOLOR', (0, 1), (-1, -1), colors.black),
            ('ALIGN', (0, 1), (-1, -1), 'LEFT'),
            ('ALIGN', (2, 1), (3, -1), 'CENTER'),  # Rev e Data centralizadas
            ('FONTNAME', (0, 1), (-1, -1), 'Helvetica'),
            ('FONTSIZE', (0, 1), (-1, -1), 8),
            ('TOPPADDING', (0, 1), (-1, -1), 6),
            ('BOTTOMPADDING', (0, 1), (-1, -1), 6),
            
            # Linhas alternadas
            ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f0f4f8')]),
            
            # Bordas
            ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cccccc')),
            ('BOX', (0, 0), (-1, -1), 1, colors.HexColor('#1f4788')),
            
            # Alinhamento vertical
            ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ]))
        
        elements.append(table)
        elements.append(Spacer(1, 0.8*cm))
        
        # Page break entre tipos (exceto último)
        if tipo != df['TIPO'].unique()[-1]:
            elements.append(PageBreak())
    
    # Rodapé
    elements.append(Spacer(1, 1*cm))
    footer_text = f"Total de desenhos: {len(df)} | Tipos: {', '.join(df['TIPO'].unique())}"
    elements.append(Paragraph(footer_text, styles['Italic']))
    
    # Gerar PDF
    doc.build(elements)
    buffer.seek(0)
    
    return buffer

async def ask_gemini_async(image, file_context, rate_limiter, api_key_param):
    """O Cérebro Assíncrono: Processa requests em paralelo com rate limiting.

    Args:
        image: Imagem PIL para análise
        file_context: Nome do ficheiro (para logging)
        rate_limiter: Instância de RateLimiter
        api_key_param: API key do Google Gemini

    Returns:
        dict: Dados extraídos pela IA
    """
    if not api_key_param:
        logger.error("Tentativa de processar sem API Key")
        return {"error": "Sem API Key", "num_desenho": "ERRO", "titulo": file_context, "revisao": "?", "data": "??/??/????", "obs": "API Key não fornecida"}, 0

    # Aguarda permissão do rate limiter
    await rate_limiter.acquire()

    # Executa a chamada síncrona da API em thread separada
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, _ask_gemini_sync, image, file_context, api_key_param)

def _ask_gemini_sync(image, file_context, api_key_param):
    """Wrapper síncrono para chamada ao Gemini (executado em thread pool).

    Args:
        image: Imagem PIL para análise
        file_context: Nome do ficheiro (para logging)
        api_key_param: API key do Google Gemini

    Returns:
        tuple: (dados_extraidos: dict, tokens_usados: int)
    """
    genai.configure(api_key=api_key_param)

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
    last_model = ""

    # LOOP DE TENTATIVAS (ROBUST FALLBACK)
    for model_name in models_to_try:
        try:
            logger.info(f"Tentando modelo {model_name} para {file_context}")
            model = genai.GenerativeModel(model_name)
            response = model.generate_content([prompt, image])
            last_model = model_name

            # Se chegou aqui, a chamada à API funcionou!
            clean_text = response.text.replace("```json", "").replace("```", "").strip()

            # Contabilizar tokens (estimativa)
            if hasattr(response, 'usage_metadata'):
                total = response.usage_metadata.total_token_count
            else:
                # Estimativa se não houver metadata: ~500 tokens por request
                total = 500

            # *** VALIDAÇÃO ROBUSTA DO JSON ***
            try:
                parsed_data = json.loads(clean_text)
            except json.JSONDecodeError as e:
                logger.error(f"JSON inválido retornado pela IA para {file_context}: {e}")
                logger.debug(f"Resposta bruta: {clean_text[:200]}...")
                return {
                    "error": f"IA retornou JSON malformado: {str(e)}",
                    "num_desenho": "ERRO_JSON",
                    "titulo": file_context,
                    "revisao": "?",
                    "data": "??/??/????",
                    "obs": f"Erro de parsing JSON: {str(e)}"
                }, 0

            # *** VALIDAÇÃO DE INTEGRIDADE DOS DADOS ***
            is_valid, errors, warnings = validate_extracted_data(parsed_data, file_context)

            if not is_valid:
                # Dados inválidos - reportar mas não falhar completamente
                logger.error(f"Dados inválidos extraídos de {file_context}: {errors}")
                parsed_data['obs'] = f"VALIDAÇÃO FALHOU: {'; '.join(errors)}"
                if warnings:
                    parsed_data['obs'] += f" | Avisos: {'; '.join(warnings)}"
            elif warnings:
                # Dados válidos mas com avisos
                if parsed_data.get('obs'):
                    parsed_data['obs'] += f" | {'; '.join(warnings)}"
                else:
                    parsed_data['obs'] = '; '.join(warnings)

            logger.info(f"Sucesso com modelo {model_name} para {file_context} ({total} tokens)")
            return parsed_data, total

        except Exception as e:
            last_error = str(e)
            logger.warning(f"Modelo {model_name} falhou para {file_context}: {last_error}")
            continue

    # Se chegou aqui, todos os modelos falharam
    logger.error(f"TODOS os modelos falharam para {file_context}. Último erro: {last_error}")
    return {
        "error": f"Falha IA. Último erro: {last_error}",
        "num_desenho": "ERRO",
        "titulo": file_context,
        "revisao": "?",
        "data": "??/??/????",
        "obs": f"Todos os modelos falharam. Último modelo: {last_model or 'nenhum'}"
    }, 0

# --- INTERFACE PRINCIPAL (FRONTEND) ---

st.title("🏗️ Gestor de Desenhos JSJ")
st.markdown("---")

col_input, col_view = st.columns([1, 2])

with col_input:
    st.subheader("1. Novo Lote")
    
    # Seletor de tipo com opções predefinidas
    tipo_preset = st.selectbox(
        "🏷️ Tipo de Desenho",
        [
            "Dimensionamento",
            "Betão Armado - Lajes",
            "Betão Armado - Pilares",
            "Betão Armado - Fundações",
            "Betão Armado - Vigas",
            "Betão Armado - Núcleos",
            "Pré-esforço",
            "Custom (personalizado)"
        ],
        index=0,
        help="Seleciona o tipo ou escolhe 'Custom' para inserir manualmente"
    )
    
    # Input manual se "Custom" selecionado
    if tipo_preset == "Custom (personalizado)":
        batch_type = st.text_input(
            "✏️ Tipo Personalizado", 
            placeholder="Ex: METALICA, PORMENOR...",
            help="Insere o tipo personalizado"
        )
    else:
        batch_type = tipo_preset
    
    # Tipos de ficheiro suportados
    file_types = ["pdf"]
    if DWG_SUPPORT:
        file_types.extend(["dwg", "dxf"])
        st.caption("✅ Suporte DWG/DXF ativo")
    else:
        st.caption("⚠️ Instala ezdxf para suportar DWG: `pip install ezdxf matplotlib`")
    
    # Inicializar key do uploader se não existir
    if 'uploader_key' not in st.session_state:
        st.session_state.uploader_key = 0
    
    uploaded_files = st.file_uploader(
        "📄 Carregar Ficheiros", 
        type=file_types, 
        accept_multiple_files=True,
        help="Suporta PDF e DWG/DXF (cada layout = 1 desenho)",
        key=f"file_uploader_{st.session_state.uploader_key}"
    )
    
    # Botão de processar
    process_btn = st.button("⚡ Processar Lote", disabled=(not uploaded_files or not batch_type))

    # LÓGICA DE VALIDAÇÃO DE CROP
    # Se checkbox NÃO marcada → processa diretamente
    # Se checkbox MARCADA → mostra preview e pede validação
    
    if process_btn:
        if not api_key:
            st.error("⚠️ Falta a API Key na barra lateral!")
        elif not show_crop_preview:
            # Processar diretamente sem validação
            st.session_state.crop_validated = True
            st.session_state.should_process = True
            st.rerun()
        elif not st.session_state.crop_validated:
            # Mostrar preview do crop do primeiro desenho para validação
            st.info("### ✂️ Validação de Crop")
            st.caption("Valida a área de crop antes de processar todos os desenhos")
            
            # Extrair primeira página do primeiro ficheiro para preview
            first_file = uploaded_files[0]
            file_ext = first_file.name.lower().split('.')[-1]
            
            try:
                if file_ext == 'pdf':
                    bytes_data = first_file.read()
                    doc = fitz.open(stream=bytes_data, filetype="pdf")
                    preview_img = get_image_from_page(doc, 0, crop_preset)
                    doc.close()
                    
                    st.image(preview_img, caption=f"Preview: {first_file.name} (Página 1) - Crop: {crop_preset}", use_container_width=True)
                    st.caption("⬆️ Esta é a área que a IA vai analisar em TODOS os desenhos")
                    
                    col_val, col_alt = st.columns(2)
                    with col_val:
                        if st.button("✅ Validar e Processar", type="primary", use_container_width=True, key="btn_validar"):
                            st.session_state.crop_validated = True
                            st.session_state.should_process = True
                            st.rerun()
                    with col_alt:
                        if st.button("🔄 Alterar Crop", use_container_width=True, key="btn_alterar"):
                            st.info("👈 Ajusta a configuração de crop na barra lateral e tenta novamente")
                            
                elif file_ext in ['dwg', 'dxf'] and DWG_SUPPORT:
                    st.warning("⚠️ Preview de crop para DWG ainda não implementado. A processar diretamente...")
                    st.session_state.crop_validated = True
                    st.session_state.should_process = True
                    st.rerun()
                else:
                    st.error(f"Tipo de ficheiro não suportado: {file_ext}")
                    
            except Exception as e:
                st.error(f"Erro ao gerar preview: {e}")
                if st.button("Continuar mesmo assim", key="btn_continuar"):
                    st.session_state.crop_validated = True
                    st.session_state.should_process = True
                    st.rerun()

    # PROCESSAMENTO PRINCIPAL (após validação ou direto)
    if st.session_state.should_process and uploaded_files:
        if not api_key:
            st.error("⚠️ Falta a API Key na barra lateral!")
        else:
            progress_bar = st.progress(0)
            status_text = st.empty()
            
            # Pré-processamento: Extrair todas as páginas/layouts
            all_tasks = []
            total_operations = 0
            
            for file in uploaded_files:
                file_ext = file.name.lower().split('.')[-1]
                
                try:
                    if file_ext == 'pdf':
                        # Processar PDF
                        bytes_data = file.read()
                        doc = fitz.open(stream=bytes_data, filetype="pdf")

                        # Preview do crop (se ativado e primeira página do primeiro ficheiro)
                        if show_crop_preview and len(all_tasks) == 0 and doc.page_count > 0:
                            preview_img = get_image_from_page(doc, 0, crop_preset)
                            st.info(f"👁️ Preview da área de crop: {crop_preset}")
                            st.image(preview_img, caption=f"Preview: {file.name} (Página 1)", width=400)
                            st.caption("Esta é a área que a IA vai analisar em todas as páginas.")

                        for page_num in range(doc.page_count):
                            display_name = f"{file.name} (Pág. {page_num + 1})"
                            img = get_image_from_page(doc, page_num, crop_preset)

                            all_tasks.append({
                                "image": img,
                                "display_name": display_name,
                                "batch_type": batch_type.upper()
                            })
                            total_operations += 1

                        doc.close()
                        
                    elif file_ext in ['dwg', 'dxf'] and DWG_SUPPORT:
                        # Processar DWG/DXF
                        status_text.text(f"A processar {file.name}...")
                        
                        # Guardar temporariamente (ezdxf precisa de ficheiro no disco)
                        with tempfile.NamedTemporaryFile(delete=False, suffix=f'.{file_ext}') as tmp:
                            tmp.write(file.read())
                            tmp_path = tmp.name
                        
                        try:
                            # Obter layouts
                            layouts = get_dwg_layouts(tmp_path)
                            
                            if not layouts:
                                st.warning(f"⚠️ Nenhum layout encontrado em {file.name}")
                                continue
                            
                            status_text.text(f"Encontrados {len(layouts)} layouts em {file.name}")
                            
                            for layout_idx, layout_name in enumerate(layouts):
                                try:
                                    display_name = f"{file.name} (Layout: {layout_name})"
                                    status_text.text(f"A renderizar {display_name}...")
                                    
                                    img = get_image_from_dwg_layout(tmp_path, layout_name)
                                    
                                    all_tasks.append({
                                        "image": img,
                                        "display_name": display_name,
                                        "batch_type": batch_type.upper()
                                    })
                                    total_operations += 1
                                    
                                except Exception as layout_error:
                                    st.warning(f"⚠️ Erro no layout '{layout_name}' de {file.name}: {str(layout_error)}")
                                    continue
                                    
                        except Exception as dwg_error:
                            st.error(f"❌ Erro ao processar {file.name}: {str(dwg_error)}")
                        finally:
                            # Limpar ficheiro temporário
                            try:
                                if os.path.exists(tmp_path):
                                    os.unlink(tmp_path)
                            except (FileNotFoundError, PermissionError, OSError) as e:
                                logger.warning(f"Não foi possível eliminar ficheiro temporário {tmp_path}: {e}")
                                pass
                    
                except Exception as e:
                    st.error(f"Erro ao ler {file.name}: {e}")
            
            # Processamento Assíncrono em Paralelo
            async def process_all_pages():
                """Processa todas as páginas em paralelo com rate limiting."""
                # Configurar rate limiter e batch size baseado no modo
                if turbo_mode:
                    rate_limiter = RateLimiter(max_requests=1000, time_window=60)
                    batch_size = 50
                    logger.info("Modo TURBO ativo: 1000 req/min, batch 50")
                else:
                    rate_limiter = RateLimiter(max_requests=15, time_window=60)
                    batch_size = 5
                    logger.info("Modo Standard ativo: 15 req/min, batch 5")

                new_records = []

                # Criar tasks assíncronas para todas as páginas
                async_tasks = []
                for task_data in all_tasks:
                    async_tasks.append(
                        ask_gemini_async(
                            task_data["image"],
                            task_data["display_name"],
                            rate_limiter,
                            api_key
                        )
                    )
                completed = 0
                
                for i in range(0, len(async_tasks), batch_size):
                    batch = async_tasks[i:i + batch_size]
                    batch_names = [all_tasks[j]["display_name"] for j in range(i, min(i + batch_size, len(all_tasks)))]
                    
                    status_text.text(f"A processar batch {i//batch_size + 1} ({len(batch)} páginas)...")
                    
                    # Executar batch em paralelo
                    results = await asyncio.gather(*batch, return_exceptions=True)
                    
                    # Processar resultados
                    for idx, result in enumerate(results):
                        task_idx = i + idx
                        task_info = all_tasks[task_idx]
                        
                        # Desempacotar resultado (data, tokens)
                        if isinstance(result, Exception):
                            data = {"error": str(result), "num_desenho": "ERRO", "titulo": task_info["display_name"]}
                            tokens = 0
                        elif isinstance(result, tuple):
                            data, tokens = result
                            st.session_state.total_tokens += tokens
                        else:
                            data = result
                            tokens = 0
                        
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
                
                # Resetar estados para próximo lote
                st.session_state.crop_validated = False
                st.session_state.should_process = False
                
                # Limpar ficheiros carregados (força reset do uploader)
                st.session_state['uploader_key'] = st.session_state.get('uploader_key', 0) + 1
                
                time.sleep(1)
                st.rerun()
            except Exception as e:
                st.error(f"Erro no processamento: {e}")
                st.session_state.crop_validated = False
                st.session_state.should_process = False

with col_view:
    st.subheader("2. Lista Completa")
    if len(st.session_state.master_data) > 0:
        df = pd.DataFrame(st.session_state.master_data)
        
        # PAINEL DE REORDENAÇÃO POR TIPO
        st.markdown("### 🔄 Reordenar por Tipo")
        
        tipos_unicos = sorted(df['TIPO'].unique().tolist())
        
        st.caption("Clica nos tipos pela ordem desejada (1º, 2º, 3º...)")
        col_pills, col_btn = st.columns([4, 1])
        
        with col_pills:
            # Interface para definir ordem
            st.write("**Ordem atual:**", " → ".join(st.session_state.ordem_customizada) if st.session_state.ordem_customizada else "Alfabética")
            
            cols = st.columns(len(tipos_unicos))
            for idx, tipo in enumerate(tipos_unicos):
                with cols[idx]:
                    if st.button(tipo, key=f"tipo_{tipo}", use_container_width=True):
                        if tipo in st.session_state.ordem_customizada:
                            st.session_state.ordem_customizada.remove(tipo)
                        else:
                            st.session_state.ordem_customizada.append(tipo)
                        st.rerun()
        
        with col_btn:
            if st.button("🔄 Reset", help="Voltar à ordem alfabética"):
                st.session_state.ordem_customizada = []
                st.rerun()
        
        # Aplicar ordenação
        if st.session_state.ordem_customizada:
            # Usar ordem customizada
            ordem_completa = st.session_state.ordem_customizada + [t for t in tipos_unicos if t not in st.session_state.ordem_customizada]
            ordem_map = {tipo: idx for idx, tipo in enumerate(ordem_completa)}
            df['_ordem'] = df['TIPO'].map(ordem_map)
            df = df.sort_values(by=['_ordem', 'Num. Desenho'])
            df = df.drop('_ordem', axis=1)
        else:
            # Ordem alfabética padrão
            if "Num. Desenho" in df.columns and "TIPO" in df.columns:
                df = df.sort_values(by=["TIPO", "Num. Desenho"])
        
        st.divider()
        
        st.dataframe(
            df, 
            use_container_width=True,
            column_config={"Ficheiro": st.column_config.TextColumn("Origem"), "Obs": st.column_config.TextColumn("Obs", width="small")},
            hide_index=True
        )
        
        # BOTÕES DE EXPORTAÇÃO
        st.markdown("### 📥 Exportar")
        col_exp1, col_exp2, col_exp3 = st.columns(3)
        
        with col_exp1:
            # Exportar XLSX
            buffer_xlsx = io.BytesIO()
            with pd.ExcelWriter(buffer_xlsx, engine='xlsxwriter') as writer:
                df.to_excel(writer, index=False, sheet_name='Lista Mestra JSJ')
                worksheet = writer.sheets['Lista Mestra JSJ']
                worksheet.set_column(0, 0, 15)  # TIPO
                worksheet.set_column(1, 1, 20)  # Num. Desenho
                worksheet.set_column(2, 2, 40)  # Titulo
                worksheet.set_column(3, 3, 10)  # Revisão
                worksheet.set_column(4, 4, 12)  # Data
                worksheet.set_column(5, 5, 30)  # Ficheiro
                worksheet.set_column(6, 6, 25)  # Obs
            
            st.download_button(
                "📊 Descarregar XLSX",
                data=buffer_xlsx.getvalue(),
                file_name="lista_desenhos_jsj.xlsx",
                mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            )
        
        with col_exp2:
            # Exportar Markdown
            md_content = "# Lista de Desenhos JSJ\n\n"
            
            # Agrupar por TIPO
            for tipo in df['TIPO'].unique():
                df_tipo = df[df['TIPO'] == tipo]
                md_content += f"## {tipo}\n\n"
                md_content += "| Num. Desenho | Título | Rev | Data | Ficheiro | Obs |\n"
                md_content += "|--------------|--------|-----|------|----------|-----|\n"
                
                for _, row in df_tipo.iterrows():
                    md_content += f"| {row['Num. Desenho']} | {row['Titulo']} | {row['Revisão']} | {row['Data']} | {row['Ficheiro']} | {row['Obs']} |\n"
                
                md_content += "\n"
            
            st.download_button(
                "📝 Descarregar MD",
                data=md_content,
                file_name="lista_desenhos_jsj.md",
                mime="text/markdown"
            )
        
        with col_exp3:
            # Exportar PDF
            pdf_buffer = create_pdf_export(df)
            
            st.download_button(
                "📄 Descarregar PDF",
                data=pdf_buffer.getvalue(),
                file_name="lista_desenhos_jsj.pdf",
                mime="application/pdf"
            )
    else:
        st.info("Define um 'Tipo' e carrega ficheiros.")