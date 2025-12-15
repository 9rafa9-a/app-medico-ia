import os

# We are running INSIDE medubs_native/
root_gradle = "android/build.gradle"
app_gradle = "android/app/build.gradle"
app_gradle_kts = "android/app/build.gradle.kts"

# 1. Patch Root build.gradle
if os.path.exists(root_gradle):
    print(f"Patching {root_gradle}...")
    with open(root_gradle, "a") as f:
        f.write("""

// INCISION BY MEDUBS BUILD FIXER
// We define global variables that standard Flutter plugins look for.
// This avoids the 'afterEvaluate' crash.
buildscript {
    ext {
        minSdkVersion = 23
        compileSdkVersion = 34
        targetSdkVersion = 34
        flutterMinSdkVersion = 23
    }
}

subprojects {
    project.configurations.all {
        resolutionStrategy.eachDependency { details ->
            if (details.requested.group == 'com.android.support'
                    && !details.requested.name.contains('multidex') ) {
                details.useVersion "1.0.0"
            }
        }
    }
}
""")
    print("Injected global configuration into root build.gradle")
elif os.path.exists(root_gradle + ".kts"):
   print("Found root build.gradle.kts - (Script not optimized for Root Kotlin yet, skipping root injection)")
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
