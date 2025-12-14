import flet as ft
import os
import json
import threading
import time
import requests
import re
from unidecode import unidecode
from fpdf import FPDF
from datetime import datetime

# ... (Imports e Configs) ...

# --- GERADOR DE PDF ---
class PDFReport(FPDF):
    def header(self):
        self.set_font('Arial', 'B', 16)
        self.set_text_color(0, 82, 204) # MEDICAL_BLUE
        self.cell(0, 10, 'MEDUBS - Relatório Clínico', 0, 1, 'C')
        self.ln(5)

    def footer(self):
        self.set_y(-15)
        self.set_font('Arial', 'I', 8)
        self.set_text_color(128)
        self.cell(0, 10, f'Página {self.page_no()}', 0, 0, 'C')

def generate_pdf_report(data, filename):
    pdf = PDFReport()
    pdf.add_page()
    pdf.set_auto_page_break(auto=True, margin=15)
    
    # Data/Hora
    pdf.set_font("Arial", size=10)
    pdf.set_text_color(100)
    now = datetime.now().strftime("%d/%m/%Y %H:%M")
    pdf.cell(0, 10, f"Gerado em: {now}", ln=True, align='R')
    pdf.ln(5)

    # SOAP
    soap = data.get("soap", {})
    suggestions = data.get("sugestoes", {})
    
    sections = [
        ("Subjetivo", soap.get('s'), "s"),
        ("Objetivo", soap.get('o'), "o"),
        ("Avaliação", soap.get('a'), "a"),
        ("Plano", soap.get('p'), "p")
    ]

    for title, content, key in sections:
        # Título Seção
        pdf.set_font("Arial", 'B', 12)
        pdf.set_text_color(0, 0, 0)
        pdf.set_fill_color(240, 240, 240)
        pdf.cell(0, 8, f" {title}", 1, 1, 'L', fill=True)
        
        # Conteúdo
        pdf.set_font("Arial", size=11)
        pdf.multi_cell(0, 6, content if content else "-")
        pdf.ln(2)
        
        # Sugestões
        sugs = suggestions.get(key, [])
        if sugs:
            pdf.set_font("Arial", 'I', 10)
            pdf.set_text_color(100, 100, 100)
            pdf.cell(0, 6, "Sugestões da IA:", ln=True)
            for s in sugs:
                 pdf.multi_cell(0, 5, f" - {s}")
            pdf.ln(3)
        
        pdf.ln(3)

    # Medicamentos
    pdf.add_page()
    pdf.set_font("Arial", 'B', 12)
    pdf.set_text_color(0, 0, 0)
    pdf.set_fill_color(227, 242, 253) # Light Blue
    pdf.cell(0, 8, " Prescrição & Análise", 1, 1, 'L', fill=True)
    pdf.ln(5)

    meds = data.get("medicamentos", [])
    if not meds:
        pdf.set_font("Arial", 'I', 11)
        pdf.cell(0, 10, "Nenhum medicamento identificado.", ln=True)
    else:
        # Re-usa lógica de check
        audit = check_meds_debug(meds)
        
        pdf.set_font("Arial", size=10)
        
        for item in audit["items"]:
            name = item['ia_term'].title()
            # Tags em texto
            tags = []
            if item['remume']['found']: tags.append("[REMUME]")
            if item['alto_custo']['found']: tags.append("[ALTO CUSTO]")
            if item['rename']['found']: tags.append("[RENAME]")
            if not tags: tags.append("[NÃO CONSTA]")
            
            tag_str = " ".join(tags)
            
            pdf.set_font("Arial", 'B', 11)
            pdf.cell(0, 6, f"{name}", ln=True)
            pdf.set_font("Arial", size=9)
            pdf.set_text_color(0, 82, 204)
            pdf.cell(0, 5, f"{tag_str}", ln=True)
            
            # Detalhes Match
            pdf.set_text_color(80)
            for db in ['remume', 'alto_custo', 'rename']:
                if item[db]['found']:
                     match = item[db]['match']
                     pdf.cell(0, 4, f"  -> {db.upper()}: {match}", ln=True)
            
            pdf.set_text_color(0)
            pdf.ln(3)

    return pdf.output(dest='S').encode('latin-1', 'replace') # Retorna bytes



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
    # Estrutura do JSON detectada: [{'grupo': '...', 'itens': [{'nome': '...'}, ...]}, ...]
    if isinstance(data, list):
        for grupo in data:
            if isinstance(grupo, dict) and "itens" in grupo:
                for item in grupo["itens"]:
                    if isinstance(item, dict):
                        names.append(item.get('nome', ''))
                    elif isinstance(item, str):
                        names.append(item)
            elif isinstance(grupo, dict) and "nome" in grupo: # Caso fallback
                names.append(grupo['nome'])
            elif isinstance(grupo, str):
                names.append(grupo)
    return [n for n in names if n]

# Verificador de Medicamentos (Mantido para compatibilidade, se necessário)
def check_meds(med_list):
    # ... (lógica antiga, pode manter ou remover se só usar o debug)
    return [] 

# --- INTEGRAÇÃO GEMINI (REST API) ---
import base64

def run_gemini_analysis(api_key, audio_path_val):
    print(f"DEBUG: Iniciando análise para {audio_path_val}")
    if not api_key:
        return {"error": "API Key não fornecida."}
    
    if not os.path.exists(audio_path_val):
        return {"error": "Arquivo de áudio não encontrado."}

    try:
        # Lê e codifica o áudio
        with open(audio_path_val, "rb") as f:
            audio_data = base64.b64encode(f.read()).decode("utf-8")
            
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={api_key}"
        
        prompt = """
        Você é um assistente médico especialista.
        Analise o áudio e gere um JSON VÁLIDO e ESTRITO.
        
        Regras de Formatação:
        1. Responda APENAS o JSON. Sem markdown (```json), sem introduções.
        2. Certifique-se de escapar aspas duplas internas.
        
        Estrutura Obrigatória:
        {
          "soap": { "s": "...", "o": "...", "a": "...", "p": "..." },
          "medicamentos": ["..."],
          "sugestoes": { "s": ["..."], "o": ["..."], "a": ["..."], "p": ["..."] }
        }
        """
        
        payload = {
            "contents": [{
                "parts": [
                    {"text": prompt},
                    {"inline_data": {
                        "mime_type": "audio/mp3", # Genérico para audio
                        "data": audio_data
                    }}
                ]
            }]
        }
        
        headers = {"Content-Type": "application/json"}
        # Timeout aumentado para áudios longos
        response = requests.post(url, json=payload, headers=headers, timeout=120)
        
        if response.status_code != 200:
            return {"error": f"Erro API Gemini ({response.status_code}): {response.text}"}
            
        result = response.json()
        
        # Extração Segura com Regex
        try:
            candidates = result.get('candidates', [])
            if not candidates:
                 return {"error": "Gemini não retornou candidatos. Áudio mudo ou bloqueado?"}
                 
            raw_text = candidates[0]['content']['parts'][0]['text']
            
            # Busca JSON com Regex
            match = re.search(r'\{.*\}', raw_text, re.DOTALL)
            if match:
                json_str = match.group(0)
            else:
                json_str = raw_text

            json_str = json_str.replace("```json", "").replace("```", "").strip()
            return json.loads(json_str)
        except Exception as e:
            print(f"Erro Parse: {raw_text}")
            return {"error": f"Erro JSON: {str(e)}"}
            
    except Exception as e:
        return {"error": f"Erro Geral: {e}"}

# --- INTEGRAÇÃO GEMINI (REST API) ---
# (run_gemini_analysis já está acima)

def check_meds_debug(meds_found):
    try:
        remume_list = [unidecode(x).lower() for x in get_remume()]
        rename_list = [unidecode(x).lower() for x in get_rename()]
        alto_custo_list = [unidecode(x).lower() for x in get_alto_custo()]
        
        audit_items = []
        
        for med in meds_found:
            med_norm = unidecode(med).lower()
            
            # Helper de busca fuzzy ou exata
            def search_db(db_list):
                # Busca Exata
                if med_norm in db_list:
                    return {"found": True, "match": med}
                # Busca Parcial (Simples)
                for item in db_list:
                    if med_norm in item or item in med_norm:
                         return {"found": True, "match": item}
                return {"found": False, "match": None}
    
            audit_items.append({
                "ia_term": med,
                "remume": search_db(remume_list),
                "rename": search_db(rename_list),
                "alto_custo": search_db(alto_custo_list)
            })
            
        return {
            "items": audit_items,
            "meta": {
                "count_remume": sum(1 for x in audit_items if x['remume']['found']),
                "count_rename": sum(1 for x in audit_items if x['rename']['found'])
            }
        }
    except Exception as e:
        print(f"Erro Check Meds: {e}")
        return {"items": [], "meta": {"error": str(e)}}

# --- CONFIGURAÇÃO DE UI (Temas e Cores) ---
MEDICAL_BLUE = "#0052CC"
MEDICAL_LIGHT_BLUE = "#E3F2FD"
SUCCESS_GREEN = "#2E7D32"
WARNING_ORANGE = "#EF6C00"
NEUTRAL_GREY = "#757575"

# --- UI PRINCIPAL (Refatorada - Fase 3) ---
def main(page: ft.Page):
    try:
        page.title = "MEDUBS" # Nome Novo
        page.scroll = "adaptive"
        page.bgcolor = "#F5F7FA"
        page.padding = 0
        
        # State
        audio_path = ft.Ref[str]()
        api_key_ref = ft.Ref[ft.TextField]()
        
        # Recupera API Key salva (Com proteção anti-crash)
        saved_key = ""
        try:
            # Tenta ler, se falhar ou se a propriedade não existir, segue vazio
            if hasattr(page, 'client_storage') and page.client_storage:
                saved_key = page.client_storage.get("gemini_api_key") or ""
        except Exception as e:
            print(f"Erro ao ler storage: {e}")
            # Não faz nada, segue sem chave
        
        # --- COMPONENTES VISUAIS ---
        
        # Header MEDUBS
        header = ft.Container(
            content=ft.Row([
                ft.Column([
                    ft.Text("MEDUBS", size=26, weight="bold", color="white"), # Fonte padrão
                    ft.Text("IA Clínica Inteligente", size=12, color="white70")
                ], spacing=2),
                # Espaço para botão de update será adicionado depois
            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            bgcolor=MEDICAL_BLUE,
            padding=ft.padding.symmetric(horizontal=20, vertical=25), # Mais espaço
            border_radius=ft.border_radius.only(bottom_left=25, bottom_right=25), # Mais arredondado
            shadow=ft.BoxShadow(blur_radius=15, color=ft.colors.with_opacity(0.4, "black"))
        )
        
        # Status Indicator
        txt_status = ft.Text("Aguardando áudio...", color=NEUTRAL_GREY, italic=True)
        
        # Input API (Com persistência)
        def save_api_key(e):
            try:
                page.client_storage.set("gemini_api_key", api_key_ref.current.value)
            except: pass # Ignora erro de save
            
        txt_api_key = ft.TextField(
            ref=api_key_ref,
            value=saved_key,
            label="Google API Key",
            password=True,
            can_reveal_password=True,
            prefix_icon=ft.icons.KEY,
            border_color=MEDICAL_BLUE,
            text_size=12,
            height=45,
            content_padding=10,
            on_change=save_api_key # Salva ao digitar
        )

        # Imagem Placeholder
        # PROTEÇÃO DE ASSET: Se não achar, não quebra
        img_src = "https://placehold.co/200x200?text=MEDUBS" # Fallback Online
        try:
             local_asset = asset("logo_medico.png")
             if os.path.exists(local_asset):
                 img_src = local_asset
        except: pass

        img_placeholder = ft.Image(
            src=img_src,
            width=200,
            opacity=0.8, # Um pouco mais visível
            animate_opacity=300,
            error_content=ft.Text("Logo não enc.", color="red") # Fallback visual
        )
        container_placeholder = ft.Container(
            content=ft.Column([
                img_placeholder,
                ft.Text("Toque em Selecionar Áudio para começar", color=NEUTRAL_GREY, weight="bold")
            ], horizontal_alignment="center", spacing=20),
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
            style=ft.ButtonStyle(shape=ft.RoundedRectangleBorder(radius=12), elevation=1)
        )
        
        btn_process = ft.ElevatedButton(
            "Processar Consulta",
            icon=ft.icons.ANALYTICS,
            on_click=None,
            bgcolor=MEDICAL_BLUE, color="white",
            disabled=True,
            style=ft.ButtonStyle(shape=ft.RoundedRectangleBorder(radius=12), elevation=4)
        )

        # Container de Resultados
        result_col = ft.Column(visible=False)

        def on_process_click(e):
            api_key = api_key_ref.current.value
            if not api_key:
                page.show_snack_bar(ft.SnackBar(ft.Text("Insira a API Key!"), bgcolor="red"))
                return
                
            # Garante salvamento
            try: page.client_storage.set("gemini_api_key", api_key)
            except: pass
                
            if not audio_path.current: return
            
            container_placeholder.visible = False
            result_col.visible = False
            txt_status.value = "Analisando com Gemini 2.5..."
            page.update()
            
            def task():
                try:
                    res = run_gemini_analysis(api_key, audio_path.current)
                    if "error" in res:
                        page.show_snack_bar(ft.SnackBar(ft.Text(f"Erro: {res['error']}"), bgcolor="red"))
                        txt_status.value = f"Erro: {res['error'][:30]}..."
                    else:
                        txt_status.value = "Análise Concluída."
                        show_results(res)
                except Exception as e:
                     page.show_snack_bar(ft.SnackBar(ft.Text(f"Erro Thread: {e}"), bgcolor="red"))
                     txt_status.value = "Erro Fatal na Thread."
                
                page.update()
                
            threading.Thread(target=task).start()

        btn_process.on_click = on_process_click

        # --- AUTO-UPDATE ---
        CURRENT_VERSION = "v1.0.1" # Incrementar se lançar tag nova
        REPO_OWNER = "9rafa9-a"
        REPO_NAME = "swift-gemini"

        def check_update(e):
            page.show_snack_bar(ft.SnackBar(ft.Text("Buscando atualizações..."), duration=1000))
            def update_task():
                try:
                    # Debug URL
                    url = f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/releases/latest"
                    print(f"DEBUG: Checking update at {url}")
                    
                    resp = requests.get(url, timeout=10)
                    if resp.status_code == 200:
                        data = resp.json()
                        latest_tag = data.get("tag_name", "v0.0.0")
                        
                        if latest_tag != CURRENT_VERSION:
                            assets = data.get("assets", [])
                            apk_url = ""
                            for asset in assets:
                                if asset["name"].endswith(".apk"):
                                    apk_url = asset["browser_download_url"]
                                    break
                            
                            if apk_url:
                                def close_dlg(e):
                                    page.dialog.open = False
                                    page.update()
                                
                                def do_update(e):
                                    page.launch_url(apk_url)
                                    close_dlg(e)

                                dlg = ft.AlertDialog(
                                    modal=True,
                                    title=ft.Text("Atualização Disponível! 🚀"),
                                    content=ft.Text(f"Nova versão {latest_tag}.\nInstalar agora?"),
                                    actions=[
                                        ft.TextButton("Não", on_click=close_dlg),
                                        ft.TextButton("Sim", on_click=do_update),
                                    ],
                                )
                                page.dialog = dlg
                                dlg.open = True
                                page.update()
                            else:
                                page.show_snack_bar(ft.SnackBar(ft.Text(f"Nova versão {latest_tag} sem APK."), bgcolor=WARNING_ORANGE))
                        else:
                            page.show_snack_bar(ft.SnackBar(ft.Text(f"Versão {CURRENT_VERSION} é a mais atual!"), bgcolor=SUCCESS_GREEN))
                    else:
                        page.show_snack_bar(ft.SnackBar(ft.Text(f"Erro GitHub: {resp.status_code}"), bgcolor="red"))
                except Exception as ex:
                     page.show_snack_bar(ft.SnackBar(ft.Text(f"Erro Update: {ex}"), bgcolor="red"))
            
            threading.Thread(target=update_task).start()

        btn_update = ft.IconButton(
            icon=ft.icons.AUTORENEW, # Corrigido Case
            icon_color="white",
            tooltip="Buscar Atualizações",
            on_click=check_update
        )
        
        # Atualiza Header para incluir botão
        header.content.controls.append(btn_update)

        def save_pdf(e):
             # Verifica se há dados guardados no Column (monkey-patch)
             if not hasattr(result_col, 'data') or not result_col.data: 
                 return
             
             save_file_dialog.save_file(file_name=f"Consulta_{datetime.now().strftime('%Y%m%d_%H%M')}.pdf")

        def on_save_result(e: ft.FilePickerResultEvent):
            if e.path:
                try:
                    pdf_bytes = generate_pdf_report(result_col.data, e.path)
                    with open(e.path, "wb") as f:
                        f.write(pdf_bytes)
                    page.show_snack_bar(ft.SnackBar(ft.Text(f"Salvo em: {e.path}"), bgcolor=SUCCESS_GREEN))
                except Exception as ex:
                    page.show_snack_bar(ft.SnackBar(ft.Text(f"Erro ao salvar: {ex}"), bgcolor="red"))

        save_file_dialog = ft.FilePicker(on_result=on_save_result)
        page.overlay.append(save_file_dialog)

        def show_results(data):
            result_col.controls.clear()
            result_col.data = data # Persiste dados para PDF

            
            # --- BLOCOS SOAP ---
            soap = data.get("soap", {})
            suggestions = data.get("sugestoes", {})
            
            def copy_to_clipboard(text):
                page.set_clipboard(text)
                page.show_snack_bar(ft.SnackBar(ft.Text("Copiado!"), duration=1000))

            def create_soap_card(key, title, content, color, icon):
                content_str = content if content else "-"
                
                # Elementos do Card
                card_content = [
                    ft.Row([
                        ft.Row([ft.Icon(icon, color=color), ft.Text(title, weight="bold", size=16, color=color)]),
                        ft.IconButton(ft.icons.COPY, icon_color=NEUTRAL_GREY, tooltip="Copiar", on_click=lambda _: copy_to_clipboard(content_str))
                    ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                    ft.Divider(height=1, color="#EEEEEE"),
                    ft.Markdown(content_str)
                ]
                
                # Adiciona Sugestões se houver
                sugs = suggestions.get(key, [])
                if sugs:
                    card_content.append(ft.Divider(height=1, color="transparent"))
                    card_content.append(
                        ft.ExpansionTile(
                            title=ft.Text("Sugestões da IA", size=12, italic=True, color=color),
                            leading=ft.Icon(ft.icons.LIGHTBULB_OUTLINE, size=16, color=color),
                            controls=[
                                ft.Column(
                                    [
                                        ft.Row(
                                            [
                                                ft.Icon(ft.icons.ARROW_RIGHT, size=12, color=NEUTRAL_GREY),
                                                ft.Expanded(ft.Text(s, size=12, selectable=True))
                                            ],
                                            vertical_alignment=ft.CrossAxisAlignment.START
                                        ) for s in sugs
                                    ],
                                    spacing=4
                                )
                            ],
                            tile_padding=ft.padding.symmetric(horizontal=0)
                        )
                    )

                return ft.Card(
                    content=ft.Container(
                        content=ft.Column(card_content),
                        padding=15,
                        border=ft.border.only(left=ft.border.BorderSide(5, color))
                    ),
                    elevation=2, # Mais sombra para destacar
                    margin=ft.margin.only(bottom=15)
                )

            result_col.controls.append(create_soap_card("s", "Subjetivo", soap.get('s'), MEDICAL_BLUE, ft.icons.PERSON))
            result_col.controls.append(create_soap_card("o", "Objetivo", soap.get('o'), SUCCESS_GREEN, ft.icons.MONITOR_HEART))
            result_col.controls.append(create_soap_card("a", "Avaliação", soap.get('a'), WARNING_ORANGE, ft.icons.ANALYTICS))
            result_col.controls.append(create_soap_card("p", "Plano", soap.get('p'), "#8E24AA", ft.icons.MEDICAL_SERVICES))
            
            # ... (Resto igual) ...
            
            # --- MEDICAMENTOS ---
            meds = data.get("medicamentos", [])
            
            med_content = []
            if not meds:
                 med_content.append(ft.Container(content=ft.Text("Nenhum medicamento identificado.", italic=True), padding=10))
            else:
                audit = check_meds_debug(meds)
                
                for item in audit["items"]:
                    name = item['ia_term']
                    tags = []
                    
                    if item['remume']['found']: 
                        tags.append(ft.Container(content=ft.Text("REMUME", size=10, color="white", weight="bold"), bgcolor=SUCCESS_GREEN, padding=5, border_radius=4))
                    if item['alto_custo']['found']:
                         tags.append(ft.Container(content=ft.Text("ALTO CUSTO", size=10, color="white", weight="bold"), bgcolor=WARNING_ORANGE, padding=5, border_radius=4))
                    if item['rename']['found']:
                         tags.append(ft.Container(content=ft.Text("RENAME", size=10, color="white", weight="bold"), bgcolor=MEDICAL_BLUE, padding=5, border_radius=4))
                    
                    if not tags:
                        tags.append(ft.Container(content=ft.Text("NÃO CONSTA", size=10, color="white"), bgcolor="red", padding=5, border_radius=4))

                    med_content.append(
                        ft.Container(
                            content=ft.Column([
                                ft.Text(name.title(), weight="bold", size=16),
                                ft.Row(tags, wrap=True)
                            ]),
                            padding=ft.padding.all(12),
                            border=ft.border.only(bottom=ft.border.BorderSide(1, "#EEEEEE"))
                        )
                    )

                # --- DEBUG PANEL ---
                debug_info = []
                debug_info.append(ft.Text(f"Total IA: {len(meds)} | REMUME({audit['meta']['count_remume']}) RENAME({audit['meta']['count_rename']})", size=11, color="grey"))
                
                for item in audit["items"]:
                    debug_info.append(ft.Divider())
                    debug_info.append(ft.Text(f"'{item['ia_term']}'", weight="bold", size=12))
                    # Detalhes compactos
                    for db in ['remume', 'alto_custo', 'rename']:
                        status = "✅" if item[db]['found'] else "❌"
                        match_txt = f": {item[db]['match']}" if item[db]['match'] else ""
                        color = "green" if item[db]['found'] else "red"
                        debug_info.append(ft.Text(f"{status} {db.upper()}{match_txt}", color=color, size=10))

                expansion_debug = ft.ExpansionTile(
                    title=ft.Row([ft.Icon(ft.icons.BUG_REPORT, size=14, color=NEUTRAL_GREY), ft.Text("Auditoria Técnica", size=12, color=NEUTRAL_GREY)]),
                    controls=[
                        ft.Container(
                            content=ft.Column(debug_info),
                            padding=10,
                            bgcolor="#FFFDE7", 
                            border=ft.border.all(1, "#FFF59D"),
                            border_radius=8
                        )
                    ]
                )
                result_col.controls.append(ft.Container(expansion_debug, margin=ft.margin.only(top=10)))

            result_col.controls.insert(4, ft.Card(
                content=ft.Container(
                    content=ft.Column([
                        ft.Row([ft.Icon(ft.icons.MEDICATION, color=MEDICAL_BLUE), ft.Text("Prescrição & Análise", size=18, weight="bold")]),
                        ft.Divider(height=1),
                        *med_content
                    ]),
                    padding=15
                ),
                elevation=2,
                margin=ft.margin.only(bottom=20)
            ))

            # Botão PDF
            btn_pdf = ft.ElevatedButton(
                "Baixar Relatório PDF",
                icon=ft.icons.PICTURE_AS_PDF,
                bgcolor=MEDICAL_BLUE,
                color="white",
                on_click=save_pdf,
                style=ft.ButtonStyle(shape=ft.RoundedRectangleBorder(radius=10))
            )

            result_col.controls.append(ft.Container(height=20))
            result_col.controls.append(ft.Row([btn_pdf], alignment=ft.MainAxisAlignment.CENTER))
            result_col.controls.append(ft.Container(height=30))

            result_col.visible = True
            page.update()

        # Montagem Final
        page.add(
            header,
            ft.Container(
                content=ft.Column([
                    ft.Container(height=10), # Espaçamento
                    txt_api_key,
                    ft.Container(height=20),
                    ft.Row([btn_select, btn_process], alignment="center", spacing=20),
                    ft.Container(content=txt_status, alignment=ft.alignment.center),
                    ft.Divider(color="transparent", height=10),
                    container_placeholder,
                    result_col,
                    ft.Container(height=50) # Bottom padding
                ]),
                padding=20
            )
        )

    except Exception as e:
        # TELA DE ERRO FATAL (Blue Screen of Life)
        # Se algo explodir no startup, isso vai aparecer no celular
        page.clean()
        page.bgcolor = "red"
        page.add(
            ft.Column([
                ft.Icon(ft.icons.ERROR_OUTLINE, color="white", size=50),
                ft.Text("ERRO FATAL DE INICIALIZAÇÃO", color="white", size=20, weight="bold"),
                ft.Text(f"Ocorreu um erro ao abrir o app:", color="white"),
                ft.Container(
                    content=ft.Text(str(e), color="black", font_family="monospace"),
                    bgcolor="white", padding=10, border_radius=5
                ),
                ft.Text("Por favor, avise o desenvolvedor e envie o erro acima.", color="white70")
            ], alignment=ft.MainAxisAlignment.CENTER, horizontal_alignment=ft.CrossAxisAlignment.CENTER)
        )
        page.update()

if __name__ == "__main__":
    ft.app(target=main)
