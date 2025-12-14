import os
import re
import sys

def patch_file(path, pattern, replacement):
    if not os.path.exists(path):
        print(f"File not found: {path}")
        return False
        
    print(f"Patching {path}...")
    with open(path, 'r') as f:
        content = f.read()
        
    # Check if already patched
    if "minSdkVersion 21" in content or "minSdk = 21" in content:
        print("Already patched or safe.")
        # But we force it anyway to be sure
        
    # Regex Magic
    # Matches "minSdkVersion 19" or "minSdk = flutter.minSdk" etc
    new_content, count = re.subn(pattern, replacement, content)
    
    if count > 0:
        print(f"Replaced {count} occurrences.")
        with open(path, 'w') as f:
            f.write(new_content)
        return True
    else:
        print("Pattern not found. Dumping content snippet:")
        print(content[:500]) # Audit
        return False

# 1. Try Groovy
groovy_path = "medubs_native/android/app/build.gradle"
if os.path.exists(groovy_path):
    # Pattern: minSdkVersion <anything>
    # We replace it with minSdkVersion 21
    patch_file(groovy_path, r"minSdkVersion\s+.*", "minSdkVersion 21")

# 2. Try Kotlin
kotlin_path = "medubs_native/android/app/build.gradle.kts"
if os.path.exists(kotlin_path):
    # Pattern: minSdk = <anything>
    patch_file(kotlin_path, r"minSdk\s*=\s*.*", "minSdk = 21")
    # Pattern: minSdkVersion(<anything>)
    patch_file(kotlin_path, r"minSdkVersion\s*\(.*\)", "minSdkVersion(21)")

print("Patching complete.")
