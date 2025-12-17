import sqlite3
import os

# Caminho do Banco (o mesmo usado pelo Flutter? Não, o Backend roda no servidor Render)
# O Flutter tem seu proprio banco SQLite local (sqflite).
# O Backend terá o SEU banco para "aprender" ou para manter cache.
# O user pediu para criar/conectar ao banco `sus_medicamentos.db`.
DB_PATH = "sus_medicamentos.db"

def get_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_connection()
    c = conn.cursor()
    
    # Tabela Principal
    c.execute('''
        CREATE TABLE IF NOT EXISTS medicamentos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nome TEXT NOT NULL,
            concentracao TEXT,
            forma TEXT,
            origem_arquivo TEXT,
            disp_rename INTEGER DEFAULT 0,
            disp_estadual INTEGER DEFAULT 0,
            disp_remume INTEGER DEFAULT 0
        )
    ''')
    
    # Índice Único para Upsert
    try:
        c.execute('CREATE UNIQUE INDEX idx_med_unique ON medicamentos (nome, concentracao, forma)')
    except sqlite3.OperationalError:
        pass # Já existe
        
    conn.commit()
    conn.close()

def upsert_medicamento(nome: str, concentracao: str, forma: str, origem_arquivo: str, tipo_lista: str):
    """
    Inserts or Updates a medication.
    tipo_lista: 'remume', 'rename', 'estadual'
    """
    conn = get_connection()
    c = conn.cursor()
    
    # Sanitiza flags
    is_remume = 1 if 'remume' in tipo_lista.lower() else 0
    is_rename = 1 if 'rename' in tipo_lista.lower() else 0
    is_estadual = 1 if 'estadual' in tipo_lista.lower() else 0
    
    try:
        # Tenta Inserir
        c.execute('''
            INSERT INTO medicamentos (nome, concentracao, forma, origem_arquivo, disp_remume, disp_rename, disp_estadual)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (nome, concentracao, forma, origem_arquivo, is_remume, is_rename, is_estadual))
        return "INSERT"
        
    except sqlite3.IntegrityError:
        # Já existe -> Update (Merge flags)
        # Monta query dinâmica para atualizar apenas as flags que são 1
        updates = []
        if is_remume: updates.append("disp_remume = 1")
        if is_rename: updates.append("disp_rename = 1")
        if is_estadual: updates.append("disp_estadual = 1")
        
        if updates:
            sql = f"UPDATE medicamentos SET {', '.join(updates)} WHERE nome=? AND concentracao=? AND forma=?"
            c.execute(sql, (nome, concentracao, forma))
            return "UPDATE"
            
    finally:
        conn.commit()
        conn.close()
    return "SKIP"
