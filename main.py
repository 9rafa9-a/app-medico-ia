import flet as ft
import requests
import json
import os
import time
import sys
import io
import threading
from unidecode import unidecode

# --- DEBUG CONSOLE SYSTEM (Must be first) ---
# This class acts as a file-like object to intercept print/errors
class ConsoleBuffer:
    def __init__(self):
        self.listeners = []
        self.buffer = []

    def write(self, message):
        if not message: return
        self.buffer.append(message)
        for listener in self.listeners:
            listener(message)
        # Also print to real terminal for dev view
        sys.__stdout__.write(message)

    def flush(self):
        sys.__stdout__.flush()

    def add_listener(self, callback):
        self.listeners.append(callback)
        # Replay history
        for msg in self.buffer:
            callback(msg)

# Global buffer to catch early errors
debug_buffer = ConsoleBuffer()
sys.stdout = debug_buffer
sys.stderr = debug_buffer
print(" --- INICIANDO LOGGER DE DEBUG --- ")

# --- CONSTANTS ---
API_URL = "https://generativelanguage.googleapis.com"
MODEL_NAME = "gemini-2.5-flash"

# --- DATABASE LOGIC (Keep it simple and robust) ---
def load_json_safe(filename, key_extractor):
    try:
        base_dir = os.path.dirname(os.path.abspath(__file__))
        path = os.path.join(base_dir, "data", filename)
        if not os.path.exists(path):
            print(f"⚠️ Aviso: Arquivo {filename} não encontrado em {path}")
            return []
        
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            
        names = []
        if isinstance(data, list):
            for item in data:
                val = key_extractor(item)
                if val: names.append(str(val))
        return names
    except Exception as e:
        print(f"❌ Erro ao ler {filename}: {e}")
        return []

# Extractors
def ext_remume(i): return i.get('nome_completo', i.get('nome')) if isinstance(i, dict) else i
def ext_ac(i): return i.get('nome') if isinstance(i, dict) else i
def ext_rename(i):
    if isinstance(i, str): return i
    if isinstance(i, dict):
        if 'itens' in i and isinstance(i['itens'], list): return "GROUP_SKIP" # Complex, skip for now for safety
        return i.get('nome')

def normalize(text):
    if not text: return ""
    return unidecode(str(text)).lower().strip()

def check_meds(med_list):
    print("🔍 Iniciando verificação de medicamentos...")
    remume = load_json_safe("db_remume.json", ext_remume)
    ac = load_json_safe("db_alto_custo.json", ext_ac)
    rename = load_json_safe("db_rename.json", ext_rename) # Simplified for stability

    # Pre-process dbs
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
            # Loose match
            if any(med_norm in c or c in med_norm for c in contents if len(c) > 3):
                med_res["found"].append(db_name)
        
        results.append(med_res)
    print("✅ Verificação concluída.")
    return results

# --- GEMINI CLIENT (Requests) ---
class GeminiClient:
    def __init__(self, api_key):
        self.api_key = api_key
    
    def process_audio(self, file_path):
        print(f"📤 Iniciando upload para Gemini: {file_path}")
        file_size = os.path.getsize(file_path)
        
        # 1. Init Upload
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

        # 2. Send Bytes
        with open(file_path, "rb") as f:
            headers_up = {"Content-Length": str(file_size), "X-Goog-Upload-Offset": "0", "X-Goog-Upload-Command": "upload, finalize"}
            r_up = requests.post(upload_url, headers=headers_up, data=f)
            r_up.raise_for_status()
        
        file_uri = r_up.json()["file"]["uri"]
        file_name = r_up.json()["file"]["name"]
        print(f"✅ Upload concluído: {file_name}")

        # 3. Wait Processing
        print("⏳ Aguardando processamento do áudio...")
        for _ in range(60):
            r_get = requests.get(f"{API_URL}/v1beta/{file_name}?key={self.api_key}")
            state = r_get.json().get("state")
            if state == "ACTIVE": break
            if state == "FAILED": raise Exception("Gemini falhou ao processar áudio")
            time.sleep(1)
        
        # 4. Generate
        print("🧠 Gerando análise clínica...")
        prompt = """
        Você é um médico auditor. Ouça o áudio.
        Saída JSON Obrigatória:
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

# --- UI MAIN ---
def main(page: ft.Page):
    page.title = "Medico IA Debugger"
    page.scroll = "auto"
    page.theme_mode = "light"
    
    # --- DEBUG UI COMPONENT ---
    console_lv = ft.ListView(height=150, spacing=2, padding=10, auto_scroll=True)
    console_container = ft.Container(
        content=console_lv,
        bgcolor="#1e1e1e",
        border_radius=10,
        padding=10,
        visible=True # Always visible for safety
    )
    
    def log_to_ui(msg):
        # Clean newlines for UI
        clean_msg = msg.strip()
        if clean_msg:
            color = "red" if "Error" in msg or "Exception" in msg else "green"
            console_lv.controls.append(ft.Text(clean_msg, color=color, font_family="Consolas", size=12))
            try:
                page.update()
            except: pass # Initialization race condition
            
    # Connect global buffer to this UI
    debug_buffer.add_listener(log_to_ui)
    
    print("🖥️ UI Inicializada. Carregando componentes...")

    try:
        # --- APP STATE ---
        api_key_field = ft.TextField(label="Google API Key", password=True)
        btn_record = ft.ElevatedButton("Gravar", icon=ft.Icons.MIC, bgcolor="blue", color="white")
        btn_stop = ft.ElevatedButton("Parar", icon=ft.Icons.STOP, bgcolor="red", color="white", disabled=True)
        status_lbl = ft.Text("Pronto", size=16, weight="bold")
        results_area = ft.Column()

        # --- AUDIO RECORDER ---
        # Robust Import Strategy for Flet 0.25.2+
        try:
            import flet_audio_recorder
            AudioRecorder = flet_audio_recorder.AudioRecorder
            print("🎙️ Usando flet_audio_recorder externo.")
        except ImportError:
            # Fallback for older Flet or if integrated
            AudioRecorder = ft.AudioRecorder
            print("🎙️ Usando ft.AudioRecorder nativo.")

        rec = AudioRecorder(
            audio_encoder=ft.AudioEncoder.WAV,
            on_state_changed=lambda e: print(f"Audio Status: {e.data}")
        )
        page.overlay.append(rec)
        print("🎙️ Gravador de Áudio Registrado.")

        # --- EVENT HANDLERS ---
        def start_rec(e):
            if not api_key_field.value:
                print("⚠️ Falta API Key!")
                return
            
            # Check permissions
            print("Verificando permissões...")
            try:
                # Permission check logic usually async or tricky in Flet, 
                # just starting recording often triggers the dialog
                rec.start_recording("consulta.wav")
                btn_record.disabled = True
                btn_stop.disabled = False
                status_lbl.value = "Gravando..."
                page.update()
                print("▶️ Gravação iniciada.")
            except Exception as ex:
                print(f"❌ Erro ao iniciar gravação: {ex}")

        def stop_rec(e):
            print("⏹️ Parando gravação...")
            try:
                path = rec.stop_recording()
                btn_record.disabled = False
                btn_stop.disabled = True
                status_lbl.value = "Processando..."
                page.update()
                
                if path:
                    print(f"Arquivo gerado: {path}")
                    run_ai_pipeline(path)
                else:
                    print("❌ Nenhum arquivo de áudio gerado.")
            except Exception as ex:
                print(f"❌ Erro ao parar: {ex}")

        def run_ai_pipeline(path):
            try:
                client = GeminiClient(api_key_field.value)
                data = client.process_audio(path)
                
                # Render
                results_area.controls.clear()
                
                # SOAP
                if "soap" in data:
                    s = data["soap"]
                    results_area.controls.append(ft.Text("SOAP", size=20, weight="bold"))
                    results_area.controls.append(ft.Text(f"S: {s.get('s')}"))
                    results_area.controls.append(ft.Text(f"O: {s.get('o')}"))
                    results_area.controls.append(ft.Text(f"A: {s.get('a')}"))
                    results_area.controls.append(ft.Text(f"P: {s.get('p')}"))
                
                # Availability
                if "medicamentos" in data:
                    results_area.controls.append(ft.Divider())
                    check_res = check_meds(data["medicamentos"])
                    for item in check_res:
                        found_in = ", ".join(item["found"]) if item["found"] else "Indisponível"
                        color = "green" if item["found"] else "red"
                        results_area.controls.append(
                            ft.Container(
                                content=ft.Row([
                                    ft.Icon(ft.icons.MEDICATION, color=color),
                                    ft.Text(f"{item['name']} -> {found_in}", weight="bold")
                                ]),
                                bgcolor="#f0f0f0", padding=5, border_radius=5
                            )
                        )
                
                status_lbl.value = "Concluído com Sucesso"
                page.update()
                
            except Exception as ex:
                print(f"❌ Erro no Pipeline IA: {ex}")
                status_lbl.value = "Erro Fatal"
                page.update()

        # Bind events
        btn_record.on_click = start_rec
        btn_stop.on_click = stop_rec

        # Assemble UI
        page.add(
            ft.Text("Debug Console (Monitor de Erros)", size=12, weight="bold"),
            console_container,
            ft.Divider(),
            ft.Text("Assistente Médico v2.0", size=24, weight="bold"),
            api_key_field,
            ft.Row([btn_record, btn_stop]),
            status_lbl,
            ft.Divider(),
            results_area
        )
        print("✅ Interface Gráfica Montada.")

    except Exception as e:
        print(f"🔥 ERRO FATAL NA MAIN: {e}")
        # Ensure log takes visible space if fatal error
        console_container.height = 500
        page.update()

if __name__ == "__main__":
    ft.app(target=main)
