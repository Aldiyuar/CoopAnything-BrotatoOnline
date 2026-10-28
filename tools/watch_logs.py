"""Live Log Watcher for Brotato Online Co-Op.

Monitors all log files simultaneously in real-time:
1. D:/Brotato_Coop_Test/logs/coop_all.log (Mod networking, RPCs, inventory)
2. %APPDATA%/Brotato/logs/godot.log (Godot engine prints, errors, crashes)
3. %APPDATA%/Brotato/logs/modloader.log (ModLoader lifecycle, hook warnings)

Usage:
    python tools/watch_logs.py
"""
import os
import sys
import time
from pathlib import Path

# Enable ANSI colors on Windows
if sys.platform == "win32":
    import ctypes
    kernel32 = ctypes.windll.kernel32
    kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)

# ANSI Color Codes
CYAN = "\033[96m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
MAGENTA = "\033[95m"
BOLD = "\033[1m"
RESET = "\033[0m"

COOP_LOG = Path(r"D:\Brotato_Coop_Test\logs\coop_all.log")
APPDATA_LOGS = Path(os.path.expandvars(r"%APPDATA%\Brotato\logs"))
GODOT_LOG = APPDATA_LOGS / "godot.log"
MODLOADER_LOG = APPDATA_LOGS / "modloader.log"
UNIFIED_OUT = Path(r"D:\Brotato_Coop_Test\logs\live_session_unified.log")

def get_log_sources():
    sources = [
        {"name": "COOP_MOD", "path": COOP_LOG, "color": CYAN, "fp": None, "offset": 0},
        {"name": "GODOT_ENGINE", "path": GODOT_LOG, "color": YELLOW, "fp": None, "offset": 0},
        {"name": "MODLOADER", "path": MODLOADER_LOG, "color": MAGENTA, "fp": None, "offset": 0},
    ]
    return sources

def main():
    print(f"{BOLD}{GREEN}==================================================================={RESET}")
    print(f"{BOLD}{GREEN}  BROTATO ONLINE CO-OP: LIVE LOG WATCHER & BUG DETECTOR            {RESET}")
    print(f"{BOLD}{GREEN}==================================================================={RESET}")
    print("Monitoring streams in real-time:")
    print(f"  * {CYAN}COOP_MOD{RESET}:      {COOP_LOG}")
    print(f"  * {YELLOW}GODOT_ENGINE{RESET}:  {GODOT_LOG}")
    print(f"  * {MAGENTA}MODLOADER{RESET}:     {MODLOADER_LOG}")
    print(f"  * Saving unified stream to: {UNIFIED_OUT}")
    print(f"\n{BOLD}Press Ctrl+C to stop watching.{RESET}\n")

    UNIFIED_OUT.parent.mkdir(parents=True, exist_ok=True)
    out_file = open(UNIFIED_OUT, "a", encoding="utf-8")

    sources = get_log_sources()
    # Seek to end on startup so we only capture events that happen while playing
    for s in sources:
        if s["path"].exists():
            s["offset"] = s["path"].stat().st_size

    error_count = 0

    try:
        while True:
            had_activity = False
            for s in sources:
                p = s["path"]
                if not p.exists():
                    continue

                curr_size = p.stat().st_size
                if curr_size < s["offset"]:
                    # File was rotated/cleared
                    s["offset"] = 0

                if curr_size > s["offset"]:
                    had_activity = True
                    try:
                        with open(p, "r", encoding="utf-8", errors="replace") as f:
                            f.seek(s["offset"])
                            new_text = f.read()
                            s["offset"] = f.tell()
                            
                            for line in new_text.splitlines():
                                line_clean = line.strip()
                                if not line_clean:
                                    continue
                                
                                is_err = any(k in line_clean for k in ["ERROR", "SCRIPT ERROR", "CRASH", "Assertion", "Exception"])
                                tag_color = RED if is_err else s["color"]
                                
                                formatted_line = f"[{tag_color}{s['name']}{RESET}] {line_clean}"
                                if is_err:
                                    error_count += 1
                                    print(f"\n{BOLD}{RED}>>> [BUG/ERROR DETECTED #{error_count}] <<<{RESET}")
                                    print(f"{BOLD}{RED}{formatted_line}{RESET}\n")
                                else:
                                    print(formatted_line)

                                # Save to disk
                                out_file.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [{s['name']}] {line_clean}\n")
                                out_file.flush()
                    except Exception as e:
                        pass

            if not had_activity:
                time.sleep(0.2)

    except KeyboardInterrupt:
        print(f"\n{BOLD}Stopping log watcher...{RESET}")
        print(f"Total bugs/errors caught this session: {BOLD}{RED if error_count > 0 else GREEN}{error_count}{RESET}")
        out_file.close()

if __name__ == "__main__":
    main()
