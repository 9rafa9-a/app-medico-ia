import json
import re
import sys

def analyze():
    try:
        with open("data/db_rename.json", "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"Erro ao ler arquivo: {e}")
        return

    issues = []
    
    # helper to flatten if needed, but structure seems to be list of groups with 'itens'
    all_items = []
    if isinstance(data, list):
        for group in data:
            if "itens" in group:
                all_items.extend(group["itens"])
            else:
                # maybe flat list?
                pass
    
    # Inspect items
    for i, item in enumerate(all_items):
        name = item.get("nome", "").strip()
        details = item.get("detalhes", "")
        
        # Heuristic 1: Starts with digit
        if re.match(r"^\d", name):
            issues.append(f"[Line ~{i}] Starts with digit: '{name}'")
            continue
            
        # Heuristic 2: Too short or junk words
        if len(name) < 3 and name.lower() not in ["az"]: # 'az' maybe? unlikely.
            issues.append(f"[Line ~{i}] Too short: '{name}'")
            continue
            
        # Heuristic 3: Common junk fragments
        junk_starts = ["equivalente a", "contendo", "com ", "de ", "em "]
        if any(name.lower().startswith(x) for x in junk_starts):
            issues.append(f"[Line ~{i}] Fragment: '{name}'")
            continue
            
        # Heuristic 4: Orphaned second parts (Contextual)
        # e.g. "potássio" following "amoxicilina" (harder to catch without context, but "potássio" generic is suspicious)
        if name.lower() in ["potássio", "sódio", "cálcio", "a", "b", "c", "mg", "ml"]:
            issues.append(f"[Line ~{i}] Orphaned suffix: '{name}'")
            continue

    print(f"Total Items Scanned: {len(all_items)}")
    print(f"Suspicious Items Found: {len(issues)}")
    print("-" * 30)
    for issue in issues[:20]: # Show first 20
        print(issue)
    if len(issues) > 20:
        print(f"... and {len(issues) - 20} more.")

if __name__ == "__main__":
    analyze()
