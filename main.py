import flet as ft
import sys
import traceback

def main(page: ft.Page):
    # 1. SETUP UI SHELL
    page.title = "Medico IA - Versão Estável"
    page.scroll = "auto"
    page.theme_mode = "light"

    log_lv = ft.ListView(height=200, spacing=2, padding=10, auto_scroll=True)
    log_container = ft.Container(
        content=log_lv,
        bgcolor="#111111",
        border_radius=10,
        padding=10,
    )
    
    page.add(
        ft.Text("Assistente Médico (File Input)", size=20, weight="bold", color="blue"),
        ft.Text("Versão sem Gravador Nativo (Bypass)", size=12, color="grey"),
        log_container
    )
    page.update()

    def log(msg, error=False):
        color = "red" if error else "green"
        icon = "❌" if error else "✅"
        log_lv.controls.append(ft.Text(f"{icon} {msg}", color=color, font_family="Consolas"))
        page.update()

    # 2. RUNTIME LOADING
    try:
        log("Importando Bibliotecas...")
        import os
        import json
        import time
        import requests
        from unidecode import unidecode
        
        log(f"Libs OK. Requests v{requests.__version__}")

        # --- CONSTANTS & CLASSES ---
        API_URL = "https://generativelanguage.googleapis.com"
        MODEL_NAME = "gemini-2.5-flash"

        class GeminiClient:
            def __init__(self, api_key):
                self.api_key = api_key
            
            def process_audio(self, file_path):
                log(f"Processando arquivo: {file_path}")
                file_size = os.path.getsize(file_path)
                
                # Upload
                url_init = f"{API_URL}/upload/v1beta/files?key={self.api_key}"
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
                log("Upload para Google OK. Aguardando...")

                # Wait
                for _ in range(60):
                    r_get = requests.get(f"{API_URL}/v1beta/{r_up.json()['file']['name']}?key={self.api_key}")
                    if r_get.json().get("state") == "ACTIVE": break
                    if r_get.json().get("state") == "FAILED": raise Exception("Falha no processamento do Gemini")
                    time.sleep(1)
                
                # Generate
                log("Analisando Áudio...")
                prompt = 'Extraia JSON: {"soap":{"s":"","o":"","a":"","p":""}, "diagnostico":"", "medicamentos":[]}'
                gen_url = f"{API_URL}/v1beta/models/{MODEL_NAME}:generateContent?key={self.api_key}"
                payload = {
                    "contents": [{"parts": [{"text": prompt}, {"file_data": {"mime_type": "audio/wav", "file_uri": file_uri}}]}],
                    "generationConfig": {"response_mime_type": "application/json"}
                }
                r_gen = requests.post(gen_url, json=payload)
                r_gen.raise_for_status()
                return json.loads(r_gen.json()["candidates"][0]["content"]["parts"][0]["text"])

        # --- UI COMPONENTS ---
        api_key_field = ft.TextField(label="Cole sua Google API Key", password=True)
        results_area = ft.Column()

        # FILE PICKER REPLACEMENT
        def on_file_picked(e: ft.FilePickerResultEvent):
            if e.files:
                file_path = e.files[0].path
                log(f"Arquivo Selecionado: {file_path}")
                if not api_key_field.value:
                    log("ERRO: Preencha a API Key antes!", True)
                    return
                
                try:
                    client = GeminiClient(api_key_field.value)
                    data = client.process_audio(file_path)
                    
                    results_area.controls.clear()
                    results_area.controls.append(ft.Text(json.dumps(data, indent=2), font_family="Consolas"))
                    page.update()
                    log("Análise Concluída com Sucesso!")
                except Exception as ex:
                    log(f"Erro na IA: {ex}", True)

        file_picker = ft.FilePicker(on_result=on_file_picked)
        page.overlay.append(file_picker)
        
        btn_pick = ft.ElevatedButton(
            "Selecionar Áudio (WAV/MP3)", 
            icon=ft.Icons.UPLOAD_FILE, 
            bgcolor="blue", 
            color="white",
            on_click=lambda _: file_picker.pick_files(allow_multiple=False)
        )

        # Add to page
        page.add(
            ft.Divider(),
            api_key_field,
            btn_pick,
            ft.Divider(),
            ft.Text("Resultados:", weight="bold"),
            results_area
        )
        page.update()
        log("Sistema Pronto. Selecione um arquivo.")

    except Exception as e:
        err_msg = traceback.format_exc()
        log(f"ERRO FATAL:\n{err_msg}", True)

if __name__ == "__main__":
    ft.app(target=main)
