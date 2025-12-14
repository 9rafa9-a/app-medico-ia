import os

root_gradle = "medubs_native/android/build.gradle"
app_gradle = "medubs_native/android/app/build.gradle"

# 1. Patch Root build.gradle to force plugins to behave
if os.path.exists(root_gradle):
    print(f"Patching {root_gradle}...")
    with open(root_gradle, "a") as f:
        # We append a subprojects block that forces configuration on all plugins
        f.write("""

// INCISION BY MEDUBS BUILD FIXER
subprojects {
    afterEvaluate { project ->
        if (project.hasProperty("android")) {
            android {
                compileSdkVersion 34
                defaultConfig {
                    minSdkVersion 23
                    targetSdkVersion 34
                }
            }
        }
    }
}
""")
    print("Injected global configuration into root build.gradle")
else:
    print(f"ERROR: {root_gradle} not found!")

# 2. Patch App build.gradle (just to be safe/redundant)
if os.path.exists(app_gradle):
    print(f"Patching {app_gradle}...")
    with open(app_gradle, "r") as f:
        content = f.read()
    
    # Replace flutter.minSdkVersion if present
    content = content.replace("flutter.minSdkVersion", "23")
    content = content.replace("flutter.targetSdkVersion", "34")
    content = content.replace("flutter.compileSdkVersion", "34")
    
    # Inject MultiDex
    if "multiDexEnabled" not in content and "defaultConfig {" in content:
        content = content.replace("defaultConfig {", "defaultConfig {\\n        multiDexEnabled true")
        
    with open(app_gradle, "w") as f:
        f.write(content)
    print("Patched app/build.gradle")

# 3. Create properties file just in case
with open("medubs_native/android/local.properties", "w") as f:
    f.write("flutter.minSdkVersion=23\\n")
    f.write("flutter.targetSdkVersion=34\\n")
    f.write("flutter.compileSdkVersion=34\\n")
    f.write("sdk.dir=/usr/lib/android-sdk\\n") # Generic placeholder
