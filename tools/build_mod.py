import os
import zipfile
import shutil

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODS_UNPACKED_DIR = os.path.join(BASE_DIR, "mods-unpacked")
OUTPUT_ZIP = os.path.join(BASE_DIR, "CoopAnything-BrotatoOnline.zip")

def build_zip(target_zip_path=OUTPUT_ZIP):
    print(f"Building mod zip: {target_zip_path}")
    if os.path.exists(target_zip_path):
        os.remove(target_zip_path)
        
    with zipfile.ZipFile(target_zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(MODS_UNPACKED_DIR):
            for file in files:
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, BASE_DIR)
                # Store paths with forward slashes for Godot zip compatibility
                archive_name = rel_path.replace(os.sep, '/')
                zipf.write(full_path, archive_name)
                print(f"  Added: {archive_name}")
                
    print(f"Mod successfully built: {target_zip_path} ({os.path.getsize(target_zip_path)} bytes)")

def deploy_to(game_dir):
    mods_dir = os.path.join(game_dir, "mods")
    os.makedirs(mods_dir, exist_ok=True)
    target_zip = os.path.join(mods_dir, "CoopAnything-BrotatoOnline.zip")
    build_zip(target_zip)
    print(f"Deployed to: {target_zip}")

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        deploy_to(sys.argv[1])
    else:
        build_zip()
