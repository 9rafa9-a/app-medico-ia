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
    f.write("flutter.sdk=/usr/local/flutter\n") # Fake path to satisfy null checks
    f.write("flutter.versionName=1.0.0\n")
    f.write("flutter.versionCode=1\n")

# 1. Patch Root build.gradle
if os.path.exists(root_gradle):
    print(f"Patching {root_gradle}...")
    with open(root_gradle, "r") as f:
        content = f.read()
    
    # We define global variables that standard Flutter plugins look for.
    variables = """
    ext {
        // Standard Android variables
        buildToolsVersion = "34.0.0"
        minSdkVersion = 23
        compileSdkVersion = 34
        targetSdkVersion = 34
        
        // Flutter variables (Mocking the flutter.groovy behavior)
        flutterMinSdkVersion = 23
        flutterTargetSdkVersion = 34
        flutterCompileSdkVersion = 34
        
        // Object style (some plugins use rootProject.ext.flutter.minSdkVersion)
        flutter = [
            minSdkVersion: 23,
            targetSdkVersion: 34,
            compileSdkVersion: 34,
            versionName: '1.0.0',
            versionCode: 1
        ]
    }
    """
    
    # Smart Insertion: Try to put it inside buildscript if possible, or just at top
    if "buildscript {" in content:
        # Insert inside buildscript, at the top of it
        new_content = content.replace("buildscript {", "buildscript {\n" + variables)
    else:
        # Prepend
        new_content = variables + "\n" + content
        
    # Also Force Subprojects configuration (Safe Mode)
    # We use a safer injection that checks for 'android' convention
    subprojects_fix = """
    subprojects {
        afterEvaluate { project ->
            if (project.extensions.findByName("android") != null) {
                try {
                project.android {
                    compileSdkVersion 34
                    defaultConfig {
                        minSdkVersion 23
                        targetSdkVersion 34
                    }
                }
                } catch (Exception e) {
                   println "Failed to force android config: " + e
                }
            }
        }
    }
    """
    
    new_content = new_content + "\n" + subprojects_fix

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
