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
    """Spawns Brotato directly onto the user's interactive physical desktop (WinSta0\Default)."""
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
    """Positions and resizes a process window using Win32 API on Default desktop."""
    EnumWindowsProc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    user32.EnumWindows.argtypes = [EnumWindowsProc, wintypes.LPARAM]
    user32.EnumWindows.restype = wintypes.BOOL
    user32.IsWindowVisible.argtypes = [wintypes.HWND]
    user32.IsWindowVisible.restype = wintypes.BOOL
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
                    # Restore if minimized/hidden, position side-by-side, bring to top
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

def run_real_game_postwave_test():
    print("=" * 75)
    print(" BROTATO REAL-GAME FULL MULTIPLAYER POST-WAVE & SHOP VERIFICATION")
    print(" (Crate Loot + Stat Upgrades + Shop Buying + Reroll + Wave Advance)")
    print("=" * 75)
    
    # Switch thread to the interactive visible desktop so we can manipulate windows on user's screen
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
            
    # 1. Launch Host instance with --coop-host-postwave on visible desktop
    print("\n[STEP 1] Launching real Host instance on visible desktop (--coop-host-postwave)...")
    host_pi = launch_game_on_default_desktop(["--windowed", "--coop-host-postwave"])
    print(f"         Host started with PID: {host_pi.dwProcessId}")
    position_window_by_pid(host_pi.dwProcessId, x=0, y=0, width=950, height=1000)
    
    # Allow host to initialize Godot and bind port 7777
    time.sleep(5)
    
    # 2. Launch Client instance with --coop-join-postwave 127.0.0.1 on visible desktop
    print("\n[STEP 2] Launching real Client instance on visible desktop (--coop-join-postwave 127.0.0.1)...")
    client_pi = launch_game_on_default_desktop(["--windowed", "--coop-join-postwave", "127.0.0.1"])
    print(f"         Client started with PID: {client_pi.dwProcessId}")
    position_window_by_pid(client_pi.dwProcessId, x=960, y=0, width=950, height=1000)
    
    # 3. Observe full post-wave sequence
    print("\n[STEP 3] Observing real game execution for 38 seconds (Upgrades + Crates + Shop + Advance)...")
    last_size = 0
    start_t = time.time()
    shot_taken = set()
    while time.time() - start_t < 38:
        time.sleep(2)
        elapsed = int(time.time() - start_t)
        for target_sec in (8, 16, 24, 32):
            if elapsed >= target_sec and target_sec not in shot_taken:
                shot_taken.add(target_sec)
                try:
                    from PIL import ImageGrab
                    img = ImageGrab.grab()
                    os.makedirs(SHOTS_DIR, exist_ok=True)
                    s_path = os.path.join(SHOTS_DIR, f"live_side_by_side_{target_sec}s.png")
                    img.save(s_path)
                    print(f"  [SCREENSHOT] Captured live side-by-side screen: {s_path}")
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
                        
    # 4. Terminate game processes cleanly
    print("\n[STEP 4] Terminating game instances...")
    for pi, name in [(host_pi, "Host"), (client_pi, "Client")]:
        try:
            kernel32.TerminateProcess(pi.hProcess, 0)
            kernel32.CloseHandle(pi.hProcess)
            kernel32.CloseHandle(pi.hThread)
        except Exception:
            subprocess.run(["taskkill", "/F", "/PID", str(pi.dwProcessId)], capture_output=True)
            
    # 5. Check Captured Screenshots
    print("\n" + "=" * 75)
    print(" VERIFYING CAPTURED POST-WAVE & SHOP SCREENSHOTS")
    print("=" * 75)
    captured = []
    if os.path.exists(SHOTS_DIR):
        for f in os.listdir(SHOTS_DIR):
            if f.endswith(".png"):
                fp = os.path.join(SHOTS_DIR, f)
                sz = os.path.getsize(fp)
                captured.append((f, sz))
                print(f"  [SCREENSHOT] {f} ({sz} bytes)")
    
    # 6. Audit Unified Log
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
    warnings = [l.strip() for l in log_lines if "[WARN]" in l]
    
    if errors:
        print(f"\n[!] Detected {len(errors)} errors:")
        for err in errors:
            print("    " + err)
    else:
        print("\n[OK] ZERO ERRORS detected in unified log file!")
        
    # Check key milestones
    has_host = any("Hosting online game on port" in l for l in log_lines)
    has_peer = any("Peer connected" in l for l in log_lines)
    has_upgrades_loaded = any("CoopUpgradesUI scene loaded successfully" in l for l in log_lines)
    has_crate_host = any("Host: Player 0 took crate item" in l for l in log_lines)
    has_crate_client = any("Added crate item to player 1 inventory" in l or "Player 1 crate take confirmed" in l for l in log_lines)
    has_upgrade_host = any("Host: Player 0 chose upgrade card" in l for l in log_lines)
    has_upgrade_client = any("Applied UPGRADE" in l or "Player 1 upgrade choice" in l for l in log_lines)
    has_shop_loaded = any("CoopShop scene loaded successfully" in l for l in log_lines)
    has_host_buy = any("Host: Bought item in slot 0 for Player 0" in l for l in log_lines)
    has_client_buy = any("Executed BUY for player 1" in l or "Confirmed shop buy for player 1" in l for l in log_lines)
    has_client_reroll = any("Executed REROLL for player 1" in l or "Confirmed shop reroll for player 1" in l for l in log_lines)
    has_ready_advance = any("All players READY in shop" in l or "Advancing from shop to next wave" in l for l in log_lines)
    
    print("\nMilestones Verification:")
    print(f"  1. Server bound & Client connected:             {'[PASS]' if (has_host and has_peer) else '[FAIL]'}")
    print(f"  2. CoopUpgradesUI scene loaded for all:         {'[PASS]' if has_upgrades_loaded else '[FAIL]'}")
    print(f"  3. Crate items taken (Host local + Client RPC): {'[PASS]' if (has_crate_host and has_crate_client) else '[FAIL]'}")
    print(f"  4. Stat upgrades chosen (Host + Client RPC):    {'[PASS]' if (has_upgrade_host and has_upgrade_client) else '[FAIL]'}")
    print(f"  5. CoopShop loaded & items bought by both:      {'[PASS]' if (has_shop_loaded and has_host_buy and has_client_buy) else '[FAIL]'}")
    print(f"  6. Shop rerolled by Client via RPC:             {'[PASS]' if has_client_reroll else '[FAIL]'}")
    print(f"  7. Both players ready & advanced to next wave:  {'[PASS]' if has_ready_advance else '[FAIL]'}")
    
    success = (len(errors) == 0) and has_host and has_peer and has_upgrades_loaded and has_crate_host and has_crate_client and has_upgrade_host and has_upgrade_client and has_shop_loaded and has_host_buy and has_client_buy and has_client_reroll and has_ready_advance
    print(f"\n>>> OVERALL POST-WAVE & SHOP MULTIPLAYER VERIFICATION: {'SUCCESS' if success else 'FAILURE'} <<<")
    return success

if __name__ == "__main__":
    ok = run_real_game_postwave_test()
    sys.exit(0 if ok else 1)
