import flet as ft
import os
import sys

# --- CORREÇÃO 1: Definir o diretório base (Para Android/PC) ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

def main(page: ft.Page):
    print(">>> INICIANDO O APP (Main Wrapper)...")
    page.title = "App Médico IA"
    page.bgcolor = "white"

    # --- CORREÇÃO 2: Try/Catch Geral (Salva-Vidas) ---
    try:
        # --- CÓDIGO DA APLICAÇÃO (ORIGINAL/DEBUG) ---
        
        lbl_status = ft.Text("Inicializando Sistema...", color="black", size=20)
        
        def on_load_click(e):
            try:
                lbl_status.value = "Carregando Requests..."
                page.update()
                import requests
                lbl_status.value = f"Requests OK: {requests.__version__}"
                lbl_status.color = "green"
                page.update()
            except Exception as ex:
                lbl_status.value = f"Erro Requests: {ex}"
                lbl_status.color = "red"
                page.update()

        btn_load = ft.ElevatedButton("Testar Dependências", on_click=on_load_click)

        # Exemplo de uso do BASE_DIR (Se tivéssemos assets)
        # img_path = os.path.join(BASE_DIR, "assets", "logo.png")
        
        page.add(
            ft.Column(
                [
                    ft.Icon(ft.icons.ANDROID, size=50, color="green"),
                    ft.Text("App Carregado com Sucesso!", color="blue", size=25, weight="bold"),
                    ft.Text(f"Diretório Base: {BASE_DIR}", size=12, color="grey"),
                    ft.Divider(),
                    lbl_status,
                    btn_load,
                    ft.Text("Se você está lendo isso, o try/catch funcionou e o app não crashou.", color="green")
                ],
                alignment="center",
                horizontal_alignment="center"
            )
        )
        
        print(">>> APP CARREGADO COM SUCESSO")

    except Exception as e:
        # --- TELA VERMELHA DA MORTE (Mas amigável) ---
        print(f">>> ERRO FATAL: {e}")
        page.clean()
        page.add(
            ft.Column(
                [
                    ft.Icon(ft.icons.ERROR_OUTLINE, size=50, color="red"),
                    ft.Text("ERRO FATAL NO APP", color="red", size=30, weight="bold"),
                    ft.Divider(),
                    ft.Text(f"Ocorreu um erro que impediu o carregamento:", size=16),
                    ft.Container(
                        content=ft.Text(str(e), color="white", font_family="monospace"),
                        bgcolor="red",
                        padding=10,
                        border_radius=5
                    ),
                    ft.Text(f"Local: {BASE_DIR}", size=12, color="grey")
                ],
                alignment="center",
                horizontal_alignment="center"
            )
        )
        page.update()

if __name__ == "__main__":
    ft.app(target=main)
