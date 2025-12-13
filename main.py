import sys

# 1. Tenta escrever no STDOUT forçando o envio imediato (flush)
print("--- [STDOUT] O CODIGO MAIN.PY ESTA RODANDO ---", flush=True)

# 2. Escreve no STDERR (Isso aparece em vermelho e não tem buffer)
print("--- [STDERR] O CODIGO MAIN.PY ESTA RODANDO ---", file=sys.stderr)

# 3. Cria um arquivo físico no celular para provar que rodou (Auditoria de arquivo)
try:
    with open("prova_de_vida.txt", "w") as f:
        f.write("Eu estive aqui.")
    print("--- [STDERR] ARQUIVO CRIADO COM SUCESSO ---", file=sys.stderr)
except Exception as e:
    print(f"--- [STDERR] ERRO AO CRIAR ARQUIVO: {e} ---", file=sys.stderr)

# 4. O Kamikaze: Força um erro para gerar um Traceback no log
raise Exception("SUCESSO!!! O APP TRAVOU PROPOSITALMENTE AQUI.")
