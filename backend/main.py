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

# --- CONFIGURAÇÃO ---
app = FastAPI(title="MedUBS Backend API v3.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Diretório para salvar os TXTs processados (RAG)
# Nota: No Render Free, isso apaga a cada deploy. Em produção real, usar S3/Supabase.
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
    debug_rag: Optional[str] = None

# --- FUNÇÕES AUXILIARES ---

def extract_text_from_bytes(file_bytes: bytes) -> str:
    """Extrai texto de PDF direto da memória RAM, sem salvar no disco."""
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
    # Palavras-chave relevantes (filtra preposições curtas)
    keywords = [w for w in query_norm.split() if len(w) > 4]

    for filename in os.listdir(kb_dir):
        if filename.endswith(".txt"):
            path = os.path.join(kb_dir, filename)
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    content_norm = unidecode(content.lower())
                    
                    # Score simples: contagem de palavras-chave
                    score = sum(content_norm.count(k) for k in keywords)
                    
                    if score > max_score:
                        max_score = score
                        best_match_content = content
                        best_file = filename
            except Exception:
                continue
    
    if max_score > 0:
        # Retorna os primeiros 5000 caracteres do protocolo mais relevante
        return f"--- INÍCIO PROTOCOLO ({best_file}) ---\n{best_match_content[:5000]}\n--- FIM PROTOCOLO ---"
    return ""

# --- ENDPOINTS ---

@app.get("/")
def read_root():
    return {"status": "online", "version": "3.0", "rag_files": len(os.listdir(KNOWLEDGE_BASE_DIR))}

@app.post("/upload-medicamento")
async def upload_medicamento(
    file: UploadFile = File(...), 
    nome_lista: str = Form(...),
    api_key: str = Form(...)
):
    """Gera JSON de medicamentos a partir de PDF."""
    try:
        content = await file.read()
        text = extract_text_from_bytes(content)
        
        if not text:
            raise HTTPException(status_code=400, detail="Não foi possível ler texto do PDF.")

        genai.configure(api_key=api_key)
        model = genai.GenerativeModel('gemini-1.5-flash') # 1.5 é mais rápido/barato que 2.0 para essa tarefa
        
        # Otimização: Pegar apenas as primeiras 30k chars para não estourar token
        # Em produção, implementaria chunking loop.
        text_sample = text[:30000]

        prompt = f"""
        Analise o texto extraído do documento "{nome_lista}".
        Extraia a lista de medicamentos disponíveis.
        Retorne JSON ARRAY puro: [{{ "nome": "MEDICAMENTO DOSAGEM", "lista_origem": "{nome_lista}", "data_importacao": "hoje" }}]
        
        TEXTO:
        {text_sample}
        """
        
        response = model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
        
        return json.loads(response.text)

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
    """Cérebro da aplicação: RAG + SOAP + Missões."""
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
            "medicamentos": ["Nome Genérico 1", "Nome Genérico 2"],
            "missoes": [
                {{ "tarefa": "Ação clínica obrigatória segundo protocolo", "categoria": "Exame/Prescrição/Orienta", "doenca": "Causa" }}
            ]
        }}
        """
        
        response = model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
        res_json = json.loads(response.text)
        
        return {
            "soap": res_json.get("soap", {}),
            "medicamentos": res_json.get("medicamentos", []),
            "missoes": res_json.get("missoes", []),
            "debug_rag": "Contexto usado: " + ("SIM" if rag_context else "NÃO")
        }

    except Exception as e:
        # Fallback de segurança para não travar o app
        return {
            "soap": {"s": "Erro ao processar", "o": "", "a": str(e), "p": ""}, 
            "medicamentos": [], 
            "missoes": [],
            "debug_rag": "ERRO"
        }

if __name__ == "__main__":
    import uvicorn
    # Configuração para rodar no Render (lê variável PORT) ou local (8000)
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
