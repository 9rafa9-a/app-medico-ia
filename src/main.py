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
        # Prepara a URL (Usando versão solicitada 2.5)
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={api_key}"
        
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

# --- CONFIGURAÇÃO DE UI (Temas e Cores) ---
MEDICAL_BLUE = "#0052CC"
MEDICAL_LIGHT_BLUE = "#E3F2FD"
SUCCESS_GREEN = "#2E7D32"
WARNING_ORANGE = "#EF6C00"
NEUTRAL_GREY = "#757575"

# --- LÓGICA DE AUDITORIA (DEBUG) ---
def check_meds_debug(med_list):
    remume = get_remume()
    alto_custo = get_alto_custo()
    rename = get_rename()
    
    # Normalização
    def norm(txt): return unidecode(str(txt)).lower().strip()
    
    db_remume = [(norm(m), m) for m in remume]
    db_alto_custo = [(norm(m), m) for m in alto_custo]
    db_rename = [(norm(m), m) for m in rename]
    
    results = []
    
    for med in med_list:
        med_n = norm(med)
        
        # Estrutura de Resultado Detalhada
        item_status = {
            "ia_term": med,
            "remume": {"found": False, "match": None},
            "alto_custo": {"found": False, "match": None},
            "rename": {"found": False, "match": None}
        }
        
        # Busca REMUME
        for d_n, d_real in db_remume:
            # Match simples (contém)
            if len(d_n) > 3 and (med_n in d_n or d_n in med_n):
                item_status["remume"] = {"found": True, "match": d_real}
                break # Para no primeiro match
                
        # Busca Alto Custo
        for d_n, d_real in db_alto_custo:
            if len(d_n) > 3 and (med_n in d_n or d_n in med_n):
                item_status["alto_custo"] = {"found": True, "match": d_real}
                break

        # Busca RENAME
        for d_n, d_real in db_rename:
            if len(d_n) > 3 and (med_n in d_n or d_n in med_n):
                item_status["rename"] = {"found": True, "match": d_real}
                break
                
        results.append(item_status)
    
    # Retorna metadata também para o painel de debug
    return {
        "items": results,
        "meta": {
            "count_remume": len(remume),
            "count_alto_custo": len(alto_custo),
            "count_rename": len(rename)
        }
    }

# --- UI PRINCIPAL (Refatorada) ---
def main(page: ft.Page):
    page.title = "Médico IA"
    page.scroll = "adaptive"
    page.bgcolor = "#F5F7FA" # Fundo Cinza Claro Profissional
    page.padding = 0 # Controle total
    
    # State
    audio_path = ft.Ref[str]()
    api_key_ref = ft.Ref[ft.TextField]()
    
    # --- COMPONENTES VISUAIS ---
    
    # Header
    header = ft.Container(
        content=ft.Column([
            ft.Text("Assistente Médico IA", size=22, weight="bold", color="white"),
            ft.Text("Análise Clínica & Farmacêutica", size=12, color="white70")
        ]),
        bgcolor=MEDICAL_BLUE,
        padding=ft.padding.all(20),
        border_radius=ft.border_radius.only(bottom_left=20, bottom_right=20),
        shadow=ft.BoxShadow(blur_radius=10, color=ft.colors.with_opacity(0.3, "black"))
    )
    
    # Status Indicator
    txt_status = ft.Text("Aguardando áudio...", color=NEUTRAL_GREY, italic=True)
    
    # Input API (Estilizado)
    txt_api_key = ft.TextField(
        ref=api_key_ref,
        label="Google API Key",
        password=True,
        can_reveal_password=True,
        prefix_icon=ft.icons.KEY,
        border_color=MEDICAL_BLUE,
        text_size=12,
        height=45,
        content_padding=10
    )

    # Imagem Placeholder (Gerada)
    img_placeholder = ft.Image(
        src=asset("logo_medico.png"), # Usando logo do usuário
        width=200,
        opacity=0.5,
        animate_opacity=300
    )
    container_placeholder = ft.Container(
        content=ft.Column([
            img_placeholder,
            ft.Text("Grave a consulta e selecione o áudio", color=NEUTRAL_GREY)
        ], horizontal_alignment="center"),
        alignment=ft.alignment.center,
        padding=40,
        visible=True
    )

    # Botões
    def on_pick(e):
        if e.files:
            audio_path.current = e.files[0].path
            txt_status.value = f"Arquivo: {e.files[0].name}"
            txt_status.color = MEDICAL_BLUE
            btn_process.disabled = False
            page.update()

    file_picker = ft.FilePicker(on_result=on_pick)
    page.overlay.append(file_picker)
    
    btn_select = ft.ElevatedButton(
        "Selecionar Áudio",
        icon=ft.icons.AUDIO_FILE,
        on_click=lambda _: file_picker.pick_files(allow_multiple=False, allowed_extensions=["mp3", "wav", "m4a"]),
        bgcolor="white", color=MEDICAL_BLUE,
        style=ft.ButtonStyle(shape=ft.RoundedRectangleBorder(radius=10))
    )
    
    btn_process = ft.ElevatedButton(
        "Processar Consulta",
        icon=ft.icons.ANALYTICS,
        on_click=None, # Definido abaixo
        bgcolor=MEDICAL_BLUE, color="white",
        disabled=True,
        style=ft.ButtonStyle(shape=ft.RoundedRectangleBorder(radius=10))
    )

    # Container de Resultados (Cards)
    result_col = ft.Column(visible=False)

    def on_process_click(e):
        api_key = api_key_ref.current.value
        if not api_key:
            page.show_snack_bar(ft.SnackBar(ft.Text("Insira a API Key!"), bgcolor="red"))
            return
            
        if not audio_path.current: return
        
        container_placeholder.visible = False
        result_col.visible = False
        txt_status.value = "Analisando com Gemini 2.5..."
        page.update()
        
        def task():
            res = run_gemini_analysis(api_key, audio_path.current)
            if "error" in res:
                page.show_snack_bar(ft.SnackBar(ft.Text(f"Erro: {res['error']}"), bgcolor="red"))
                txt_status.value = "Erro na análise."
            else:
                txt_status.value = "Análise Concluída."
                show_results(res)
            page.update()
            
        threading.Thread(target=task).start()

    btn_process.on_click = on_process_click

    def show_results(data):
        result_col.controls.clear()
        
        # Card SOAP
        soap = data.get("soap", {})
        card_soap = ft.Card(
            content=ft.Container(
                content=ft.Column([
                    ft.Text("SOAP", weight="bold", size=18, color=MEDICAL_BLUE),
                    ft.Divider(),
                    ft.Markdown(f"**S:** {soap.get('s','-')}"),
                    ft.Markdown(f"**O:** {soap.get('o','-')}"),
                    ft.Markdown(f"**A:** {soap.get('a','-')}"),
                    ft.Markdown(f"**P:** {soap.get('p','-')}"),
                ]),
                padding=15
            ),
            elevation=2,
            margin=10
        )
        result_col.controls.append(card_soap)
        
        # Card Medicamentos
        meds = data.get("medicamentos", [])
        if meds:
            med_rows = []
            
            # Roda Auditoria
            audit = check_meds_debug(meds)
            
            for item in audit["items"]:
                name = item['ia_term']
                
                # Tags
                tags = []
                if item['remume']['found']: 
                    tags.append(ft.Container(content=ft.Text("REMUME", size=10, color="white"), bgcolor=SUCCESS_GREEN, padding=5, border_radius=4))
                if item['alto_custo']['found']:
                     tags.append(ft.Container(content=ft.Text("ALTO CUSTO", size=10, color="white"), bgcolor=WARNING_ORANGE, padding=5, border_radius=4))
                if item['rename']['found']:
                     tags.append(ft.Container(content=ft.Text("RENAME", size=10, color="white"), bgcolor=MEDICAL_BLUE, padding=5, border_radius=4))
                
                if not tags:
                    tags.append(ft.Container(content=ft.Text("NÃO ENCONTRADO", size=10, color="white"), bgcolor=NEUTRAL_GREY, padding=5, border_radius=4))

                med_rows.append(
                    ft.Container(
                        content=ft.Column([
                            ft.Text(name, weight="bold", size=16),
                            ft.Row(tags)
                        ]),
                        padding=10,
                        border=ft.border.only(bottom=ft.border.BorderSide(1, "#E0E0E0"))
                    )
                )

            card_meds = ft.Card(
                content=ft.Container(
                    content=ft.Column([
                        ft.Row([ft.Icon(ft.icons.MEDICATION, color=MEDICAL_BLUE), ft.Text("Medicamentos Sugeridos", size=18, weight="bold")]),
                        ft.Divider(),
                        *med_rows
                    ]),
                    padding=15
                ),
                elevation=2,
                margin=10
            )
            result_col.controls.append(card_meds)

            # --- PAINEL DE DEBUG (AUDITORIA) ---
            debug_info = []
            debug_info.append(ft.Text(f"Bancos Carregados: REMUME({audit['meta']['count_remume']}), Alto Custo({audit['meta']['count_alto_custo']})", size=12, color="grey"))
            
            for item in audit["items"]:
                debug_info.append(ft.Divider())
                debug_info.append(ft.Text(f"IA: '{item['ia_term']}'", weight="bold", size=12))
                
                if item['remume']['found']:
                     debug_info.append(ft.Text(f"✅ REMUME Match: {item['remume']['match']}", color=SUCCESS_GREEN, size=11, font_family="monospace"))
                else:
                     debug_info.append(ft.Text(f"❌ REMUME: Sem match", color="red", size=11))
                     
                if item['alto_custo']['found']:
                     debug_info.append(ft.Text(f"✅ Alto Custo Match: {item['alto_custo']['match']}", color=WARNING_ORANGE, size=11, font_family="monospace"))
                     
            expansion_debug = ft.ExpansionTile(
                title=ft.Text("🕵️ Auditoria Técnica (Debug)", size=14, color=NEUTRAL_GREY),
                controls=[
                    ft.Container(
                        content=ft.Column(debug_info),
                        padding=15,
                        bgcolor="#FFF8E1", # Amarelo clarinho debug
                        border=ft.border.all(1, "#FFECB3")
                    )
                ]
            )
            result_col.controls.append(ft.Container(expansion_debug, margin=10))

        result_col.visible = True
        page.update()

    # Montagem Final
    page.add(
        header,
        ft.Container(
            content=ft.Column([
                txt_api_key,
                ft.Row([btn_select, btn_process], alignment="center", spacing=20),
                txt_status,
                ft.Divider(),
                container_placeholder,
                result_col
            ]),
            padding=20
        )
    )

if __name__ == "__main__":
    ft.app(target=main)
