import os
import sys
import time
import subprocess
import ctypes
from ctypes import wintypes

user32 = ctypes.windll.user32

GAME_EXE = r"D:\Brotato_Coop_Test\Brotato.exe"
GAME_DIR = os.path.dirname(GAME_EXE)
LOG_FILE = r"D:\Brotato_Coop_Test\logs\coop_all.log"

SW_RESTORE = 9

def get_brotato_hwnds():
    hwnds = []
    def enum_windows_callback(hwnd, extra):
        if user32.IsWindowVisible(hwnd):
            length = user32.GetWindowTextLengthW(hwnd)
            buff = ctypes.create_unicode_buffer(length + 1)
            user32.GetWindowTextW(hwnd, buff, length + 1)
            title = buff.value
            if "Brotato" in title:
                hwnds.append(hwnd)
        return True

    ENUMPROC = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
    user32.EnumWindows(ENUMPROC(enum_windows_callback), 0)
    return hwnds

def launch_dual_windows():
    print("=" * 70)
    print(" LAUNCHING DUAL BROTATO CO-OP WINDOWS (LIVE USER PLAY)")
    print("=" * 70)

    # 1. Screen Dimensions
    screen_w = user32.GetSystemMetrics(0)
    screen_h = user32.GetSystemMetrics(1)
    print(f"Detected Display Resolution: {screen_w}x{screen_h}")

    half_w = (screen_w // 2) - 20
    win_h = screen_h - 90

    # 2. Launch Host
    print("\n[1/4] Launching Host instance (Port 7777)...")
    host_proc = subprocess.Popen(
        [GAME_EXE, "--windowed", "--coop-host-match"],
        cwd=GAME_DIR
    )
    print(f"      Host PID: {host_proc.pid}")
    print("      Waiting 7 seconds for Host to initialize Godot, bind port, and enter arena...")
    time.sleep(7)

    # 3. Launch Client
    print("\n[2/4] Launching Client instance (Connecting to 127.0.0.1:7777)...")
    client_proc = subprocess.Popen(
        [GAME_EXE, "--windowed", "--coop-join", "127.0.0.1"],
        cwd=GAME_DIR
    )
    print(f"      Client PID: {client_proc.pid}")
    print("      Waiting 7 seconds for Client to connect, handshake, and enter arena...")
    time.sleep(7)

    # 4. Position Windows Side-by-Side
    print("\n[3/4] Arranging game windows side-by-side on your monitor...")
    for attempt in range(5):
        hwnds = get_brotato_hwnds()
        if len(hwnds) >= 2:
            break
        time.sleep(1)

    hwnds = get_brotato_hwnds()
    print(f"      Found {len(hwnds)} visible Brotato windows.")
    if len(hwnds) >= 2:
        # Sort by x or hwnd to distinguish left and right
        w1, w2 = hwnds[0], hwnds[1]
        user32.ShowWindow(w1, SW_RESTORE)
        user32.MoveWindow(w1, 10, 10, half_w, win_h, True)

        user32.ShowWindow(w2, SW_RESTORE)
        user32.MoveWindow(w2, (screen_w // 2) + 5, 10, half_w, win_h, True)
        user32.SetForegroundWindow(w1)
        print("      Windows placed: Window 1 (Left), Window 2 (Right).")
    elif len(hwnds) == 1:
        user32.ShowWindow(hwnds[0], SW_RESTORE)
        user32.MoveWindow(hwnds[0], 10, 10, half_w, win_h, True)

    print("\n[4/4] Both game instances are live on your screen!")
    print("=" * 70)
    print("  <- LEFT WINDOW : HOST   (Player 0 - Well-Rounded)")
    print("  -> RIGHT WINDOW: CLIENT (Player 1 - Brawler)")
    print("=" * 70)
    print("Click into either window to play and move that character!")
    print("Monitoring session log in real-time. Do not close this runner...")
    sys.stdout.flush()

    last_size = 0
    try:
        while host_proc.poll() is None or client_proc.poll() is None:
            time.sleep(1)
            if os.path.exists(LOG_FILE):
                with open(LOG_FILE, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
                    if len(content) > last_size:
                        new_text = content[last_size:]
                        last_size = len(content)
                        for line in new_text.strip().splitlines():
                            if "[ERROR]" in line or "input" in line.lower() or "wave" in line.lower() or "peer" in line.lower():
                                print("  [LOG] " + line)
                                sys.stdout.flush()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    launch_dual_windows()
