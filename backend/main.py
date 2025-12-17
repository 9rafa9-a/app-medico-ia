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

# --- FUNÇÕES AUXILIARES ---

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
    return {"status": "online", "version": "4.0 Hybrid", "rag_files": len(os.listdir(KNOWLEDGE_BASE_DIR))}

@app.post("/upload-medicamento")
async def upload_medicamento(
    file: UploadFile = File(...), 
    nome_lista: str = Form(...),
    api_key: str = Form(...),
    model: str = Form(...),
    force_ai: str = Form("false") # Novo flag (string "true"/"false")
):
    """
    Gera JSON de medicamentos.
    ESTRATÉGIA NOVA: Otimização Python -> IA
    1. Python limpa tabelas e texto.
    2. Se texto pequeno (< 100), falha e pede IA Forçada.
    3. Se texto OK, envia para IA.
       - Se < 30k chars: Envio único (Mais rápido / Melhor contexto).
       - Se > 30k chars: Fatoração (Segurança contra output limit).
    """
    try:
        content = await file.read()
        
        # 0. Instancia Parser
        parser = parser_core.HeuristicParser()
        
        # 1. Extração Otimizada (Python)
        opt_text = parser.extract_optimized_context(content)
        
        # 2. Validação: É imagem?
        # Se force_ai for false e não achou nada, rejeita.
        if len(opt_text) < 100 and force_ai.lower() != "true":
            return {
                "status": "heuristic_failed",
                "debug": {"msg": "Pouco texto encontrado (vazio ou imagem). Requer OCR/Vision."}
            }
            
        # 3. Preparação IA
        if not opt_text and force_ai.lower() == "true":
             # Fallback extremo: Se o parser otimizado falhou totalmente mas o user forçou,
             # tentamos o 'extract_text' puro do pdfplumber (talvez pegue lixo mas pega algo)
             opt_text = extract_text_from_bytes(content)
             if not opt_text: raise HTTPException(status_code=400, detail="PDF totalmente ilegível.")

        genai.configure(api_key=api_key)
        model_name = model if model else "gemini-1.5-flash"
        ai_model = genai.GenerativeModel(model_name)
        
        aggregated_meds = []
        chunks_processed = 0
        
        # 4. Lógica Dinâmica ("Safety Valve")
        # Limite seguro para output JSON grande: ~30k caracteres de input costuma gerar outputs seguros
        SAFE_LIMIT = 30000 
        
        if len(opt_text) <= SAFE_LIMIT:
            # --- SINGLE SHOT (Otimizado) ---
            chunks_processed = 1
            prompt = f"""
            Analise o contexto abaixo (Tabelas e Texto extraídos de "{nome_lista}").
            Identifique todos os medicamentos.
            Retorne JSON ARRAY puro: [{{ "nome": "MEDICAMENTO", "concentracao": "500MG", "forma": "CP", "lista_origem": "{nome_lista}", "data_importacao": "hoje" }}]
            
            CONTEXTO OTIMIZADO:
            {opt_text}
            """
            try:
                response = ai_model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
                parsed = json.loads(response.text)
                if isinstance(parsed, list): aggregated_meds = parsed
                elif isinstance(parsed, dict): aggregated_meds = parsed.get('medicamentos', [])
            except Exception as e:
                print(f"Erro Single Shot: {e}")
                
        else:
            # --- CHUNKING (Segurança para Docs Gigantes) ---
            chunk_size = 25000 # Um pouco menor que o limite para garantir
            total_chunks = (len(opt_text) // chunk_size) + 1
            max_chunks = 6 # Aumentei um pouco pois agora o texto é "denso" (só info util)
            if total_chunks > max_chunks: total_chunks = max_chunks
            
            for i in range(total_chunks):
                chunks_processed += 1
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
                    response = ai_model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
                    parsed = json.loads(response.text)
                    batch = []
                    if isinstance(parsed, list): batch = parsed
                    elif isinstance(parsed, dict): batch = parsed.get('medicamentos', [])
                    aggregated_meds.extend(batch)
                except: continue

        # 5. Salva no Banco e Retorna
        if aggregated_meds:
            for item in aggregated_meds:
                nome = item.get('nome', 'DESCONHECIDO')
                conc = item.get('concentracao', '')
                forma = item.get('forma', '')
                db_manager.upsert_medicamento(nome, conc, forma, nome_lista, nome_lista)

            return {
                "status": "success",
                "method": "ai_optimized",
                "data": aggregated_meds,
                "debug": {
                    "text_len": len(opt_text),
                    "chunks_processed": chunks_processed,
                    "mode": "Single Shot" if len(opt_text) <= SAFE_LIMIT else "Safety Chunking"
                }
            }
        else:
            return {
                "status": "success", # Retorna sucesso mas vazio, pra não travar loop
                "data": [],
                "debug": {"msg": "AI não encontrou itens"}
            }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

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
        
        response = model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
        res_json = json.loads(response.text)
        
        return {
            "soap": res_json.get("soap", {}),
            "paciente": res_json.get("paciente", {}),
            "medicamentos": res_json.get("medicamentos", []),
            "keywords": res_json.get("keywords", []), # Novo
            "missoes": res_json.get("missoes", []),
            "debug_rag": "Contexto usado: " + ("SIM" if rag_context else "NÃO")
        }

    except Exception as e:
        return {
            "soap": {"s": "Erro ao processar", "o": "", "a": str(e), "p": ""}, 
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
