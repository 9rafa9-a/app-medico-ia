import sys
import os
import traceback
import platform

# --- 1. CONFIGURAÇÃO DE LOG (A CAIXA PRETA) ---
# Redireciona tudo para garantir que apareça no Logcat
def log(message):
    print(f"[DIAGNOSTICO] {message}")
    sys.stdout.flush()

log("=== INÍCIO DO DIAGNÓSTICO DE BOOT ===")

# --- 2. INVESTIGAÇÃO DO AMBIENTE (CSI) ---
try:
    log(f"1. Sistema Operacional: {platform.system()} {platform.release()}")
    log(f"2. Arquitetura do Processador: {platform.machine()} (Isso define se libpyjni vai rodar)")
    log(f"3. Versão do Python: {sys.version}")
    log(f"4. Diretório Atual (CWD): {os.getcwd()}")
    
    # Lista arquivos locais para garantir que o Flet copiou tudo
    log("5. Arquivos na pasta do app:")
    try:
        files = os.listdir('.')
        log(f"   -> {files}")
    except Exception as e:
        log(f"   -> Erro ao listar arquivos: {e}")

    # Verifica onde o Python está procurando bibliotecas
    log("6. Python Path (sys.path):")
    for p in sys.path:
        log(f"   -> {p}")

except Exception as e:
    log(f"ERRO DURANTE O DIAGNÓSTICO: {e}")

# --- 3. TESTE DE DEPENDÊNCIAS (IMPORTAÇÃO SEGURA) ---
log("=== INICIANDO IMPORTAÇÃO DE BIBLIOTECAS ===")

ft = None
try:
    log("Tentando importar 'flet'...")
    import flet as ft
    log(f"SUCESSO: Flet importado. Versão: {ft.version if hasattr(ft, 'version') else 'Desconhecida'}")
except ImportError as e:
    log(f"ERRO FATAL: Falha ao importar Flet. O app não vai abrir. Detalhes: {e}")
    # Sem Flet, não tem UI. O script vai morrer aqui e veremos no log.
    raise e
except Exception as e:
    log(f"ERRO GENÉRICO NO FLET: {e}")
    raise e

try:
    log("Tentando importar 'requests'...")
    import requests
    log("SUCESSO: Requests importado.")
except ImportError as e:
    log(f"ERRO CRÍTICO: Requests não encontrado. Verifique requirements.txt. Detalhes: {e}")
except Exception as e:
    log(f"ERRO AO IMPORTAR REQUESTS: {e}")

try:
    log("Tentando importar 'unidecode'...")
    from unidecode import unidecode
    log("SUCESSO: Unidecode importado.")
except Exception as e:
    log(f"AVISO: Unidecode falhou ({e}). O app pode rodar, mas vai quebrar na lógica.")

# --- 4. APLICAÇÃO PRINCIPAL (PROTEGIDA) ---
log("=== INICIANDO INTERFACE GRÁFICA ===")

def main(page: ft.Page):
    log(">>> FUNÇÃO MAIN CHAMADA PELO FLET <<<")
    
    # Tratamento de erro DENTRO da UI para mostrar na tela se possível
    try:
        page.title = "Diagnóstico Inicial"
        page.scroll = "adaptive"
        page.bgcolor = ft.colors.BLACK
        
        log("Criando elementos visuais...")
        
        msg_sucesso = ft.Column([
            ft.Icon(ft.icons.CHECK_CIRCLE, color=ft.colors.GREEN, size=50),
            ft.Text("O SISTEMA ESTÁ OPERACIONAL", size=20, color=ft.colors.GREEN, weight=ft.FontWeight.BOLD),
            ft.Text(f"Arquitetura: {platform.machine()}", color=ft.colors.WHITE),
            ft.Text(f"Python: {platform.python_version()}", color=ft.colors.WHITE),
            ft.Divider(color=ft.colors.GREY),
            ft.Text("Se você vê isso, o problema de 'libpyjni' e 'import' foi resolvido.", color=ft.colors.WHITE),
            ft.ElevatedButton("Testar Request (Google)", on_click=lambda _: test_request(page))
        ])
        
        page.add(msg_sucesso)
        page.update()
        log("Interface atualizada com sucesso.")

    except Exception as e:
        log(f"ERRO DENTRO DO MAIN: {e}")
        traceback.print_exc()
        page.add(ft.Text(f"Erro de UI: {e}", color=ft.colors.RED, size=20))

def test_request(page):
    try:
        import requests
        r = requests.get("https://www.google.com")
        page.add(ft.Text(f"Teste de Rede: Status {r.status_code}", color=ft.colors.YELLOW))
    except Exception as e:
        page.add(ft.Text(f"Erro de Rede: {e}", color=ft.colors.RED))
    page.update()

# --- 5. LANÇAMENTO ---
try:
    log("Chamando ft.app(target=main)...")
    ft.app(target=main)
    log("=== FLET APP ENCERRADO NORMALMENTE ===")
except Exception as e:
    log("!!! CRASH FATAL NO ARRANQUE DO FLET !!!")
    log(f"Erro: {str(e)}")
    log("Traceback completo:")
    for line in traceback.format_exc().splitlines():
        log(line)
