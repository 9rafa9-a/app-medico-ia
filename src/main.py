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
        Analise o áudio desta consulta e gere um JSON estrito com:
        1. "soap": objeto com chaves "s", "o", "a", "p" (Subjetivo, Objetivo, Avaliação, Plano).
        2. "medicamentos": lista de strings com nomes genéricos dos medicamentos prescritos ou citados.
        3. "sugestoes": objeto com chaves "s", "o", "a", "p". Em cada chave, uma lista de strings com sugestões do que faltou perguntar ou examinar (ex: "Perguntar sobre alergias" no S, "Avaliar desidratação" no O). Se estiver completo, lista vazia.
        
        Responda APENAS o JSON, sem markdown.
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
        
        # Extração Segura
        try:
            candidates = result.get('candidates', [])
            if not candidates:
                 return {"error": "Gemini não retornou candidatos. Áudio mudo ou bloqueado?"}
                 
            raw_text = candidates[0]['content']['parts'][0]['text']
            # Limpeza do JSON Markdown
            cleaned_text = raw_text.replace("```json", "").replace("```", "").strip()
            return json.loads(cleaned_text)
        except Exception as e:
            print(f"Erro Parse: {raw_text}")
            return {"error": f"Erro ao processar JSON: {e}"}
            
    except Exception as e:
        return {"error": f"Erro Geral: {e}"}

# ... (check_meds_debug mantida) ...

# ... (UI Config mantida) ...

# ... (Main Init mantida) ...

        def show_results(data):
            result_col.controls.clear()
            
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
                                    [ft.Row([ft.Icon(ft.icons.ARROW_RIGHT, size=12, color=NEUTRAL_GREY), ft.Text(s, size=12)]) for s in sugs],
                                    spacing=2
                                )
                            ],
                            min_tile_height=30,
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
