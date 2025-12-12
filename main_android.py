import flet as ft
import sys

# ANDROID SAFE MODE
# Sem imports pesados (requests/unidecode) no topo
# Apenas Interface Nativa Pura para testar se o Flet carrega

def main(page: ft.Page):
    page.title = "Android Debug"
    page.bgcolor = "white"
    
    lbl_status = ft.Text("Inicializando Android...", color="black", size=20)
    
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

    page.add(
        ft.Column(
            [
                ft.Icon(ft.icons.ANDROID, size=50, color="green"),
                ft.Text("Se você vê isso, o APK funciona!", color="blue", size=25, weight="bold"),
                ft.Divider(),
                lbl_status,
                btn_load
            ],
            alignment="center",
            horizontal_alignment="center"
        )
    )

if __name__ == "__main__":
    ft.app(target=main)
