import os
import sys
import time
import subprocess

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS_DIR = os.path.join(BASE_DIR, "tools")
BUILD_SCRIPT = os.path.join(TOOLS_DIR, "build_mod.py")
ARENA_SCRIPT = os.path.join(TOOLS_DIR, "real_game_arena_test.py")
POSTWAVE_SCRIPT = os.path.join(TOOLS_DIR, "real_game_postwave_test.py")

GAME_DIR = r"D:\Brotato_Coop_Test"
LOG_FILE = os.path.join(GAME_DIR, "logs", "coop_all.log")
SHOTS_DIR = os.path.join(GAME_DIR, "screenshots")
GODOT_LOG = os.path.expandvars(r"%APPDATA%\Brotato\logs\godot.log")
MODLOADER_LOG = os.path.expandvars(r"%APPDATA%\Brotato\logs\modloader.log")

def kill_brotato():
    subprocess.run(["powershell", "-Command", "Get-Process -Name Brotato -ErrorAction SilentlyContinue | Stop-Process -Force"], capture_output=True)
    time.sleep(1)

def run_step(title, cmd, cwd=None):
    print("\n" + "=" * 80)
    print(f" >>> {title}")
    print("=" * 80)
    sys.stdout.flush()
    result = subprocess.run(cmd, cwd=cwd)
    if result.returncode != 0:
        print(f"\n[STEP FAILED] Return code: {result.returncode}")
        return False
    print(f"\n[STEP PASSED]")
    return True

def main():
    print("*" * 80)
    print(" STARTING COMPLETE BROTATO ONLINE CO-OP VERIFICATION SUITE")
    print("*" * 80)
    sys.stdout.flush()

    kill_brotato()

    # Step 1: Build & Deploy
    if not run_step("STEP 1: BUILD & DEPLOY MOD", [sys.executable, BUILD_SCRIPT, GAME_DIR], cwd=BASE_DIR):
        sys.exit(1)

    time.sleep(2)
    kill_brotato()

    # Step 2: Arena & 30Hz Movement Test
    arena_ok = run_step("STEP 2: ARENA & 30Hz REAL-TIME MOVEMENT TEST", [sys.executable, ARENA_SCRIPT], cwd=TOOLS_DIR)
    
    time.sleep(3)
    kill_brotato()

    # Step 3: Post-Wave & Shop Test
    postwave_ok = run_step("STEP 3: POST-WAVE & SHOP COMPREHENSIVE TEST", [sys.executable, POSTWAVE_SCRIPT], cwd=TOOLS_DIR)

    time.sleep(2)
    kill_brotato()

    # Step 4: Full Multi-Log Audit
    print("\n" + "=" * 80)
    print(" STEP 4: MULTI-TIER LOG AUDIT & ZERO-ERROR VALIDATION")
    print("=" * 80)
    
    godot_errors = []
    if os.path.exists(GODOT_LOG):
        with open(GODOT_LOG, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                if "SCRIPT ERROR:" in line or "CRASH" in line:
                    godot_errors.append(line.strip())

    coop_errors = []
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                if "[ERROR]" in line or "Parse Error" in line:
                    coop_errors.append(line.strip())

    print(f"1. Godot Engine Log ({GODOT_LOG}):")
    print(f"   Script Errors / Crashes: {len(godot_errors)}")
    for err in godot_errors[-5:]:
        print(f"     -> {err}")

    print(f"2. Unified Mod Log ({LOG_FILE}):")
    print(f"   Logged Errors: {len(coop_errors)}")
    for err in coop_errors[-5:]:
        print(f"     -> {err}")

    # Step 5: Screenshots Check
    print("\n" + "=" * 80)
    print(" STEP 5: GPU CAPTURED SCREENSHOTS AUDIT")
    print("=" * 80)
    screenshots = []
    if os.path.exists(SHOTS_DIR):
        for f in os.listdir(SHOTS_DIR):
            if f.endswith(".png"):
                fp = os.path.join(SHOTS_DIR, f)
                screenshots.append((f, os.path.getsize(fp)))

    print(f"Total screenshots collected: {len(screenshots)}")
    for s_name, s_size in screenshots:
        print(f"  [SCREENSHOT] {s_name} ({s_size} bytes)")

    # Final Verdict
    print("\n" + "*" * 80)
    print(" FINAL VERIFICATION RESULTS SUMMARY")
    print("*" * 80)
    print(f"  - Mod Build & Deploy:    PASS")
    print(f"  - Real Arena Test:       {'PASS' if arena_ok else 'FAIL'}")
    print(f"  - Real Post-Wave Test:   {'PASS' if postwave_ok else 'FAIL'}")
    print(f"  - Zero Errors in Logs:   {'PASS' if len(godot_errors) == 0 and len(coop_errors) == 0 else 'FAIL'}")
    print(f"  - Screenshots Captured:  {'PASS' if len(screenshots) > 0 else 'FAIL'}")
    
    suite_ok = arena_ok and postwave_ok and (len(godot_errors) == 0) and (len(coop_errors) == 0)
    print(f"\n>>> SUITE OUTCOME: {'ALL TESTS PASSED WITH ZERO ERRORS' if suite_ok else 'TESTS FAILED OR DETECTED ERRORS'} <<<")
    print("*" * 80)

    sys.exit(0 if suite_ok else 1)

if __name__ == "__main__":
    main()
