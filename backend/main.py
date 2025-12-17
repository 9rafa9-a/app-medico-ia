import os
import io
import json
import shutil
from typing import List, Optional
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import pdfplumber
import google.generativeai as genai
from unidecode import unidecode

# Novos Módulos
import db_manager
import parser_core

# --- CONFIGURAÇÃO ---
app = FastAPI(title="MedUBS Backend API v4.0 (Hybrid)")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Inicializa Banco
@app.on_event("startup")
def on_startup():
    db_manager.init_db()

# Diretório para salvar os TXTs processados (RAG)
KNOWLEDGE_BASE_DIR = "knowledge_base"
os.makedirs(KNOWLEDGE_BASE_DIR, exist_ok=True)

# --- MODELOS ---
class ConsultaRequest(BaseModel):
    transcricao: str
    api_key: str
    model: Optional[str] = "gemini-1.5-flash"

class ConsultaResponse(BaseModel):
    soap: dict
    medicamentos: List[str]
    missoes: List[dict]
    paciente: dict
    keywords: List[str] # Novo
    debug_rag: Optional[str] = None
import time
from google.api_core import exceptions as google_exceptions

# --- FUNÇÕES AUXILIARES ---

def generate_with_retry(model, prompt, retries=3, response_mime_type="application/json"):
    """
    Wrapper para chamar model.generate_content com Retry Strategy (Backoff Exponencial).
    Trata erros 429 (ResourceExhausted) aguardando antes de tentar de novo.
    """
    base_delay = 5
    for attempt in range(retries):
        try:
            return model.generate_content(prompt, generation_config={"response_mime_type": response_mime_type})
        except google_exceptions.ResourceExhausted as e:
            wait_time = base_delay * (2 ** attempt) # 5s, 10s, 20s...
            print(f"⚠️ Quota Exceeded (429). Retrying in {wait_time}s... (Attempt {attempt+1}/{retries})")
            time.sleep(wait_time)
        except Exception as e:
            # Outros erros (400, 500, etc) não adianta tentar de novo imediatamente
            print(f"❌ Erro API Gemini: {e}")
            raise e
            
    raise Exception("Falha após múltiplas tentativas (Quota Exceeded)")

def extract_text_from_bytes(file_bytes: bytes) -> str:
    """Extrai texto de PDF direto da memória RAM."""
    text = ""
    try:
        with pdfplumber.open(io.BytesIO(file_bytes)) as pdf:
            for page in pdf.pages:
                extracted = page.extract_text(layout=True)
                if extracted:
                    text += extracted + "\n"
    except Exception as e:
        print(f"Erro ao ler PDF: {e}")
        return ""
    return text

def simple_rag_search(query: str, kb_dir: str) -> str:
    """Busca contexto nos arquivos TXT salvos."""
    if not os.path.exists(kb_dir) or not os.listdir(kb_dir):
        return ""

    best_match_content = ""
    max_score = 0
    best_file = ""

    query_norm = unidecode(query.lower())
    keywords = [w for w in query_norm.split() if len(w) > 4]

    for filename in os.listdir(kb_dir):
        if filename.endswith(".txt"):
            path = os.path.join(kb_dir, filename)
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    content_norm = unidecode(content.lower())
                    score = sum(content_norm.count(k) for k in keywords)
                    
                    if score > max_score:
                        max_score = score
                        best_match_content = content
                        best_file = filename
            except Exception:
                continue
    
    if max_score > 0:
        return f"--- INÍCIO PROTOCOLO ({best_file}) ---\n{best_match_content[:5000]}\n--- FIM PROTOCOLO ---"
    return ""

# --- ENDPOINTS ---

@app.get("/")
def read_root():
    return {"status": "online", "version": "4.1 Retry-Enabled", "rag_files": len(os.listdir(KNOWLEDGE_BASE_DIR))}

@app.post("/upload-medicamento")
async def upload_medicamento(
    file: UploadFile = File(...), 
    nome_lista: str = Form(...),
    api_key: str = Form(...),
    model: str = Form(...),
    force_ai: str = Form("false")
):
    from fastapi.responses import StreamingResponse
    import json
    import time

    async def process_stream():
        try:
            content = await file.read()
            yield json.dumps({"status": "progress", "msg": "Arquivo recebido. Analisando estrutura..."}) + "\n"
            
            # 0. Instancia Parser
            parser = parser_core.HeuristicParser()
            
            # 1. Extração Otimizada (Python)
            opt_text = parser.extract_optimized_context(content)
            
            # 2. Validação: É imagem?
            if len(opt_text) < 100 and force_ai.lower() != "true":
                yield json.dumps({
                    "status": "heuristic_failed",
                    "debug": {"msg": "Pouco texto encontrado (vazio ou imagem). Requer OCR/Vision."}
                }) + "\n"
                return

            # 3. Preparação IA
            if not opt_text and force_ai.lower() == "true":
                 try:
                    opt_text = extract_text_from_bytes(content)
                 except: 
                    pass
                 if not opt_text: 
                     yield json.dumps({"status": "error", "msg": "PDF totalmente ilegível."}) + "\n"
                     return

            genai.configure(api_key=api_key)
            model_name = model if model else "gemini-1.5-flash"
            ai_model = genai.GenerativeModel(model_name)
            
            aggregated_meds = []
            
            # 4. Lógica Dinâmica
            SAFE_LIMIT = 30000 
            
            if len(opt_text) <= SAFE_LIMIT:
                # --- SINGLE SHOT ---
                yield json.dumps({"status": "progress", "msg": "Envio único (Texto curto). Processando com IA..."}) + "\n"
                
                prompt = f"""
                Analise o contexto abaixo (Tabelas e Texto extraídos de "{nome_lista}").
                Identifique todos os medicamentos.
                Retorne JSON ARRAY puro: [{{ "nome": "MEDICAMENTO", "concentracao": "500MG", "forma": "CP", "lista_origem": "{nome_lista}", "data_importacao": "hoje" }}]
                
                CONTEXTO OTIMIZADO:
                {opt_text}
                """
                try:
                    response = generate_with_retry(ai_model, prompt)
                    parsed = json.loads(response.text)
                    if isinstance(parsed, list): aggregated_meds = parsed
                    elif isinstance(parsed, dict): aggregated_meds = parsed.get('medicamentos', [])
                    yield json.dumps({"status": "progress", "msg": "IA processou e enviou dados."}) + "\n"
                except Exception as e:
                    yield json.dumps({"status": "log", "msg": f"Erro Single Shot: {e}"}) + "\n"
                    
            else:
                # --- CHUNKING ---
                chunk_size = 25000 
                total_chunks = (len(opt_text) // chunk_size) + 1
                max_chunks = 6 
                if total_chunks > max_chunks: total_chunks = max_chunks
                
                yield json.dumps({"status": "start_chunks", "total": total_chunks, "msg": f"Iniciando processamento em {total_chunks} partes."}) + "\n"
                
                for i in range(total_chunks):
                    # Progress Update
                    yield json.dumps({
                        "status": "progress", 
                        "current": i + 1, 
                        "total": total_chunks,
                        "msg": f"Dando upload no render, render mandou pra IA {i+1}/{total_chunks}"
                    }) + "\n"

                    start = i * chunk_size
                    end = start + chunk_size
                    chunk = opt_text[start:end]
                    
                    prompt = f"""
                    Analise este trecho ({i+1}/{total_chunks}) de "{nome_lista}".
                    Extraia medicamentos. Retorne JSON ARRAY puro.
                    
                    TRECHO:
                    {chunk}
                    """
                    try:
                        response = generate_with_retry(ai_model, prompt)
                        parsed = json.loads(response.text)
                        batch = []
                        if isinstance(parsed, list): batch = parsed
                        elif isinstance(parsed, dict): batch = parsed.get('medicamentos', [])
                        aggregated_meds.extend(batch)
                        
                        yield json.dumps({
                            "status": "progress", 
                            "msg": f"IA processou {i+1} e enviou {i+1}."
                        }) + "\n"
                        
                        # DELAY DE 25 SEGUNDOS
                        if i < total_chunks - 1:
                            yield json.dumps({"status": "waiting", "seconds": 25, "msg": "Aguardando 25s para rate limit..."}) + "\n"
                            time.sleep(25) 
                        
                    except Exception as e:
                       yield json.dumps({"status": "log", "msg": f"Erro no chunk {i}: {str(e)}"}) + "\n"
                       continue

            # 5. Salva no Banco e Retorna
            if aggregated_meds:
                for item in aggregated_meds:
                    nome = item.get('nome', 'DESCONHECIDO')
                    conc = item.get('concentracao', '')
                    forma = item.get('forma', '')
                    db_manager.upsert_medicamento(nome, conc, forma, nome_lista, nome_lista)

                final_response = {
                    "status": "success",
                    "method": "ai_optimized_retry_stream",
                    "data": aggregated_meds,
                    "debug": {
                        "text_len": len(opt_text),
                        "mode": "Stream"
                    }
                }
                yield json.dumps(final_response) + "\n"
            else:
                yield json.dumps({
                    "status": "success", 
                    "data": [],
                    "debug": {"msg": "AI não encontrou itens."}
                }) + "\n"

        except Exception as e:
            yield json.dumps({"status": "error", "detail": str(e)}) + "\n"

    return StreamingResponse(process_stream(), media_type="application/x-ndjson")

@app.post("/upload-diretriz")
async def upload_diretriz(
    file: UploadFile = File(...),
    api_key: str = Form(...)
):
    """Salva texto de PCDT para consulta futura (RAG)."""
    try:
        content = await file.read()
        text = extract_text_from_bytes(content)
        
        if len(text) < 100:
            raise HTTPException(status_code=400, detail="PDF parece vazio ou é imagem (precisa de OCR).")
        
        kb_filename = f"{os.path.splitext(file.filename)[0]}.txt"
        kb_path = os.path.join(KNOWLEDGE_BASE_DIR, kb_filename)
        
        with open(kb_path, "w", encoding='utf-8') as f:
            f.write(text)
            
        return {"status": "success", "file": kb_filename, "chars_saved": len(text)}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/consultar-ia")
async def consultar_ia(req: ConsultaRequest):
    """Cérebro da aplicação: RAG + SOAP + Missões + Keywords."""
    try:
        # 1. RAG
        rag_context = simple_rag_search(req.transcricao, KNOWLEDGE_BASE_DIR)
        
        # 2. Gemini
        genai.configure(api_key=req.api_key)
        model_name = req.model if req.model else "gemini-1.5-flash"
        model = genai.GenerativeModel(model_name)
        
        prompt = f"""
        Atue como Médico Auditor e Preceptor de Residência.
        Analise a transcrição.
        
        {rag_context if rag_context else "Nenhum protocolo específico encontrado na base local. Use conhecimento padrão do Ministério da Saúde."}
        
        TRANSCRIÇÃO:
        "{req.transcricao}"
        
        Gere JSON estrito:
        {{
            "soap": {{ "s": "Resumo Subjetivo", "o": "Objetivo", "a": "Avaliação/Diagnóstico", "p": "Plano/Conduta" }},
            "paciente": {{ "sexo": "Masculino/Feminino", "idade": 0 }},
            "medicamentos": ["Nome Genérico 1", "Nome Genérico 2"],
            "keywords": ["Termo Clinico 1", "Termo Clinico 2"],
            "missoes": [
                {{ "tarefa": "Ação clínica obrigatória segundo protocolo", "categoria": "Exame/Prescrição/Orienta", "doenca": "Causa" }}
            ]
        }}
        """
        
        # USA RETRY AQUI TAMBÉM
        response = generate_with_retry(model, prompt)
        res_json = json.loads(response.text)
        
        return {
            "soap": res_json.get("soap", {}),
            "paciente": res_json.get("paciente", {}),
            "medicamentos": res_json.get("medicamentos", []),
            "keywords": res_json.get("keywords", []), 
            "missoes": res_json.get("missoes", []),
            "debug_rag": "Contexto usado: " + ("SIM" if rag_context else "NÃO")
        }

    except Exception as e:
        # Retorna erro legível no card em vez do JSON de crash
        err_msg = str(e)
        if "Quota" in err_msg or "429" in err_msg:
             err_msg = "⚠️ Limite de cota atingido (Erro 429). Aguarde alguns instantes e tente novamente."
             
        return {
            "soap": {"s": "Erro ao processar", "o": "", "a": err_msg, "p": ""}, 
            "medicamentos": [], 
            "missoes": [],
            "keywords": [],
            "paciente": {},
            "debug_rag": "ERRO"
        }

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
