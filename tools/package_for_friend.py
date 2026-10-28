import os
import zipfile
import shutil

SOURCE_DIR = r"D:\Brotato_Coop_Test"
OUTPUT_ZIP = r"D:\Brotato_Online_Coop_Portable.zip"

EXCLUDE_DIRS = {"logs", "screenshots"}
EXCLUDE_EXTS = {".log"}

def package():
    print(f"Creating portable zip: {OUTPUT_ZIP} from {SOURCE_DIR}...")
    if os.path.exists(OUTPUT_ZIP):
        os.remove(OUTPUT_ZIP)

    file_count = 0
    with zipfile.ZipFile(OUTPUT_ZIP, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(SOURCE_DIR):
            # Prune excluded directories in-place
            dirs[:] = [d for d in dirs if d.lower() not in EXCLUDE_DIRS]
            
            for file in files:
                ext = os.path.splitext(file)[1].lower()
                if ext in EXCLUDE_EXTS:
                    continue
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, SOURCE_DIR)
                zipf.write(full_path, rel_path)
                file_count += 1
                
    size_mb = os.path.getsize(OUTPUT_ZIP) / (1024 * 1024)
    print(f"Successfully packaged {file_count} files into {OUTPUT_ZIP} ({size_mb:.2f} MB)")

if __name__ == "__main__":
    package()
