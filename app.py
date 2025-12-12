import streamlit as st
import pyaudio
import wave
import google.generativeai as genai
import pandas as pd
import os
import json
import threading
import time
from streamlit.runtime.scriptrunner import add_script_run_ctx
from unidecode import unidecode

# --- Configuração da Página ---
st.set_page_config(page_title="Assistente Médico - Gemini", page_icon="🩺", layout="wide")

# --- CSS Personalizado ---
st.markdown("""
<style>
    .big-button {
        font-size: 20px !important;
        padding: 15px 30px !important;
        border-radius: 10px !important;
    }
    .stButton>button {
        width: 100%;
        border-radius: 8px;
        font-weight: bold;
    }
    .success-box {
        padding: 15px;
        background-color: #d4edda;
        color: #155724;
        border-radius: 5px;
        border: 1px solid #c3e6cb;
    }
    .warning-box {
        padding: 15px;
        background-color: #fff3cd;
        color: #856404;
        border-radius: 5px;
        border: 1px solid #ffeeba;
    }
    
    /* SOAP Colors */
    .soap-box {
        padding: 15px;
        border-radius: 8px;
        margin-bottom: 10px;
        color: #000;
        font-weight: 500;
    }
    .soap-s { background-color: #C6F623; }
    .soap-o { background-color: #A1D4F9; }
    .soap-a { background-color: #FCE656; }
    .soap-p { background-color: #A7D6C7; }
    
    .soap-title {
        font-weight: 900;
        font-size: 1.2em;
        margin-right: 10px;
    }

    /* Med Badges */
    .med-container {
        background-color: #f8f9fa;
        padding: 10px;
        border-radius: 8px;
        margin-bottom: 8px;
        border: 1px solid #e9ecef;
        color: #333333; /* Força texto escuro para contraste com fundo claro */
    }
    .med-name {
        font-weight: bold;
        font-size: 1.1em;
        display: block;
        margin-bottom: 5px;
    }
    .badge {
        display: inline-block;
        padding: 4px 8px;
        font-size: 0.8em;
        border-radius: 4px;
        margin-right: 5px;
        color: white;
        font-weight: bold;
    }
    .badge-success { background-color: #28a745; }
    .badge-secondary { background-color: #6c757d; opacity: 0.6; }
</style>
""", unsafe_allow_html=True)

# --- Configurações Iniciais ---
if 'api_key' not in st.session_state:
    st.session_state.api_key = ''
if 'recording' not in st.session_state:
    st.session_state.recording = False
if 'processing' not in st.session_state:
    st.session_state.processing = False
if 'audio_frames' not in st.session_state:
    st.session_state.audio_frames = []
if 'analysis_result' not in st.session_state:
    st.session_state.analysis_result = None

CHUNK = 1024
FORMAT = pyaudio.paInt16
CHANNELS = 1
RATE = 44100
OUTPUT_FILENAME = "consulta_temp.wav"

# --- Funções Auxiliares ---

def load_remume_names():
    try:
        path = os.path.join("data", "db_remume.json")
        if not os.path.exists(path): return []
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            names = []
            if isinstance(data, list):
                for item in data:
                    if isinstance(item, dict):
                        names.append(item.get('nome_completo', item.get('nome', '')))
                    elif isinstance(item, str):
                        names.append(item)
            elif isinstance(data, dict):
                names.append(data.get('nome_completo', ''))
            return [n for n in names if n]
    except Exception as e:
        st.error(f"Erro ao ler db_remume.json: {e}")
        return []

def load_alto_custo_names():
    try:
        path = os.path.join("data", "db_alto_custo.json")
        if not os.path.exists(path): return []
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            names = []
            if isinstance(data, list):
                for item in data:
                    if isinstance(item, dict):
                        names.append(item.get('nome', ''))
                    elif isinstance(item, str):
                        names.append(item)
            elif isinstance(data, dict):
                names.append(data.get('nome', ''))
            return [n for n in names if n]
    except Exception as e:
        st.error(f"Erro ao ler db_alto_custo.json: {e}")
        return []

def load_rename_names():
    try:
        path = os.path.join("data", "db_rename.json")
        if not os.path.exists(path): return []
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            names = []
            if isinstance(data, list):
                for item in data:
                    if isinstance(item, str): # Suporte a lista simples
                        names.append(item)
                    elif isinstance(item, dict):
                        # Tenta estrutura complexa (Group -> itens)
                        if 'itens' in item and isinstance(item['itens'], list):
                            for sub in item['itens']:
                                if isinstance(sub, dict):
                                    names.append(sub.get('nome', ''))
                                elif isinstance(sub, str):
                                    names.append(sub)
                        # Tenta estrutura direta
                        elif 'nome' in item:
                            names.append(item['nome'])
            return [n for n in names if n]
    except Exception as e:
        st.error(f"Erro ao ler db_rename.json: {e}")
        return []

def check_medication_availability(medication_list, remume_names, alto_custo_names, rename_names):
    checked_meds = []
    
    # Função auxiliar de normalização
    def normalize(text):
        return unidecode(str(text)).lower().strip()

    # Prepara tuplas (normalizado, original) para poder retornar o original
    remume_db = [(normalize(m), m) for m in remume_names if m]
    alto_custo_db = [(normalize(m), m) for m in alto_custo_names if m]
    rename_db = [(normalize(m), m) for m in rename_names if m]
    
    for med in medication_list:
        med_clean = med.strip()
        med_norm = normalize(med_clean)
        
        status = {
            "name": med_clean,
            "remume": {"found": False, "match": None},
            "alto_custo": {"found": False, "match": None},
            "rename": {"found": False, "match": None}
        }
        
        # Helper de busca
        def find_match(term_norm, db_list):
            # Procura item do banco (db_norm) dentro do termo (term_norm) OU termo dentro do item do banco
            # Retorna o Original
            for db_norm, db_original in db_list:
                # IGNORA entradas muito curtas (ex: "a", "b", "ou") para evitar falso positivo
                if len(db_norm) < 3:
                    continue
                    
                if term_norm in db_norm or db_norm in term_norm:
                    return db_original
            return None

        # Check Municipal (REMUME)
        match_remume = find_match(med_norm, remume_db)
        if match_remume:
            status["remume"] = {"found": True, "match": match_remume}
            
        # Check Estadual (Alto Custo)
        match_estadual = find_match(med_norm, alto_custo_db)
        if match_estadual:
            status["alto_custo"] = {"found": True, "match": match_estadual}
            
        # Check Nacional (RENAME)
        match_rename = find_match(med_norm, rename_db)
        if match_rename:
            status["rename"] = {"found": True, "match": match_rename}
            
        checked_meds.append(status)
    
    return checked_meds

def record_audio():
    p = pyaudio.PyAudio()
    stream = p.open(format=FORMAT,
                    channels=CHANNELS,
                    rate=RATE,
                    input=True,
                    frames_per_buffer=CHUNK)

    st.session_state.audio_frames = []
    
    while st.session_state.recording:
        data = stream.read(CHUNK)
        st.session_state.audio_frames.append(data)
    
    stream.stop_stream()
    stream.close()
    p.terminate()

    waveFile = wave.open(OUTPUT_FILENAME, 'wb')
    waveFile.setnchannels(CHANNELS)
    waveFile.setsampwidth(p.get_sample_size(FORMAT))
    waveFile.setframerate(RATE)
    waveFile.writeframes(b''.join(st.session_state.audio_frames))
    waveFile.close()

def process_with_gemini(api_key):
    try:
        genai.configure(api_key=api_key)
        
        # Upload do arquivo
        audio_file = genai.upload_file(path=OUTPUT_FILENAME)
        
        # Aguarda processamento se necessário (embora upload seja rápido para arquivos pequenos)
        while audio_file.state.name == "PROCESSING":
            time.sleep(1)
            audio_file = genai.get_file(audio_file.name)

        model = genai.GenerativeModel('gemini-2.5-flash')
        
        prompt = """
        Você é um assistente médico experiente e preciso. Ouça o áudio desta consulta médica com atenção.
        
        1. Identifique a "Principal Hipótese Diagnóstica" (Doença/Condição).
        2. Considere os Protocolos Clínicos e Diretrizes Terapêuticas (PCDT) vigentes.
        3. Elabore um resumo SOAP estruturado (Subjetivo, Objetivo, Avaliação, Plano).
        4. Sugira medicamentos alinhados com o PCDT e as melhores práticas. PREFIRA SEMPRE NOMES GENÉRICOS SIMPLES (ex: "Dipirona" em vez de "Dipirona Sódica").
        
        Sua tarefa é extrair as informações e retornar APENAS um objeto JSON válido com a seguinte estrutura:
        {
            "soap": {
                "s": "Texto do Subjetivo.",
                "o": "Texto do Objetivo.",
                "a": "Texto da Avaliação.",
                "p": "Texto do Plano."
            },
            "principal_hipotese_diagnostica": "Texto com o diagnóstico principal.",
            "medicamentos_sugeridos": ["Lista de strings", "Use nomes genéricos", "Evite nomes comerciais"]
        }
        
        Seja preciso. Retorne apenas JSON.
        """
        
        response = model.generate_content([prompt, audio_file])
        
        # Tenta extrair o JSON
        try:
            # Remove blocos de código se houver (```json ... ```)
            text_res = response.text.strip()
            if text_res.startswith("```"):
                text_res = text_res.split("```")[1]
                if text_res.startswith("json"):
                    text_res = text_res[4:]
            
            data = json.loads(text_res)
            return data
        except Exception as e:
            st.error(f"Erro ao fazer parse do JSON do Gemini: {e}")
            st.text(response.text)
            return None

    except Exception as e:
        st.error(f"Erro na API do Gemini: {e}")
        return None

# --- Interface Gráfica ---

st.title("🩺 Assistente Médico AI Record")

with st.sidebar:
    st.header("Configurações")
    api_key_input = st.text_input("Google API Key", type="password", value=st.session_state.api_key)
    if api_key_input:
        st.session_state.api_key = api_key_input
        
    st.markdown("---")
    st.markdown("**Status dos Bancos de Dados:**")
    
    # Carrega dados específicos
    remume_names = load_remume_names()
    alto_custo_names = load_alto_custo_names()
    rename_names = load_rename_names()
    
    st.success(f"REMUME: {len(remume_names)} itens")
    st.info(f"Alto Custo: {len(alto_custo_names)} itens")
    st.warning(f"RENAME: {len(rename_names)} itens")

col1, col2 = st.columns(2)

with col1:
    # Lógica de Gravação
    # Como o Streamlit é stateless, usaremos botões que alteram flags na session_state
    
    # Botão Iniciar
    if not st.session_state.recording and not st.session_state.processing:
        if st.button("🎤 Gravar Consulta", use_container_width=True, type="primary"):
            st.session_state.recording = True
            st.session_state.analysis_result = None # Limpa resultado anterior
            
            # Inicia thread de gravação
            rec_thread = threading.Thread(target=record_audio)
            add_script_run_ctx(rec_thread)
            rec_thread.start()
            st.rerun()

    # Botão Parar
    if st.session_state.recording:
        st.warning("⚠️ Gravando... Pressione Parar para finalizar.")
        if st.button("⏹️ Parar Gravação", use_container_width=True, type="secondary"):
            st.session_state.recording = False
            st.session_state.processing = True
            st.rerun()

    # Processamento
    if st.session_state.processing:
        with st.spinner("Processando áudio com Gemini AI..."):
            if not st.session_state.api_key:
                st.error("Por favor, insira sua API Key na barra lateral.")
                st.session_state.processing = False
            else:
                # Aguarda um momento para garantir que a thread de gravação fechou o arquivo
                time.sleep(0.5) 
                
                result = process_with_gemini(st.session_state.api_key)
                if result:
                    st.session_state.analysis_result = result
                
                st.session_state.processing = False
                st.rerun()

# --- Exibição dos Resultados ---
if st.session_state.analysis_result:
    result = st.session_state.analysis_result
    
    st.markdown("---")
    
    # Evolução
    st.subheader("📋 Evolução (SOAP)")
    
    soap_data = result.get("soap", {})
    # Fallback se o modelo retornar o formato antigo ou string
    if isinstance(soap_data, str):
        st.info("Formato simples retornado pelo modelo:")
        st.text_area("SOAP", soap_data, height=200)
    elif isinstance(soap_data, dict):
        s_text = soap_data.get("s", "N/A")
        o_text = soap_data.get("o", "N/A")
        a_text = soap_data.get("a", "N/A")
        p_text = soap_data.get("p", "N/A")
        
        st.markdown(f"""
        <div class="soap-box soap-s"><span class="soap-title">S</span> {s_text}</div>
        <div class="soap-box soap-o"><span class="soap-title">O</span> {o_text}</div>
        <div class="soap-box soap-a"><span class="soap-title">A</span> {a_text}</div>
        <div class="soap-box soap-p"><span class="soap-title">P</span> {p_text}</div>
        """, unsafe_allow_html=True)
        
        # Copiar texto completo
        full_text = f"S: {s_text}\nO: {o_text}\nA: {a_text}\nP: {p_text}"
        with st.expander("Copiar Texto Completo"):
            st.text_area("Para Prontuário", value=full_text, height=150)
    else:
        st.text_area("Copiar para Prontuário", value=result.get("resumo_soap", ""), height=200)
    
    # Diagnóstico e Receita
    c_diag, c_rec = st.columns(2)
    
    with c_diag:
        st.subheader("🔍 Hipótese Diagnóstica")
        st.info(result.get("principal_hipotese_diagnostica", result.get("sugestao_diagnostica", "Não especificado")))

    with c_rec:
        st.subheader("💊 Medicamentos e Disponibilidade")
        meds = result.get("medicamentos_sugeridos", [])
        
        if meds:
            checked_meds_status = check_medication_availability(meds, remume_names, alto_custo_names, rename_names)
            
            st.markdown("### Receita Sugerida")
            
            for item in checked_meds_status:
                name = item['name']
                is_remume = item['remume']['found']
                is_alto_custo = item['alto_custo']['found']
                is_rename = item['rename']['found']
                
                # Badges HTML
                badge_remume = '<span class="badge badge-success">REMUME</span>' if is_remume else '<span class="badge badge-secondary">REMUME</span>'
                badge_rename = '<span class="badge badge-success">RENAME</span>' if is_rename else '<span class="badge badge-secondary">RENAME</span>'
                badge_estadual = '<span class="badge badge-success">ESTADUAL</span>' if is_alto_custo else '<span class="badge badge-secondary">ESTADUAL</span>'
                
                st.markdown(f"""
                <div class="med-container">
                    <span class="med-name">{name}</span>
                    <div>
                        {badge_remume}
                        {badge_rename}
                        {badge_estadual}
                    </div>
                </div>
                """, unsafe_allow_html=True)
            
            st.markdown("---")
            st.caption("Verde = Disponível | Cinza = Indisponível/Não encontrado")

            # --- ABA DE AUDITORIA ---
            with st.expander("🕵️ Auditoria de Medicamentos (Debug de Match)"):
                st.write("Aqui você pode ver EXATAMENTE qual item do banco de dados foi encontrado para cada sugestão da IA.")
                
                audit_data = []
                for item in checked_meds_status:
                    med_ia = item['name']
                    
                    # REMUME Match
                    if item['remume']['found']:
                        audit_data.append({"Origem": "IA", "Medicamento": med_ia, "Banco": "REMUME", "Match no Banco": item['remume']['match']})
                    else:
                         audit_data.append({"Origem": "IA", "Medicamento": med_ia, "Banco": "REMUME", "Match no Banco": "❌ Não encontrado"})

                    # RENAME Match
                    if item['rename']['found']:
                         audit_data.append({"Origem": "IA", "Medicamento": med_ia, "Banco": "RENAME", "Match no Banco": item['rename']['match']})
                    # Alto Custo do not populate if empty to save space or populate? Let's populate for clarity
                    if item['alto_custo']['found']:
                         audit_data.append({"Origem": "IA", "Medicamento": med_ia, "Banco": "Alto Custo", "Match no Banco": item['alto_custo']['match']})
                
                if audit_data:
                    st.dataframe(pd.DataFrame(audit_data))
                else:
                    st.info("Nenhum dado de auditoria disponível.")
            
        else:
            st.write("Nenhum medicamento identificado.")

# --- Debug Section ---
with st.expander("🛠️ Debug Information"):
    st.write("### Session State")
    st.json(st.session_state)
    
    if st.session_state.analysis_result:
        st.write("### Raw Gemini Response")
        st.json(st.session_state.analysis_result)
