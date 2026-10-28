import subprocess
import time
import os
import sys
import ctypes
from ctypes import wintypes
from PIL import ImageGrab

user32 = ctypes.windll.user32

GAME_EXE = r"D:\Brotato_Coop_Test\Brotato.exe"
SHOTS_DIR = r"D:\Brotato_Coop_Test\screenshots"
LOG_FILE = r"D:\Brotato_Coop_Test\logs\coop_all.log"

VK_RETURN = 0x0D
VK_DOWN = 0x28
VK_UP = 0x26
VK_SPACE = 0x20
KEYEVENTF_KEYUP = 0x0002

def press_key(vk):
    user32.keybd_event(vk, 0, 0, 0)
    time.sleep(0.08)
    user32.keybd_event(vk, 0, KEYEVENTF_KEYUP, 0)
    time.sleep(0.15)

def find_brotato_hwnds():
    hwnds = []
    def enum_windows_proc(hwnd, lParam):
        if user32.IsWindowVisible(hwnd):
            length = user32.GetWindowTextLengthW(hwnd)
            buff = ctypes.create_unicode_buffer(length + 1)
            user32.GetWindowTextW(hwnd, buff, length + 1)
            title = buff.value
            if "Brotato" in title:
                hwnds.append(hwnd)
        return True
    EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
    user32.EnumWindows(EnumWindowsProc(enum_windows_proc), 0)
    return hwnds

def capture_brotato(hwnd, name):
    rect = wintypes.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    bbox = (rect.left, rect.top, rect.right, rect.bottom)
    if rect.right <= rect.left or rect.bottom <= rect.top:
        print(f"[WARN] Invalid window rect for {name}")
        return None
    img = ImageGrab.grab(bbox=bbox)
    os.makedirs(SHOTS_DIR, exist_ok=True)
    out_path = os.path.join(SHOTS_DIR, f"{name}.png")
    img.save(out_path)
    print(f"[SHOT] Saved screenshot: {out_path} ({rect.right-rect.left}x{rect.bottom-rect.top})")
    return out_path

def run_real_game_playtest():
    print("=" * 65)
    print(" STARTING REAL-GAME INTERACTIVE VISUAL PLAYTEST")
    print("=" * 65)
    
    # Clean previous log
    if os.path.exists(LOG_FILE):
        try:
            os.remove(LOG_FILE)
        except Exception:
            pass
            
    # 1. Launch Game
    print("\n[STEP 1] Launching real Brotato game process in windowed mode...")
    proc = subprocess.Popen([GAME_EXE, "--windowed"], cwd=os.path.dirname(GAME_EXE))
    print(f"         Game process PID: {proc.pid}")
    
    # 2. Wait for Splash Screen & Main Menu to load
    print("\n[STEP 2] Waiting for splash screen and main menu to initialize...")
    time.sleep(7)
    
    hwnds = find_brotato_hwnds()
    if not hwnds:
        print("[FAIL] Could not find Brotato window!")
        proc.terminate()
        return False
        
    main_hwnd = hwnds[0]
    user32.SetForegroundWindow(main_hwnd)
    time.sleep(0.5)
    
    # 3. Capture Main Menu with our ONLINE CO-OP button
    print("\n[STEP 3] Capturing Main Menu...")
    shot_menu = capture_brotato(main_hwnd, "01_main_menu")
    
    # 4. Navigate down to "ONLINE CO-OP" button and press Enter
    print("\n[STEP 4] Navigating to ONLINE CO-OP button...")
    press_key(VK_DOWN) # Down arrow from Start to Online Co-op
    time.sleep(0.5)
    shot_focused = capture_brotato(main_hwnd, "02_online_button_focused")
    
    print("\n[STEP 5] Pressing Enter to open Online Co-op Dialog...")
    press_key(VK_RETURN)
    time.sleep(1.2)
    shot_dialog = capture_brotato(main_hwnd, "03_online_coop_dialog")
    
    # 5. Press Enter to Host Game (first button in dialog is "HOST GAME")
    print("\n[STEP 6] Selecting HOST GAME (Port 7777)...")
    press_key(VK_RETURN)
    time.sleep(1.5)
    shot_char_select = capture_brotato(main_hwnd, "04_host_char_selection")
    
    # 6. Launch Client instance to join
    print("\n[STEP 7] Launching second game client instance (--coop-join 127.0.0.1)...")
    client_proc = subprocess.Popen([GAME_EXE, "--windowed", "--coop-join", "127.0.0.1"], cwd=os.path.dirname(GAME_EXE))
    print(f"         Client process PID: {client_proc.pid}")
    
    time.sleep(7) # Wait for client to connect and handshake
    
    # Capture all active windows
    all_hwnds = find_brotato_hwnds()
    print(f"\n[STEP 8] Found {len(all_hwnds)} running Brotato game windows.")
    for idx, h in enumerate(all_hwnds):
        capture_brotato(h, f"05_connected_window_{idx+1}")
        
    # Wait a few seconds for live input verification
    time.sleep(3)
    
    # Cleanup
    print("\n[CLEANUP] Closing game processes...")
    for p in [proc, client_proc]:
        try:
            p.terminate()
            p.wait(timeout=2)
        except Exception:
            subprocess.run(["taskkill", "/F", "/PID", str(p.pid)], capture_output=True)
            
    print("\n" + "=" * 65)
    print(" VERIFYING LOGS FROM REAL-GAME SESSION")
    print("=" * 65)
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
        print(f"Log events captured: {len(lines)}")
        for l in lines:
            print("  " + l.strip())
            
        errors = [l for l in lines if "[ERROR]" in l or "Parse Error" in l]
        if not errors:
            print("\n[SUCCESS] REAL GAME INTERACTIVE PLAYTEST PASSED WITH ZERO ERRORS!")
            return True
        else:
            print(f"\n[FAIL] Found {len(errors)} errors in session log.")
            return False
    else:
        print("[FAIL] No log file generated.")
        return False

if __name__ == "__main__":
    ok = run_real_game_playtest()
    sys.exit(0 if ok else 1)
