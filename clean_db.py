import json
import re

def clean_database():
    source_path = "data/db_rename.json"
    target_path = "data/db_rename.json" # Overwrite to fix directly

    try:
        with open(source_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"Erro ao ler: {e}")
        return

    cleaned_groups = []
    removed_count = 0
    merged_count = 0

    if isinstance(data, list):
        for group in data:
            new_items = []
            if "itens" in group:
                raw_items = group["itens"]
                
                # Single pass with lookback for merging
                for i, item in enumerate(raw_items):
                    name = item.get("nome", "").strip()
                    lower_name = name.lower()
                    
                    # 1. ORPHANS (Merge strategies)
                    # Starts with "de ", "com ", "contendo ", "em " OR is a suffix like "potássio"
                    is_orphan_prefix = any(lower_name.startswith(x) for x in ["de ", "com ", "contendo ", "em ", "+ "])
                    is_orphan_suffix = lower_name in ["potássio", "sódica", "sódico", "cálcio", "a", "b"]
                    
                    if (is_orphan_prefix or is_orphan_suffix) and len(new_items) > 0:
                        # MERGE with previous
                        prev_item = new_items[-1]
                        # Glue them together
                        prev_item["nome"] = f"{prev_item['nome']} {name}"
                        # Also merge details if useful? Usually details in orphan line are also junk or match
                        merged_count += 1
                        continue # Skip adding this as new item
                    
                    # 2. TRASH (Delete strategies)
                    # Starts with digit (Dosage only) -> "500 mg"
                    if re.match(r"^\d", name):
                        removed_count += 1
                        continue
                        
                    # Too short or specific junk
                    if len(name) < 3 or lower_name in ["equivalente a", "a", "b", "-"]:
                        removed_count += 1
                        continue
                        
                    # If verified as "Good", add to list
                    new_items.append(item)
                
                group["itens"] = new_items
                cleaned_groups.append(group)
            else:
                cleaned_groups.append(group)

    # Save
    with open(target_path, "w", encoding="utf-8") as f:
        json.dump(cleaned_groups, f, indent=4, ensure_ascii=False)

    print(f"✅ Faxina Concluída!")
    print(f"🗑️ Lixo Removido: {removed_count} itens")
    print(f"🔗 Órfãos Re-conectados: {merged_count} itens")

if __name__ == "__main__":
    clean_database()
