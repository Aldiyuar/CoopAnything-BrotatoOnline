import subprocess
import time
import os

GAME_EXE = r"D:\Brotato_Coop_Test\Brotato.exe"
MODLOADER_LOG = os.path.expandvars(r"%APPDATA%\Brotato\logs\modloader.log")

def run_smoke_test():
    print(f"Launching {GAME_EXE} for smoke test...")
    proc = subprocess.Popen([GAME_EXE, "--windowed"], cwd=os.path.dirname(GAME_EXE))
    pid = proc.pid
    print(f"Brotato started with PID: {pid}")
    
    time.sleep(8)
    
    # Read log
    print("Reading modloader.log...")
    lines = []
    if os.path.exists(MODLOADER_LOG):
        with open(MODLOADER_LOG, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
            
    # Terminate process cleanly
    try:
        proc.terminate()
        proc.wait(timeout=3)
    except Exception:
        subprocess.run(["taskkill", "/F", "/PID", str(pid)], capture_output=True)
        
    print("\n--- ModLoader Log Tail ---")
    for line in lines[-35:]:
        print(line.strip())
        
    success = any("CoopAnything" in line for line in lines)
    if success:
        print("\n[SUCCESS] CoopAnything-BrotatoOnline loaded successfully!")
    else:
        print("\n[FAIL] Mod was not detected in modloader.log")

if __name__ == "__main__":
    run_smoke_test()
