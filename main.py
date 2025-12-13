import sys
import traceback
import platform
import os

# --- SISTEMA DE LOG (Para o Logcat) ---
def log_console(msg):
    # Escreve no stderr para garantir que apareça no Logcat sem buffer
    print(f"[DIAGNOSTICO] {msg}", file=sys.stderr)

log_console("=== INICIANDO SCRIPT DE DIAGNOSTICO COMPLETO ===")

# Variáveis de estado
status_flet = "PENDENTE"
status_requests = "PENDENTE"
status_unidecode = "PENDENTE"
erro_critico = None

# --- 1. TENTATIVA DE IMPORTS ---
try:
    log_console("Importando Flet...")
    import flet as ft
    status_flet = "OK ✅"
except Exception as e:
    status_flet = f"ERRO ❌ ({e})"
    erro_critico = e
    log_console(f"FALHA NO FLET: {e}")

try:
    log_console("Importando Requests...")
    import requests
    status_requests = "OK ✅"
except Exception as e:
    status_requests = f"ERRO ❌ ({e})"
    log_console(f"FALHA NO REQUESTS: {e}")

try:
    log_console("Importando Unidecode...")
    from unidecode import unidecode
    status_unidecode = "OK ✅"
except Exception as e:
    status_unidecode = f"ERRO ❌ ({e})"
    log_console(f"FALHA NO UNIDECODE: {e}")

# --- 2. INTERFACE GRÁFICA (Se o Flet sobreviveu) ---
if erro_critico:
    log_console("!!! O APP VAI FECHAR PORQUE O FLET FALHOU !!!")
    raise erro_critico

def main(page: ft.Page):
    log_console("Entrou na função main()")
    
    page.title = "Diagnóstico Médico IA"
    page.scroll = ft.ScrollMode.ADAPTIVE
    page.bgcolor = ft.colors.BLACK
    page.padding = 20

    # Função para testar Internet
    def testar_internet(e):
        log_console("Botão Internet Clicado")
        status_text.value = "Testando conexão..."
        status_text.color = ft.colors.YELLOW
        page.update()
        
        try:
            r = requests.get("https://www.google.com", timeout=5)
            status_text.value = f"SUCESSO! Status Code: {r.status_code}"
            status_text.color = ft.colors.GREEN
            log_console("Internet OK")
        except Exception as ex:
            status_text.value = f"FALHA DE REDE: {ex}"
            status_text.color = ft.colors.RED
            log_console(f"Internet FALHA: {ex}")
        page.update()

    status_text = ft.Text("Clique abaixo para testar rede", color=ft.colors.WHITE)

    # Monta a tela de relatório
    try:
        page.add(
            ft.Column([
                ft.Text("RELATÓRIO DE SISTEMA", size=24, weight=ft.FontWeight.BOLD, color=ft.colors.CYAN),
                ft.Divider(color=ft.colors.GREY),
                
                ft.Text("1. Bibliotecas Python:", color=ft.colors.WHITE, weight=ft.FontWeight.BOLD),
                ft.Text(f"Flet: {status_flet}", color=ft.colors.GREEN if "OK" in status_flet else ft.colors.RED),
                ft.Text(f"Requests: {status_requests}", color=ft.colors.GREEN if "OK" in status_requests else ft.colors.RED),
                ft.Text(f"Unidecode: {status_unidecode}", color=ft.colors.GREEN if "OK" in status_unidecode else ft.colors.RED),
                
                ft.Divider(color=ft.colors.GREY),
                
                ft.Text("2. Ambiente Android:", color=ft.colors.WHITE, weight=ft.FontWeight.BOLD),
                ft.Text(f"Python: {platform.python_version()}", color=ft.colors.GREY_400),
                ft.Text(f"Sistema: {platform.system()} {platform.release()}", color=ft.colors.GREY_400),
                ft.Text(f"Arquitetura: {platform.machine()}", color=ft.colors.GREY_400),
                
                ft.Divider(color=ft.colors.GREY),
                
                ft.Text("3. Teste de Rede (Permissões):", color=ft.colors.WHITE, weight=ft.FontWeight.BOLD),
                status_text,
                ft.ElevatedButton("Testar Conexão Google", on_click=testar_internet),
                
                ft.Divider(color=ft.colors.GREY),
                ft.Container(height=20),
                ft.Text("Se tudo estiver verde acima, pode colocar seu código final!", color=ft.colors.GREEN_ACCENT, text_align=ft.TextAlign.CENTER)
            ])
        )
        page.update()
        log_console("Interface desenhada com sucesso.")
        
    except Exception as e:
        log_console(f"Erro ao desenhar tela: {e}")
        page.add(ft.Text(f"Erro fatal na UI: {e}", color=ft.colors.RED))

# --- 3. EXECUÇÃO ---
try:
    log_console("Chamando ft.app()...")
    ft.app(target=main)
except Exception as e:
    log_console(f"CRASH FATAL NO ARRANQUE: {e}")
    traceback.print_exc()
