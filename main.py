import flet as ft
import sys
import os

def main(page: ft.Page):
    page.title = "Teste de Vida"
    page.scroll = "auto"
    
    # Header
    page.add(ft.Text("TESTE DE VIDA DO APP", size=30, weight="bold", color="blue"))
    page.add(ft.Text(f"Python Version: {sys.version}", size=12))
    
    # Check Dependencies
    def check_dep(name):
        try:
            mod = __import__(name)
            return ft.Text(f"✅ {name}: OK ({getattr(mod, '__version__', 'v?')})", color="green", size=20)
        except ImportError as e:
            return ft.Text(f"❌ {name}: FALTOU ({e})", color="red", size=20, weight="bold")
        except Exception as e:
            return ft.Text(f"⚠️ {name}: ERRO ({e})", color="orange", size=20)

    page.add(ft.Divider())
    page.add(ft.Text("Checando Dependências:", size=16, weight="bold"))
    page.add(check_dep("requests"))
    page.add(check_dep("unidecode"))
    page.add(check_dep("json"))
    
    # Check Audio Recorder Availability (Safety Check)
    page.add(ft.Divider())
    try:
        rec = ft.AudioRecorder()
        page.add(ft.Text("✅ ft.AudioRecorder: Instanciado!", color="green"))
    except Exception as e:
        page.add(ft.Text(f"❌ ft.AudioRecorder: ERRO ({e})", color="red"))

    page.update()

if __name__ == "__main__":
    ft.app(target=main)
