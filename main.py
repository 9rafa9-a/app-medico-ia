import flet as ft
import sys
import traceback

def main(page: ft.Page):
    # 1. SETUP UI SHELL
    page.title = "Medico IA - Bootloader"
    page.scroll = "auto"
    page.theme_mode = "light"

    log_lv = ft.ListView(height=300, spacing=2, padding=10, auto_scroll=True)
    log_container = ft.Container(
        content=log_lv,
        bgcolor="#111111",
        border_radius=10,
        padding=10,
        expand=True
    )
    
    page.add(
        ft.Text("Iniciando Sistema... v3.1 (Lazy Loader)", size=20, weight="bold", color="blue"),
        log_container
    )
    page.update()

    def log(msg, error=False):
        color = "red" if error else "green"
        icon = "❌" if error else "✅"
        log_lv.controls.append(ft.Text(f"{icon} {msg}", color=color, font_family="Consolas"))
        page.update()

    # 2. RUNTIME LOADING (Protected Block)
    try:
        # --- PHASE 1: IMPORTS ---
        log("Importando Bibliotecas...")
        import os
        import json
        import time
        import threading
        
        try:
            import requests
            log(f"Requests ok: {requests.__version__}")
        except ImportError as e:
            log(f"Falta Requests: {e}", True)

        try:
            from unidecode import unidecode
            log("Unidecode ok")
        except ImportError as e:
            log(f"Falta Unidecode: {e}", True)

        # --- PHASE 2: CONSTANTS & CLASSES ---
        log("Definindo Classes...")
        
        API_URL = "https://generativelanguage.googleapis.com"
        MODEL_NAME = "gemini-2.5-flash"

        class GeminiClient:
            def __init__(self, api_key):
                self.api_key = api_key
            
            def process_audio(self, file_path):
                log(f"Upload iniciado: {file_path}")
                file_size = os.path.getsize(file_path)
                
                # Upload Logic
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
                log("Upload OK. Processando...")

                # Wait
                for _ in range(60):
                    r_get = requests.get(f"{API_URL}/v1beta/{r_up.json()['file']['name']}?key={self.api_key}")
                    if r_get.json().get("state") == "ACTIVE": break
                    if r_get.json().get("state") == "FAILED": raise Exception("Falha Gemini")
                    time.sleep(1)
                
                # Generate
                log("Gerando IA...")
                prompt = 'Extraia JSON: {"soap":{"s":"","o":"","a":"","p":""}, "diagnostico":"", "medicamentos":[]}'
                gen_url = f"{API_URL}/v1beta/models/{MODEL_NAME}:generateContent?key={self.api_key}"
                payload = {
                    "contents": [{"parts": [{"text": prompt}, {"file_data": {"mime_type": "audio/wav", "file_uri": file_uri}}]}],
                    "generationConfig": {"response_mime_type": "application/json"}
                }
                r_gen = requests.post(gen_url, json=payload)
                r_gen.raise_for_status()
                return json.loads(r_gen.json()["candidates"][0]["content"]["parts"][0]["text"])

        # --- PHASE 3: DATABASE ---
        log("Carregando Databases (Simulado Check)...")
        # Included inline logic for safety
        def check_meds(med_list):
            return [{"name": m, "found": ["MockDB"]} for m in med_list]

        # --- PHASE 4: UI COMPONENTS ---
        log("Criando Interface...")
        
        api_key_field = ft.TextField(label="Google API Key", password=True)
        # Use simple icons for maximum compatibility (Strings, not Objects if possible, but Objects OK in 0.22.1)
        btn_record = ft.ElevatedButton("Gravar", icon=ft.icons.MIC, bgcolor="blue", color="white")
        btn_stop = ft.ElevatedButton("Parar", icon=ft.icons.STOP, bgcolor="red", color="white", disabled=True)
        status_lbl = ft.Text("Pronto", size=16, weight="bold")
        results_area = ft.Column()

        # --- PHASE 5: RECORDER ---
        log("Inicializando Gravador...")
        rec = ft.AudioRecorder(
            audio_encoder=ft.AudioEncoder.WAV,
            on_state_changed=lambda e: log(f"Audio Status: {e.data}")
        )
        page.overlay.append(rec)
        log("Gravador Pronto.")

        # --- LOGIC ---
        def start_rec(e):
            if not api_key_field.value:
                log("ERRO: Falta API Key", True)
                return
            try:
                rec.start_recording("consulta.wav")
                btn_record.disabled = True
                btn_stop.disabled = False
                status_lbl.value = "Gravando..."
                page.update()
            except Exception as ex:
                log(f"Erro Start: {ex}", True)

        def stop_rec(e):
            try:
                path = rec.stop_recording()
                btn_record.disabled = False
                btn_stop.disabled = True
                status_lbl.value = "Processando..."
                page.update()
                if path:
                    log(f"Arquivo: {path}")
                    try:
                        client = GeminiClient(api_key_field.value)
                        data = client.process_audio(path)
                        # Render Logic
                        results_area.controls.clear()
                        results_area.controls.append(ft.Text(str(data)))
                        page.update()
                    except Exception as ai_ex:
                        log(f"Erro IA: {ai_ex}", True)
            except Exception as ex:
                log(f"Erro Stop: {ex}", True)

        btn_record.on_click = start_rec
        btn_stop.on_click = stop_rec

        # Add to page
        page.add(
            ft.Divider(),
            ft.Text("App Carregado:", weight="bold"),
            api_key_field,
            ft.Row([btn_record, btn_stop]),
            status_lbl,
            results_area
        )
        page.update()
        log("SISTEMA PRONTO PARA USO.")

    except Exception as e:
        # CATCH-ALL FOR ANY LOADING ERROR
        err_msg = traceback.format_exc()
        log(f"ERRO FATAL NO LOAD:\n{err_msg}", True)
        print(err_msg)

if __name__ == "__main__":
    ft.app(target=main)
