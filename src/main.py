import flet as ft
import os
import json
import threading
import time
import requests
from unidecode import unidecode
# Note: google.generativeai might need to be installed or used via REST API if the library has issues on Android.
# Ideally we use the library if it builds, or requests if we want to be "pure python" safe.
# Given build.yml installs it, we'll try to import it.
# import google.generativeai as genai # REMOVIDO: Usando REST API para evitar bloatware


# --- CONFIGURAÇÃO DE AMBIENTE ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# --- FUNÇÕES AUXILIARES (ASSETS) ---
def asset(path):
    # Garante caminho absoluto para assets
    # No Android, assets ficam em mobile/assets que são copiados para junto do main.py ou acessíveis via path relativo se estruturado
    # Com a flag --project src, o main.py está na raiz do APK (ou src), e assets também.
    # Vamos assumir que 'assets' está no mesmo nível que este script (src/assets) ou um nível acima?
    # Se 'assets' está na raiz do projeto e usamos --project src, o build copia assets para dentro?
    # O build COPY assets para mobile/assets.
    # O Flet carrega assets da raiz do bundle.
    # Para arquivos de LEITURA (json), precisamos do caminho físico.
    
    # Tentativa 1: Mesmo diretório (se o build copiar para junto)
    path_same_dir = os.path.join(BASE_DIR, "assets", path)
    if os.path.exists(path_same_dir):
        return path_same_dir
        
    # Tentativa 2: Um nível acima (se src for subdir)
    path_parent = os.path.join(os.path.dirname(BASE_DIR), "assets", path)
    if os.path.exists(path_parent):
        return path_parent
        
    return os.path.join(BASE_DIR, "assets", path) # Fallback

# --- LÓGICA DE NEGÓCIO (PORTADA DO APP.PY) ---

def load_json_db(filename):
    try:
        fpath = asset(filename)
        if not os.path.exists(fpath):
            print(f"DEBUG: Arquivo não encontrado: {fpath}")
            return []
        with open(fpath, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        print(f"Erro ao ler {filename}: {e}")
        return []

# Carregadores específicos
def get_remume():
    data = load_json_db("db_remume.json")
    names = []
    # Lógica simplificada de extração
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                names.append(item.get('nome_completo', item.get('nome', '')))
            elif isinstance(item, str):
                names.append(item)
    return [n for n in names if n]

def get_alto_custo():
    data = load_json_db("db_alto_custo.json")
    names = []
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                names.append(item.get('nome', ''))
            elif isinstance(item, str):
                names.append(item)
    return [n for n in names if n]

def get_rename():
    data = load_json_db("db_rename.json")
    names = []
    if isinstance(data, list):
        for item in data:
            if isinstance(item, str): names.append(item)
            elif isinstance(item, dict):
                if 'nome' in item: names.append(item['nome'])
    return [n for n in names if n]

# Verificador de Medicamentos
def check_meds(med_list):
    remume = get_remume()
    alto_custo = get_alto_custo()
    rename = get_rename()
    
    # Prepara DBs normalizados
    def norm(txt): return unidecode(str(txt)).lower().strip()
    
    db_remume = [(norm(m), m) for m in remume]
    db_alto_custo = [(norm(m), m) for m in alto_custo]
    db_rename = [(norm(m), m) for m in rename]
    
    results = []
    for med in med_list:
        med_n = norm(med)
        res = {"name": med, "remume": False, "alto_custo": False, "rename": False}
        
        # Busca simples (substring)
        for d_n, _ in db_remume:
            if len(d_n) > 3 and (med_n in d_n or d_n in med_n):
                res["remume"] = True; break
        for d_n, _ in db_alto_custo:
            if len(d_n) > 3 and (med_n in d_n or d_n in med_n):
                res["alto_custo"] = True; break
        for d_n, _ in db_rename:
            if len(d_n) > 3 and (med_n in d_n or d_n in med_n):
                res["rename"] = True; break
        
        results.append(res)
    return results

# Processamento Gemini
# Processamento Gemini via REST (Sem SDK pesado)
def run_gemini_analysis(api_key, audio_path):
    if not api_key: return {"error": "API Key não configurada"}
    
    try:
        # Prepara a URL (Usando Flash que é rápido e multimodal)
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={api_key}"
        
        # Lê e codifica o áudio para Base64
        import base64
        import mimetypes
        
        if not os.path.exists(audio_path):
            return {"error": "Arquivo de áudio não encontrado"}
            
        mime_type, _ = mimetypes.guess_type(audio_path)
        if not mime_type: mime_type = "audio/wav" # Fallback
        
        with open(audio_path, "rb") as f:
            audio_data = base64.b64encode(f.read()).decode("utf-8")
            
        # Payload JSON
        payload = {
            "contents": [{
                "parts": [
                    {
                        "text": """
                        Atue como médico especialista. Analise o áudio da consulta com extrema atenção aos detalhes clínicos.
                        Retorne APENAS um JSON válido (sem markdown) com a seguinte estrutura:
                        {
                            "soap": {
                                "s": "Subjetivo detalhado",
                                "o": "Objetivo detalhado",
                                "a": "Avaliação clínica",
                                "p": "Plano terapêutico"
                            },
                            "diagnostico": "Hipótese diagnóstica principal",
                            "medicamentos": ["Nome Genérico 1", "Nome Genérico 2"]
                        }
                        """
                    },
                    {
                        "inline_data": {
                            "mime_type": mime_type,
                            "data": audio_data
                        }
                    }
                ]
            }]
        }
        
        headers = {'Content-Type': 'application/json'}
        
        # Request
        response = requests.post(url, headers=headers, json=payload, timeout=60)
        
        if response.status_code != 200:
            return {"error": f"Erro API ({response.status_code}): {response.text}"}
            
        result_json = response.json()
        
        # Tenta extrair o texto da resposta da IA
        try:
            candidates = result_json.get("candidates", [])
            if not candidates: return {"error": "API não retornou candidatos", "raw": result_json}
            
            raw_text = candidates[0].get("content", {}).get("parts", [])[0].get("text", "")
            
            # Limpeza do Markdown JSON (```json ... ```)
            clean_text = raw_text.strip()
            if clean_text.startswith("```"):
                clean_text = clean_text.split("```")[1]
                if clean_text.startswith("json"): 
                    clean_text = clean_text[4:]
            
            return json.loads(clean_text)
            
        except Exception as parse_error:
            return {"error": f"Erro ao processar JSON da IA: {str(parse_error)}", "raw_text": raw_text}

    except Exception as e:
        return {"error": f"Erro de conexão/processamento: {str(e)}"}

# --- UI PRINCIPAL ---
def main(page: ft.Page):
    page.title = "Médico IA"
    page.scroll = "adaptive"
    page.bgcolor = ft.colors.WHITE
    
    # Variáveis de Estado
    api_key_val = "YOUR_API_KEY_HERE" # Idealmente ler de config
    audio_path = ft.Ref[str]()
    
    # Componentes UI
    txt_status = ft.Text("Aguardando áudio...", color=ft.colors.GREY)
    
    def on_file_picked(e: ft.FilePickerResultEvent):
        if e.files:
            f = e.files[0]
            txt_status.value = f"Arquivo selecionado: {f.name}"
            # Armazena caminho no ref (ou var global)
            audio_path.current = f.path
            btn_process.disabled = False
            page.update()
            
    file_picker = ft.FilePicker(on_result=on_file_picked)
    page.overlay.append(file_picker)
    
    def on_process_click(e):
        if not audio_path.current: return
        
        txt_status.value = "Enviando para Gemini..."
        txt_status.color = ft.colors.BLUE
        page.update()
        
        # Thread para não travar UI
        def task():
            res = run_gemini_analysis(api_key_val, audio_path.current)
            if "error" in res:
                txt_status.value = f"Erro: {res['error']}"
                txt_status.color = ft.colors.RED
            else:
                txt_status.value = "Análise Concluída!"
                txt_status.color = ft.colors.GREEN
                
                # Atualiza UI com Resultado
                show_results(res)
            page.update()
            
        threading.Thread(target=task).start()

    btn_process = ft.ElevatedButton("Processar Consulta", on_click=on_process_click, disabled=True)
    
    # Area de Resultados
    result_col = ft.Column()
    
    def show_results(data):
        result_col.controls.clear()
        
        # SOAP
        soap = data.get("soap", {})
        result_col.controls.append(ft.Text("SOAP", size=20, weight="bold", color=ft.colors.BLACK))
        result_col.controls.append(ft.Text(f"S: {soap.get('s','-')}", color=ft.colors.BLACK))
        result_col.controls.append(ft.Text(f"O: {soap.get('o','-')}", color=ft.colors.BLACK))
        result_col.controls.append(ft.Text(f"A: {soap.get('a','-')}", color=ft.colors.BLACK))
        result_col.controls.append(ft.Text(f"P: {soap.get('p','-')}", color=ft.colors.BLACK))
        
        # Meds
        meds = data.get("medicamentos", [])
        if meds:
            result_col.controls.append(ft.Divider())
            result_col.controls.append(ft.Text("Medicamentos", size=18, weight="bold", color=ft.colors.BLACK))
            
            checked = check_meds(meds)
            for m in checked:
                row = ft.Row([
                    ft.Text(m['name'], weight="bold", color=ft.colors.BLACK),
                    ft.Container(
                        content=ft.Text("REMUME", size=10, color=ft.colors.WHITE),
                        bgcolor=ft.colors.GREEN if m['remume'] else ft.colors.GREY,
                        padding=5, border_radius=5
                    )
                ])
                result_col.controls.append(row)
        
        page.update()

    # Layout Principal
    page.add(
        ft.Column([
            ft.Text("Assistente Médico IA", size=25, weight="bold", color=ft.colors.BLUE),
            ft.Divider(),
            ft.ElevatedButton("Selecionar Áudio (Gravação)", 
                             icon=ft.icons.AUDIO_FILE, 
                             on_click=lambda _: file_picker.pick_files(allow_multiple=False, allowed_extensions=["mp3", "wav", "m4a", "ogg"])),
            txt_status,
            btn_process,
            ft.Divider(),
            result_col
        ])
    )

if __name__ == "__main__":
    ft.app(target=main)
