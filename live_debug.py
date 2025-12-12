import subprocess
import time
import os
import sys

# Path to ADB
ADB_PATH = os.path.expandvars(r"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe")

def main():
    print(f"🕵️‍♂️ Live Android Debugger v1.0")
    print(f"📍 ADB Path: {ADB_PATH}")
    
    if not os.path.exists(ADB_PATH):
        print("❌ ADB not found! Check SDK installation.")
        return

    print("⏳ Waiting for device connection... (Plug in USB)")
    
    # 1. Wait for device
    while True:
        try:
            res = subprocess.check_output([ADB_PATH, "devices"]).decode()
            lines = [l for l in res.splitlines() if l.strip() and "List of" not in l]
            if len(lines) > 0 and "device" in lines[0]:
                print(f"✅ Device Connected: {lines[0].split()[0]}")
                break
            else:
                # print(".", end="", flush=True)
                time.sleep(1)
        except Exception as e:
            print(f"Error checking devices: {e}")
            time.sleep(1)

    print("\n📺 STREAMING LOGS (Filtering for 'python', 'flet', 'fatal')...")
    print("-" * 50)

    # 2. Stream Logcat
    try:
        # Clear old logs first
        subprocess.run([ADB_PATH, "logcat", "-c"])
        
        # Start stream
        process = subprocess.Popen(
            [ADB_PATH, "logcat", "-v", "time"], 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE
        )

        while True:
            line = process.stdout.readline()
            if not line:
                break
            
            line_str = line.decode("utf-8", errors="replace").strip()
            
            # Smart Filter
            keywords = ["python", "flet", "fatal", "exception", "crash", "traceback"]
            if any(k in line_str.lower() for k in keywords):
                # Highlight in output
                print(f"🔴 {line_str}")
            
    except KeyboardInterrupt:
        print("\n🛑 Stopped by user.")
    except Exception as e:
        print(f"❌ Stream Error: {e}")

if __name__ == "__main__":
    main()
