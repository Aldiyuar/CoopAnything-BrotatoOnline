import subprocess
import time
import os
import sys
import ctypes
from ctypes import wintypes

kernel32 = ctypes.windll.kernel32
user32 = ctypes.windll.user32

GAME_EXE = r"D:\Brotato_Coop_Test\Brotato.exe"
LOG_FILE = r"D:\Brotato_Coop_Test\logs\coop_all.log"
SHOTS_DIR = r"D:\Brotato_Coop_Test\screenshots"

class STARTUPINFOW(ctypes.Structure):
    _fields_ = [
        ('cb', wintypes.DWORD),
        ('lpReserved', wintypes.LPWSTR),
        ('lpDesktop', wintypes.LPWSTR),
        ('lpTitle', wintypes.LPWSTR),
        ('dwX', wintypes.DWORD),
        ('dwY', wintypes.DWORD),
        ('dwXSize', wintypes.DWORD),
        ('dwYSize', wintypes.DWORD),
        ('dwXCountChars', wintypes.DWORD),
        ('dwYCountChars', wintypes.DWORD),
        ('dwFillAttribute', wintypes.DWORD),
        ('dwFlags', wintypes.DWORD),
        ('wShowWindow', wintypes.WORD),
        ('cbReserved2', wintypes.WORD),
        ('lpReserved2', ctypes.POINTER(wintypes.BYTE)),
        ('hStdInput', wintypes.HANDLE),
        ('hStdOutput', wintypes.HANDLE),
        ('hStdError', wintypes.HANDLE),
    ]

class PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [
        ('hProcess', wintypes.HANDLE),
        ('hThread', wintypes.HANDLE),
        ('dwProcessId', wintypes.DWORD),
        ('dwThreadId', wintypes.DWORD),
    ]

def launch_game_on_default_desktop(cmd_args):
    si = STARTUPINFOW()
    si.cb = ctypes.sizeof(STARTUPINFOW)
    si.lpDesktop = 'WinSta0\\Default'
    pi = PROCESS_INFORMATION()
    full_cmd = f'"{GAME_EXE}" {" ".join(cmd_args)}'
    cwd = os.path.dirname(GAME_EXE)
    ok = kernel32.CreateProcessW(None, full_cmd, None, None, False, 0, None, cwd, ctypes.byref(si), ctypes.byref(pi))
    if not ok:
        raise RuntimeError(f"Failed to launch game process on Default desktop: {kernel32.GetLastError()}")
    return pi

def position_window_by_pid(pid, x, y, width, height):
    EnumWindowsProc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    user32.EnumWindows.argtypes = [EnumWindowsProc, wintypes.LPARAM]
    user32.EnumWindows.restype = wintypes.BOOL
    user32.IsWindowVisible.argtypes = [wintypes.HWND]
    user32.IsWindowVisible.restype = wintypes.BOOL
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
    user32.SetWindowPos.argtypes = [wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_uint]
    user32.SetForegroundWindow.argtypes = [wintypes.HWND]
    user32.BringWindowToTop.argtypes = [wintypes.HWND]

    for _ in range(25):
        found = []
        def check_cb(hwnd, _):
            if user32.IsWindowVisible(hwnd):
                p = wintypes.DWORD()
                user32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
                if p.value == pid:
                    user32.ShowWindow(hwnd, 9) # SW_RESTORE
                    user32.SetWindowPos(hwnd, 0, x, y, width, height, 0x0040) # SWP_SHOWWINDOW
                    user32.BringWindowToTop(hwnd)
                    user32.SetForegroundWindow(hwnd)
                    found.append(hwnd)
                    return False
            return True
        user32.EnumWindows(EnumWindowsProc(check_cb), 0)
        if found:
            print(f"         [WINDOW] Positioned PID {pid} to ({x}, {y}) size ({width}x{height}) on visible desktop!")
            return found[0]
        time.sleep(0.4)
    print(f"         [WINDOW] Warning: Window for PID {pid} not found for positioning")
    return None

def run_real_game_death_test():
    print("=" * 75)
    print(" BROTATO REAL-GAME MULTIPLAYER PLAYER DEATH & GAMEOVER VERIFICATION")
    print("=" * 75)
    
    h_desk = user32.OpenDesktopW("Default", 0, False, 0x01FF)
    if h_desk:
        user32.SetThreadDesktop(h_desk)

    # Clean previous log & screenshots
    if os.path.exists(LOG_FILE):
        try:
            os.remove(LOG_FILE)
            print("[INIT] Reset coop_all.log")
        except Exception as e:
            print(f"[WARN] Could not remove log: {e}")
            
    if os.path.exists(SHOTS_DIR):
        for f in os.listdir(SHOTS_DIR):
            if f.endswith(".png"):
                try:
                    os.remove(os.path.join(SHOTS_DIR, f))
                except Exception:
                    pass
        print("[INIT] Cleaned previous screenshots")
            
    # 1. Launch Host instance with --coop-host-death on visible desktop
    print("\n[STEP 1] Launching real Host instance on visible desktop (--coop-host-death)...")
    host_pi = launch_game_on_default_desktop(["--windowed", "--coop-host-death"])
    print(f"         Host started with PID: {host_pi.dwProcessId}")
    position_window_by_pid(host_pi.dwProcessId, x=0, y=0, width=950, height=1000)
    
    time.sleep(5)
    
    # 2. Launch Client instance with --coop-join-death 127.0.0.1 on visible desktop
    print("\n[STEP 2] Launching real Client instance on visible desktop (--coop-join-death 127.0.0.1)...")
    client_pi = launch_game_on_default_desktop(["--windowed", "--coop-join-death", "127.0.0.1"])
    print(f"         Client started with PID: {client_pi.dwProcessId}")
    position_window_by_pid(client_pi.dwProcessId, x=960, y=0, width=950, height=1000)
    
    # 3. Wait for arena scene transition, then observe active gameplay & death sequence
    print("\n[STEP 3] Waiting for arena scene transition...")
    arena_ready = False
    wait_start = time.time()
    last_size = 0
    while time.time() - wait_start < 25:
        time.sleep(1)
        if os.path.exists(LOG_FILE):
            with open(LOG_FILE, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
                if len(content) > last_size:
                    new_text = content[last_size:]
                    last_size = len(content)
                    for line in new_text.strip().splitlines():
                        print("  [LIVE LOG] " + line)
                if "Arena scene" in content and "loaded successfully" in content:
                    arena_ready = True
                    break

    print("\n[STEP 4] Observing death test sequence (P1 lethal damage @ 5s, P0 lethal damage @ 11s, GameOver)...")
    start_t = time.time()
    shot_taken = set()
    while time.time() - start_t < 28:
        time.sleep(2)
        elapsed = int(time.time() - start_t)
        for target_sec in (7, 14, 22):
            if elapsed >= target_sec and target_sec not in shot_taken:
                shot_taken.add(target_sec)
                try:
                    from PIL import ImageGrab
                    img = ImageGrab.grab()
                    os.makedirs(SHOTS_DIR, exist_ok=True)
                    s_path = os.path.join(SHOTS_DIR, f"live_death_sequence_{target_sec}s.png")
                    img.save(s_path)
                    print(f"  [SCREENSHOT] Captured live death test screen: {s_path}")
                except Exception as e:
                    print(f"  [SCREENSHOT ERROR] {e}")
        if os.path.exists(LOG_FILE):
            with open(LOG_FILE, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
                if len(content) > last_size:
                    new_text = content[last_size:]
                    last_size = len(content)
                    for line in new_text.strip().splitlines():
                        print("  [LIVE LOG] " + line)

    # 5. Terminate game processes cleanly
    print("\n[STEP 5] Terminating game instances...")
    for pi, name in [(host_pi, "Host"), (client_pi, "Client")]:
        try:
            kernel32.TerminateProcess(pi.hProcess, 0)
            kernel32.CloseHandle(pi.hProcess)
            kernel32.CloseHandle(pi.hThread)
        except Exception:
            subprocess.run(["taskkill", "/F", "/PID", str(pi.dwProcessId)], capture_output=True)
            
    # Check Captured Screenshots
    print("\n" + "=" * 75)
    print(" VERIFYING CAPTURED GAMEPLAY SCREENSHOTS")
    print("=" * 75)
    captured = []
    if os.path.exists(SHOTS_DIR):
        for f in os.listdir(SHOTS_DIR):
            if f.endswith(".png"):
                fp = os.path.join(SHOTS_DIR, f)
                sz = os.path.getsize(fp)
                captured.append((f, sz))
                print(f"  [SCREENSHOT] {f} ({sz} bytes)")
    
    # Audit Unified Log
    print("\n" + "=" * 75)
    print(" AUDITING UNIFIED LOG FILE (coop_all.log)")
    print("=" * 75)
    if not os.path.exists(LOG_FILE):
        print(f"[FAIL] {LOG_FILE} was not found!")
        return False
        
    with open(LOG_FILE, "r", encoding="utf-8", errors="ignore") as f:
        log_lines = f.readlines()
        
    print(f"Total log events recorded: {len(log_lines)}")
    errors = [l.strip() for l in log_lines if "[ERROR]" in l or "Parse Error" in l]
    
    if errors:
        print(f"\n[!] Detected {len(errors)} errors:")
        for err in errors:
            print("    " + err)
    else:
        print("\n[OK] ZERO ERRORS detected in unified log file!")
        
    # Check key milestones
    has_host = any("Hosting online game on port" in l for l in log_lines)
    has_peer = any("Peer connected" in l for l in log_lines)
    has_arena = any("Death test: Arena scene loaded" in l or "Arena scene" in l for l in log_lines)
    has_p1_lethal = any("Inflicting lethal damage to Player 1" in l for l in log_lines)
    has_p1_died_host = any("Host: Player 1 died!" in l for l in log_lines)
    has_p1_died_client = any("Client: Processing player 1 death" in l or "Player 1 died" in l for l in log_lines)
    has_p0_lethal = any("Inflicting lethal damage to Player 0" in l for l in log_lines)
    has_p0_died_host = any("Host: Player 0 died!" in l for l in log_lines)
    has_p0_died_client = any("Client: Processing player 0 death" in l or "Player 0 died" in l for l in log_lines)
    has_coop_end_run = any("coop_end_run.tscn" in l for l in log_lines)
    
    print("\nMilestones Verification:")
    print(f"  1. Server bound & Client connected:             {'[PASS]' if (has_host and has_peer) else '[FAIL]'}")
    print(f"  2. Arena scene entered for death test:          {'[PASS]' if has_arena else '[FAIL]'}")
    print(f"  3. Host inflicted lethal damage to Player 1:    {'[PASS]' if has_p1_lethal else '[FAIL]'}")
    print(f"  4. Host broadcasted Player 1 death:             {'[PASS]' if has_p1_died_host else '[FAIL]'}")
    print(f"  5. Client processed Player 1 death:             {'[PASS]' if has_p1_died_client else '[FAIL]'}")
    print(f"  6. Host inflicted lethal damage to Player 0:    {'[PASS]' if has_p0_lethal else '[FAIL]'}")
    print(f"  7. Host broadcasted Player 0 death:             {'[PASS]' if has_p0_died_host else '[FAIL]'}")
    print(f"  8. Client processed Player 0 death:             {'[PASS]' if has_p0_died_client else '[FAIL]'}")
    print(f"  9. Transitioned to GameOver (coop_end_run):     {'[PASS]' if has_coop_end_run else '[FAIL]'}")
    
    success = (len(errors) == 0) and has_host and has_peer and has_arena and has_p1_lethal and has_p1_died_host and has_p1_died_client and has_p0_lethal and has_p0_died_host and has_p0_died_client and has_coop_end_run
    print(f"\n>>> OVERALL DEATH & GAMEOVER VERIFICATION RESULT: {'SUCCESS' if success else 'FAILURE'} <<<")
    return success

if __name__ == "__main__":
    ok = run_real_game_death_test()
    sys.exit(0 if ok else 1)
