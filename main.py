import flet as ft
import sys
import traceback

# --- VERSION CONTROL ---
APP_VERSION = "1.0.0"
UPDATE_URL = "https://raw.githubusercontent.com/9rafa9-a/swift-gemini/main/version.json" # Adjust repo user/name if needed

def main(page: ft.Page):
    # 1. SETUP UI SHELL
    page.title = "Medico IA"
    page.scroll = "auto"
    page.theme_mode = "light"
    page.bgcolor = "#f5f5f5"

    # Header / Debug Log
    debug_expander = ft.ExpansionTile(
        title=ft.Text("Log do Sistema", size=12, color="grey"),
        subtitle=ft.Text(f"v{APP_VERSION}", size=10),
        controls=[
            ft.ListView(height=150, spacing=2, padding=10, auto_scroll=True, id="log_view")
        ]
    )
    
    # Main Container
    main_col = ft.Column(spacing=20)
    page.add(debug_expander, main_col)

    def log(msg, error=False):
        # Add to log view logic (simplified for perf)
        # We might not render everything to avoid lag, mainly prints
        print(msg)
        try:
             # Just invalidating log if needed, for now keep simple print
             pass
        except: pass

    # 2. RUNTIME LOADING
    try:
        log("Importando Bibliotecas...")
        import os
        import json
        import time
        import requests
        from unidecode import unidecode
        
        # --- DATABASE LOGIC (Restored) ---
        def load_json_safe(filename, key_extractor):
            try:
                base_dir = os.path.dirname(os.path.abspath(__file__))
                path = os.path.join(base_dir, "data", filename)
                if not os.path.exists(path): return []
                with open(path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                names = []
                if isinstance(data, list):
                    for item in data:
                        val = key_extractor(item)
                        if val: names.append(str(val))
                return names
            except Exception: return []

        # Extractors
        def ext_remume(i): return i.get('nome_completo', i.get('nome')) if isinstance(i, dict) else i
        def ext_ac(i): return i.get('nome') if isinstance(i, dict) else i
        def ext_rename(i):
            if isinstance(i, str): return i
            if isinstance(i, dict):
                if 'itens' in i and isinstance(i['itens'], list): return None # Skip groups
                return i.get('nome')

        def normalize(text):
            if not text: return ""
            return unidecode(str(text)).lower().strip()

        def check_meds(med_list):
            remume = load_json_safe("db_remume.json", ext_remume)
            ac = load_json_safe("db_alto_custo.json", ext_ac)
            rename = load_json_safe("db_rename.json", ext_rename)

            db_map = {
                "REMUME": [normalize(x) for x in remume],
                "ESTADUAL": [normalize(x) for x in ac],
                "RENAME": [normalize(x) for x in rename]
            }

            results = []
            for med in med_list:
                med_norm = normalize(med)
                med_res = {"name": med, "found": []}
                for db_name, contents in db_map.items():
                    # Simple substring match
                    if any(med_norm in c or c in med_norm for c in contents if len(c) > 3):
                        med_res["found"].append(db_name)
                results.append(med_res)
            return results

        # --- AUTO UPDATE ---
        def check_for_updates():
            try:
                 # Logic: User repo must have version.json {"version": "1.0.1", "url": "..."}
                 # Hardcoded repo check for example
                 r = requests.get(UPDATE_URL, timeout=3)
                 if r.status_code == 200:
                     info = r.json()
                     if info.get("version") != APP_VERSION:
                         def close_dlg(e):
                             page.dialog.open = False
                             page.update()
                         
                         dlg = ft.AlertDialog(
                             title=ft.Text("Atualização Disponível"),
                             content=ft.Text(f"Nova versão: {info.get('version')}\nSua versão: {APP_VERSION}"),
                             actions=[ft.TextButton("Fechar", on_click=close_dlg)]
                         )
                         page.dialog = dlg
                         dlg.open = True
                         page.update()
            except: pass # Silent fail

        # --- GEMINI CLIENT ---
        API_URL = "https://generativelanguage.googleapis.com"
        MODEL_NAME = "gemini-2.5-flash"

        class GeminiClient:
            def __init__(self, api_key):
                self.api_key = api_key
            
            def process_audio(self, file_path):
                # Upload
                url_init = f"{API_URL}/upload/v1beta/files?key={self.api_key}"
                file_size = os.path.getsize(file_path)
                headers = {
                    "X-Goog-Upload-Protocol": "resumable",
                    "X-Goog-Upload-Command": "start",
                    "X-Goog-Upload-Header-Content-Length": str(file_size),
                    "X-Goog-Upload-Header-Content-Type": "audio/wav",
                    "Content-Type": "application/json"
                }
                r = requests.post(url_init, headers=headers, json={"file": {"display_name": "med_audio"}})
                r.raise_for_status()
                upload_url = r.headers["X-Goog-Upload-URL"]

                with open(file_path, "rb") as f:
                    headers_up = {"Content-Length": str(file_size), "X-Goog-Upload-Offset": "0", "X-Goog-Upload-Command": "upload, finalize"}
                    r_up = requests.post(upload_url, headers=headers_up, data=f)
                    r_up.raise_for_status()
                
                file_uri = r_up.json()["file"]["uri"]
                file_name = r_up.json()["file"]["name"]

                # Wait
                for _ in range(60):
                    r_get = requests.get(f"{API_URL}/v1beta/{file_name}?key={self.api_key}")
                    if r_get.json().get("state") == "ACTIVE": break
                    if r_get.json().get("state") == "FAILED": raise Exception("Gemini falhou")
                    time.sleep(1)
                
                # Generate
                prompt = """
                Atue como médico auditor experiente. Ouça o áudio da consulta.
                Extraia JSON EXATO:
                {
                    "soap": {"s": "...", "o": "...", "a": "...", "p": "..."},
                    "diagnostico": "Hipótese Principal",
                    "medicamentos": ["nome_generico_1", "nome_generico_2"]
                }
                """
                gen_url = f"{API_URL}/v1beta/models/{MODEL_NAME}:generateContent?key={self.api_key}"
                payload = {
                    "contents": [{"parts": [{"text": prompt}, {"file_data": {"mime_type": "audio/wav", "file_uri": file_uri}}]}],
                    "generationConfig": {"response_mime_type": "application/json"}
                }
                r_gen = requests.post(gen_url, json=payload)
                r_gen.raise_for_status()
                return json.loads(r_gen.json()["candidates"][0]["content"]["parts"][0]["text"])

        # --- UI COMPONENTS ---
        
        # KEY INPUT
        api_key_field = ft.TextField(
            label="Google API Key", 
            password=True, 
            bgcolor="white", 
            border_color="blue",
            prefix_icon=ft.Icons.KEY
        )
        
        # UPLOAD BTN
        def on_file_picked(e: ft.FilePickerResultEvent):
            if e.files:
                file_path = e.files[0].path
                if not api_key_field.value:
                    page.snack_bar = ft.SnackBar(ft.Text("Por favor, insira a API Key!"))
                    page.snack_bar.open = True
                    page.update()
                    return
                
                # Show loading
                pb = ft.ProgressBar(width=400, color="amber")
                status_txt = ft.Text("Processando Áudio (Upload + Análise)...", color="blue")
                main_col.controls.insert(2, ft.Column([status_txt, pb]))
                page.update()
                
                try:
                    client = GeminiClient(api_key_field.value)
                    data = client.process_audio(file_path)
                    render_results(data)
                except Exception as ex:
                    main_col.controls.append(ft.Text(f"Erro: {ex}", color="red"))
                finally:
                    # Remove loading
                    main_col.controls.pop(2) # Remove Column(Status+PB) assuming it's at index 2
                    page.update()

        file_picker = ft.FilePicker(on_result=on_file_picked)
        page.overlay.append(file_picker)

        upload_btn = ft.Container(
            content=ft.Row(
                [
                    ft.Icon(ft.Icons.CLOUD_UPLOAD, color="white", size=30),
                    ft.Text("Selecionar Áudio da Consulta", color="white", size=16, weight="bold")
                ],
                alignment="center"
            ),
            bgcolor=ft.Colors.BLUE_600,
            padding=20,
            border_radius=15,
            on_click=lambda _: file_picker.pick_files(allow_multiple=False),
            shadow=ft.BoxShadow(blur_radius=10, color=ft.Colors.BLUE_200)
        )

        def render_results(data):
            # Clear previous results (keep header/input)
            del main_col.controls[3:] 
            
            # 1. SOAP
            if "soap" in data:
                s_data = data["soap"]
                soap_card = ft.Card(
                    content=ft.Container(
                        content=ft.Column([
                            ft.Text("📝 SOAP - Evolução Clínica", size=20, weight="bold", color="blue"),
                            ft.Divider(),
                            ft.Text(f"S (Subjetivo): {s_data.get('s')}", selectable=True),
                            ft.Text(f"O (Objetivo): {s_data.get('o')}", selectable=True),
                            ft.Text(f"A (Avaliação): {s_data.get('a')}", selectable=True),
                            ft.Text(f"P (Plano): {s_data.get('p')}", selectable=True),
                        ]),
                        padding=15
                    ),
                    color="white",
                    elevation=5
                )
                main_col.controls.append(soap_card)

            # 2. DIAGNOSIS
            if "diagnostico" in data:
                diag_card = ft.Card(
                    content=ft.Container(
                        content=ft.Column([
                            ft.Text("🩺 Hipótese Diagnóstica", size=20, weight="bold", color="green"),
                            ft.Divider(),
                            ft.Text(data["diagnostico"], size=16, weight="bold", selectable=True)
                        ]),
                        padding=15
                    ),
                    color="white",
                    elevation=5
                )
                main_col.controls.append(diag_card)

            # 3. MEDS
            if "medicamentos" in data:
                checked = check_meds(data["medicamentos"])
                med_rows = []
                for m in checked:
                    icon = ft.Icons.CHECK_CIRCLE if m["found"] else ft.Icons.WARNING
                    color = "green" if m["found"] else "orange"
                    
                    found_str = " | ".join(m["found"]) if m["found"] else "Não encontrado na rede"
                    
                    med_rows.append(
                        ft.ListTile(
                            leading=ft.Icon(icon, color=color),
                            title=ft.Text(m["name"], weight="bold"),
                            subtitle=ft.Text(found_str, size=12, color="grey")
                        )
                    )
                
                med_card = ft.Card(
                    content=ft.Container(
                        content=ft.Column([
                            ft.Text("💊 Validação de Medicamentos (SUS)", size=20, weight="bold", color="red"),
                            ft.Divider(),
                            ft.Column(med_rows)
                        ]),
                        padding=15
                    ),
                    color="white",
                    elevation=5
                )
                main_col.controls.append(med_card)
            
            page.update()

        # BUILD MAIN LAYOUT
        main_col.controls = [
            ft.Text("Assistente Médico IA", size=28, weight="bold", color="#333333"),
            api_key_field,
            upload_btn
            # Result cards will be appended here
        ]
        
        # Check updates on start
        check_for_updates()
        page.update()

    except Exception as e:
        page.add(ft.Text(f"Fatal Error: {traceback.format_exc()}", color="red"))

if __name__ == "__main__":
    ft.app(target=main)
