from fastapi.testclient import TestClient
from main import app
import os

client = TestClient(app)

def test_read_root():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["status"] == "online"
    assert response.json()["version"] == "3.0"

def test_knowledge_base_dir_exists():
    assert os.path.exists("knowledge_base")
    assert os.path.isdir("knowledge_base")

print("✅ Testes Básicos de Infraestrutura (Backend) Passaram!")
print("Rode este teste com: pytest test_main.py")
