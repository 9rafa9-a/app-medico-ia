import sys
import time

def gritar(msg):
    print(f"--- [DEGRES] {msg} ---", file=sys.stderr, flush=True)

gritar("1. O PYTHON INICIOU. VAMOS SUBIR A ESCADA.")

try:
    gritar("2. TENTANDO IMPORTAR 'os' e 'platform' (Nativas)...")
    import os
    import platform
    gritar(f"   -> SUCESSO! Sistema: {platform.machine()}")
except Exception as e:
    gritar(f"   -> MORREU NO BASICO: {e}")

try:
    gritar("3. TENTANDO IMPORTAR 'requests' (Biblioteca Externa)...")
    import requests
    gritar("   -> SUCESSO! Requests carregou.")
except Exception as e:
    gritar(f"   -> MORREU NO REQUESTS: {e}")

try:
    gritar("4. TENTANDO IMPORTAR 'flet' (O Suspeito Principal)...")
    import flet as ft
    gritar("   -> SUCESSO! Flet carregou (Milagre!).")
except Exception as e:
    gritar(f"   -> MORREU NO FLET: {e}")

gritar("5. FIM DA ESCADA. SE CHEGOU AQUI, O ERRO É NA UI.")

# Mantém o app vivo para dar tempo do log sair
while True:
    time.sleep(1)
