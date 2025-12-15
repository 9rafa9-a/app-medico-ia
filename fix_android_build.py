import os

# We are running INSIDE medubs_native/
root_gradle = "android/build.gradle"
app_gradle = "android/app/build.gradle"
app_gradle_kts = "android/app/build.gradle.kts"

# 3. Create/Overwrite gradle.properties (Critical for Plugins)
print("Creating gradle.properties...")
with open("android/gradle.properties", "w") as f:
    f.write("org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8\n")
    f.write("android.useAndroidX=true\n")
    f.write("android.enableJetifier=true\n")
    f.write("flutter.minSdkVersion=23\n")
    f.write("flutter.targetSdkVersion=34\n")
    f.write("flutter.compileSdkVersion=34\n")

# 1. Patch Root build.gradle
if os.path.exists(root_gradle):
    print(f"Patching {root_gradle}...")
    with open(root_gradle, "r") as f:
        content = f.read()
    
    # We want to inject our variables at the very top or inside ext if it exists.
    # Easiest way: Prepend to the file a buildscript block with ext? 
    # Or just replace "buildscript {" with "buildscript { ext { ... } "
    
    variables = """
    ext {
        buildToolsVersion = "34.0.0"
        minSdkVersion = 23
        compileSdkVersion = 34
        targetSdkVersion = 34
        flutterMinSdkVersion = 23
    }
    """
    
    if "ext {" in content:
        # If ext exists, simplistic injection might be messy.
        # Let's just prepend to the file. Gradle allows multiple buildscript blocks usually or just root vars.
        # BUT: vars defined in root are visible to subprojects.
        new_content = variables + "\n" + content
    else:
        # Prepend
        new_content = variables + "\n" + content

    with open(root_gradle, "w") as f:
        f.write(new_content)
    print("Injected global configuration variables into root build.gradle")
    
    print("--- ROOT BUILD.GRADLE CONTENT ---")
    print(new_content)
    print("---------------------------------")
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
    content = content.replace("flutter.targetSdkVersion", "34")
    content = content.replace("flutter.compileSdkVersion", "34")
    
    # Inject MultiDex
    if "multiDexEnabled" not in content and "defaultConfig {" in content:
        # Use simple string replacement with native newline
        content = content.replace("defaultConfig {", "defaultConfig {\n        multiDexEnabled true")
        
    with open(target_app_gradle, "w") as f:
        f.write(content)
    print("Patched app gradle file")
else:
    print("No app build.gradle found!")

# 3. Create properties file just in case
with open("android/local.properties", "w") as f:
    f.write("flutter.minSdkVersion=23\\n")
    f.write("flutter.targetSdkVersion=34\\n")
    f.write("flutter.compileSdkVersion=34\\n")
    f.write("sdk.dir=/usr/lib/android-sdk\\n") # Generic placeholder
