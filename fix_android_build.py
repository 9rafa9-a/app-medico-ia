import os
import subprocess

# We are running INSIDE medubs_native/
root_gradle = "android/build.gradle"
app_gradle = "android/app/build.gradle"
app_gradle_kts = "android/app/build.gradle.kts"

# 3. Create/Overwrite gradle.properties (Critical for Plugins)
print("Creating gradle.properties...")

try:
    # Find where flutter is installed
    flutter_bin = subprocess.check_output(["which", "flutter"]).decode("utf-8").strip()
    # flutter_bin is likely .../bin/flutter. SDK root is one level up.
    flutter_sdk_root = os.path.dirname(os.path.dirname(flutter_bin))
    print(f"Found Flutter SDK at: {flutter_sdk_root}")
except Exception as e:
    print(f"Could not resolve Flutter SDK: {e}")
    flutter_sdk_root = "/usr/local/flutter" # Fallback

with open("android/local.properties", "w") as f:
    f.write(f"flutter.sdk={flutter_sdk_root}\n")
    f.write("flutter.buildMode=release\n")
    f.write("flutter.versionName=1.0.0\n")
    f.write("flutter.versionCode=1\n")

    with open("android/gradle.properties", "w") as f:
        f.write("org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8\n")
        f.write("org.gradle.daemon=false\n") # Disable daemon for CI stability
        f.write("android.useAndroidX=true\n")
        f.write("android.enableJetifier=true\n")
        f.write("flutter.minSdkVersion=23\n")
        f.write("flutter.targetSdkVersion=35\n")
        f.write("flutter.compileSdkVersion=35\n")

# 1. Patch Root build.gradle
if os.path.exists(root_gradle):
    print(f"Patching {root_gradle}...")
    with open(root_gradle, "r") as f:
        content = f.read()
    
    # We define global variables that standard Flutter plugins look for.
    variables = """
    ext {
        // Standard Android variables
        buildToolsVersion = "35.0.0"
        minSdkVersion = 23
        compileSdkVersion = 35
        targetSdkVersion = 35
        
        // Flutter variables (Mocking the flutter.groovy behavior)
        flutterMinSdkVersion = 23
        flutterTargetSdkVersion = 35
        flutterCompileSdkVersion = 35
        
        // Object style (some plugins use rootProject.ext.flutter.minSdkVersion)
        flutter = [
            minSdkVersion: 23,
            targetSdkVersion: 35,
            compileSdkVersion: 35,
            versionName: '1.0.0',
            versionCode: 1
        ]
    }
    """
    
    # NAMESPACE PATCH (Moved to TOP just after logic vars)
    namespace_patch = """
    subprojects {
        afterEvaluate { project ->
            if (project.hasProperty("android")) {
                project.android {
                    if (namespace == null) {
                        println "Fixing missing namespace for ${project.name}"
                        namespace project.group ?: "com.example.${project.name}"
                    }
                }
            }
        }
    }
    """

    # Prepend both to ensure they run BEFORE any other evaluation
    new_content = variables + "\n" + namespace_patch + "\n" + content.replace("buildscript {", "// buildscript moved implicitly via prepending\nbuildscript {")
    
    # Clean up potential duplicates if buildscript was already top
    if "buildscript {" in content:
        new_content = variables + "\n" + namespace_patch + "\n" + content

    with open(root_gradle, "w") as f:
        f.write(new_content)
    print("Injected global configuration variables and namespace patcher at TOP")

else:
    print(f"ERROR: {root_gradle} not found!")

# 2. Patch App build.gradle (Groovy or Kotlin)
target_app_gradle = app_gradle if os.path.exists(app_gradle) else (app_gradle_kts if os.path.exists(app_gradle_kts) else None)

if target_app_gradle:
    print(f"Patching {target_app_gradle}...")
    with open(target_app_gradle, "r") as f:
        content = f.read()
    
    # Simple Replacements
    content = content.replace("flutter.minSdkVersion", "23")
    content = content.replace("flutter.targetSdkVersion", "35")
    content = content.replace("flutter.compileSdkVersion", "35")
    
    # Inject MultiDex
    if "multiDexEnabled" not in content and "defaultConfig {" in content:
        # Use simple string replacement with native newline
        content = content.replace("defaultConfig {", "defaultConfig {\n        multiDexEnabled true")
        
    with open(target_app_gradle, "w") as f:
        f.write(content)
    print("Patched app gradle file")
else:
    print("No app build.gradle found!")

# 4. Patch AndroidManifest.xml (Inject Permissions)
def patch_manifest():
    \"\"\"Injects permissions into AndroidManifest.xml\"\"\"
    manifest_paths = [
        "android/app/src/main/AndroidManifest.xml",
        "medubs_native/android/app/src/main/AndroidManifest.xml", 
        "AndroidManifest.xml" # Fallback
    ]
    
    target_path = None
    for p in manifest_paths:
        if os.path.exists(p):
            target_path = p
            break
            
    if not target_path:
        print(f"❌ Manifest not found in checked paths.")
        return

    print(f"🔧 Patching Manifest: {target_path}")
    with open(target_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Permissions to add
    permissions = [
        '<uses-permission android:name="android.permission.INTERNET"/>',
        '<uses-permission android:name="android.permission.RECORD_AUDIO"/>',
        '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>',
        '<uses-permission android:name="android.permission.READ_MEDIA_AUDIO"/>',
    ]
    
    if "android.permission.INTERNET" in content:
        print("ℹ️ Manifest already has permissions.")
        return

    # Inject permissions before the <application> tag
    if "<application" in content:
        perm_block = "\n    ".join(permissions)
        content = content.replace("<application", f"{perm_block}\n    <application")
        
        with open(target_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("✅ Permissions injected into AndroidManifest.xml")
    else:
        print("❌ Could not find <application> tag in Manifest.")

if __name__ == "__main__":
    patch_manifest()
