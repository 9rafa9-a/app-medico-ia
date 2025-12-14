import flet as ft
import os

def main(page: ft.Page):
    print("DEBUG: Main App Started")
    page.bgcolor = "white"
    page.add(ft.SafeArea(ft.Text("DEBUG MODE: Flet 0.28.3", size=20, color="black")))
    page.add(ft.Text("Se você vê isso, o Flet 0.28 NÃO está crashando.", color="green"))

    # --- AUDIO TEST ---
    status_text = ft.Text("Aguardando...", color="black")
    
    def on_state_changed(e):
        print(f"Recorder State: {e.data}")
        status_text.value = f"Estado: {e.data}"
        page.update()

    # Note: Flet 0.28+ uses AudioRecorder directly
    try:
        audio_recorder = ft.AudioRecorder(
            on_state_changed=on_state_changed
        )
        page.overlay.append(audio_recorder)
        page.add(ft.Text("AudioRecorder Adicionado com sucesso.", size=12, color="blue"))
    except Exception as e:
        page.add(ft.Text(f"Erro ao criar Recorder: {e}", color="red"))

    def start_click(e):
        try:
            status_text.value = "Iniciando..."
            # output path?
            # On Android, just filename might save to cache/document?
            # Or use empty string to let OS decide?
            audio_recorder.start_recording("test_recording.wav")
            status_text.value = "Comando Start Enviado"
            page.update()
        except Exception as ex:
            status_text.value = f"Erro Start: {ex}"
            page.update()

    def stop_click(e):
        try:
            res = audio_recorder.stop_recording()
            status_text.value = f"Parado. Arquivo: {res}"
            page.update()
        except Exception as ex:
            status_text.value = f"Erro Stop: {ex}"
            page.update()

    page.add(
        ft.ElevatedButton("Gravar (Teste)", on_click=start_click),
        ft.ElevatedButton("Parar (Teste)", on_click=stop_click),
        status_text
    )

ft.app(target=main)
