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
    # We catch the whole line to be safe about indentation if we wanted, but simple substitution is usually fine.
    
    # Force Min SDK 23 (Android 6.0) - High compatibility and required by many plugins
    new_content, count = re.subn(pattern, replacement, content)
    
    # Also Enable MultiDex (Common fix for 'Release' builds with many plugins)
    if "multiDexEnabled" not in new_content:
        # Inject into defaultConfig
        if "defaultConfig {" in new_content:
            new_content = new_content.replace("defaultConfig {", "defaultConfig {\n        multiDexEnabled true")
            print("Injected multiDexEnabled.")
    
    if count > 0:
        print(f"Replaced {count} occurrences of minSdkVersion.")
        with open(path, 'w') as f:
            f.write(new_content)
        
        # DEBUG: Print the relevant section to verify syntax
        print(f"--- PATCHED CONTENT ({path}) [Snippet] ---")
        start_idx = new_content.find("defaultConfig")
        print(new_content[start_idx:start_idx+300])
        print("---------------------------------------------")
        return True
    else:
        print("Pattern not found. Dumping content snippet:")
        print(content[:500]) # Audit
        return False

# 1. Try Groovy
groovy_path = "medubs_native/android/app/build.gradle"
if os.path.exists(groovy_path):
    # Pattern: minSdkVersion <anything>
    # We replace it with minSdkVersion 23
    patch_file(groovy_path, r"minSdkVersion\s+.*", "minSdkVersion 23")

# 2. Try Kotlin
kotlin_path = "medubs_native/android/app/build.gradle.kts"
if os.path.exists(kotlin_path):
    # Pattern: minSdk = <anything>
    patch_file(kotlin_path, r"minSdk\s*=\s*.*", "minSdk = 23")
    # Pattern: minSdkVersion(<anything>)
    patch_file(kotlin_path, r"minSdkVersion\s*\(.*\)", "minSdkVersion(23)")

print("Patching complete.")
