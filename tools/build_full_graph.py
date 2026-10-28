"""Generate a comprehensive Graphify knowledge graph of the entire Brotato game and Online Co-Op mod.

Extracts AST entities, relations, inheritance, preloads, singleton calls, and RPCs
from both the vanilla decompiled source (D:/Brotato_Mod_Backup/DecompiledSource)
and the mod codebase (C:/Users/Vadim/.gemini/antigravity/scratch/brotato-coop).

Builds:
  - graphify-out/graph.json
  - graphify-out/graph.html
  - graphify-out/GRAPH_REPORT.md
"""
import os
import re
import sys
from pathlib import Path

# Add graphify site-packages to sys.path
GRAPHIFY_PYTHON = Path(r"C:\Users\Vadim\AppData\Roaming\uv\tools\graphifyy\Scripts\python.exe")
GRAPHIFY_SITE = Path(r"C:\Users\Vadim\AppData\Roaming\uv\tools\graphifyy\Lib\site-packages")
if str(GRAPHIFY_SITE) not in sys.path:
    sys.path.insert(0, str(GRAPHIFY_SITE))

import networkx as nx
import graphify.build as gb
import graphify.cluster as gc
import graphify.export as ge
import graphify.report as gr

ROOT_DIR = Path(__file__).resolve().parent.parent
DECOMPILED_DIR = ROOT_DIR / "DecompiledSource"
MOD_UNPACKED_DIR = ROOT_DIR / "mods-unpacked" / "CoopAnything-BrotatoOnline"
TOOLS_DIR = ROOT_DIR / "tools"
OUT_DIR = ROOT_DIR / "graphify-out"

def make_node_id(prefix: str, name: str) -> str:
    clean = re.sub(r'[^a-zA-Z0-9_]', '_', f"{prefix}_{name}").strip('_').lower()
    return clean

def extract_gdscript_file(file_path: Path, root_label: str, known_classes: dict, known_files: dict):
    nodes = []
    edges = []
    
    try:
        content = file_path.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        return {"nodes": [], "edges": []}

    rel_path = file_path.as_posix()
    file_id = make_node_id("file", rel_path)
    file_label = file_path.name
    
    file_node = {
        "id": file_id,
        "label": f"{root_label}/{file_label}",
        "file_type": "code",
        "source_file": str(file_path),
        "source_location": "L1"
    }
    nodes.append(file_node)
    known_files[file_path.stem] = file_id
    known_files[file_path.name] = file_id
    known_files[rel_path] = file_id

    lines = content.splitlines()
    current_class_id = file_id

    for line_idx, line in enumerate(lines, 1):
        line_clean = line.strip()
        
        # class_name
        m_class = re.match(r'^class_name\s+([A-Za-z0-9_]+)', line_clean)
        if m_class:
            cname = m_class.group(1)
            cid = make_node_id("class", cname)
            nodes.append({
                "id": cid,
                "label": f"class {cname}",
                "file_type": "code",
                "source_file": str(file_path),
                "source_location": f"L{line_idx}"
            })
            edges.append({
                "source": file_id,
                "target": cid,
                "relation": "defines",
                "confidence": "EXTRACTED",
                "source_file": str(file_path)
            })
            known_classes[cname] = cid
            current_class_id = cid

        # extends
        m_ext = re.match(r'^extends\s+(?:"([^"]+)"|([A-Za-z0-9_]+))', line_clean)
        if m_ext:
            target_res = m_ext.group(1) or m_ext.group(2)
            tid = make_node_id("res", target_res)
            # Create stub if not present
            nodes.append({
                "id": tid,
                "label": target_res.split('/')[-1],
                "file_type": "code",
                "source_file": str(file_path),
                "source_location": f"L{line_idx}"
            })
            edges.append({
                "source": current_class_id,
                "target": tid,
                "relation": "inherits_from",
                "confidence": "EXTRACTED",
                "source_file": str(file_path)
            })

        # func
        m_func = re.match(r'^func\s+([A-Za-z0-9_]+)\s*\((.*?)\)', line_clean)
        if m_func:
            fname = m_func.group(1)
            fid = make_node_id("fn", f"{file_path.stem}_{fname}")
            nodes.append({
                "id": fid,
                "label": f"{fname}()",
                "file_type": "code",
                "source_file": str(file_path),
                "source_location": f"L{line_idx}"
            })
            edges.append({
                "source": current_class_id,
                "target": fid,
                "relation": "contains",
                "confidence": "EXTRACTED",
                "source_file": str(file_path)
            })
            
            # Special check for RPC
            if fname.startswith("rpc_"):
                edges.append({
                    "source": fid,
                    "target": make_node_id("tag", "network_rpc"),
                    "relation": "has_tag",
                    "confidence": "EXTRACTED",
                    "source_file": str(file_path)
                })

        # preload / load
        for m_load in re.finditer(r'(?:preload|load)\s*\(\s*"([^"]+)"\s*\)', line_clean):
            load_target = m_load.group(1)
            lid = make_node_id("res", load_target)
            nodes.append({
                "id": lid,
                "label": load_target.split('/')[-1],
                "file_type": "code",
                "source_file": str(file_path),
                "source_location": f"L{line_idx}"
            })
            edges.append({
                "source": file_id,
                "target": lid,
                "relation": "imports",
                "confidence": "EXTRACTED",
                "source_file": str(file_path)
            })

        # Calls to singletons
        for s in ["RunData", "CoopService", "ProgressData", "ItemService", "ZoneService", "NetworkManager", "NetworkLogger", "ModLoaderMod"]:
            if re.search(r'\b' + s + r'\.[a-zA-Z0-9_]+', line_clean):
                sid = make_node_id("singleton", s)
                nodes.append({
                    "id": sid,
                    "label": s,
                    "file_type": "concept",
                    "source_file": str(file_path),
                    "source_location": f"L{line_idx}"
                })
                edges.append({
                    "source": current_class_id,
                    "target": sid,
                    "relation": "calls_singleton",
                    "confidence": "INFERRED",
                    "source_file": str(file_path)
                })

    return {"nodes": nodes, "edges": edges}

def extract_python_tools(tool_path: Path):
    nodes = []
    edges = []
    file_id = make_node_id("py_tool", tool_path.stem)
    nodes.append({
        "id": file_id,
        "label": f"tools/{tool_path.name}",
        "file_type": "code",
        "source_file": str(tool_path),
        "source_location": "L1"
    })
    try:
        content = tool_path.read_text(encoding="utf-8", errors="replace")
    except:
        return {"nodes": nodes, "edges": edges}

    for idx, line in enumerate(content.splitlines(), 1):
        m_def = re.match(r'^(?:async\s+)?def\s+([A-Za-z0-9_]+)', line.strip())
        if m_def:
            fn = m_def.group(1)
            fn_id = make_node_id("py_fn", f"{tool_path.stem}_{fn}")
            nodes.append({
                "id": fn_id,
                "label": f"{fn}()",
                "file_type": "code",
                "source_file": str(tool_path),
                "source_location": f"L{idx}"
            })
            edges.append({
                "source": file_id,
                "target": fn_id,
                "relation": "defines",
                "confidence": "EXTRACTED",
                "source_file": str(tool_path)
            })
        for target in ["coop_all.log", "godot.log", "modloader.log", "Brotato.exe"]:
            if target in line:
                tid = make_node_id("resource", target)
                nodes.append({
                    "id": tid,
                    "label": target,
                    "file_type": "concept",
                    "source_file": str(tool_path),
                    "source_location": f"L{idx}"
                })
                edges.append({
                    "source": file_id,
                    "target": tid,
                    "relation": "inspects" if ".log" in target else "launches",
                    "confidence": "EXTRACTED",
                    "source_file": str(tool_path)
                })

    return {"nodes": nodes, "edges": edges}

def main():
    print("=" * 70)
    print(" BUILDING BROTATO GAME & CO-OP MOD KNOWLEDGE GRAPH VIA GRAPHIFY")
    print("=" * 70)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    known_classes = {}
    known_files = {}

    extractions = []

    # 1. Scan Mod Files
    print(f"\n[1/3] Extracting Mod Files from {MOD_UNPACKED_DIR}...")
    mod_files = list(MOD_UNPACKED_DIR.rglob("*.gd"))
    print(f"      Found {len(mod_files)} mod GDScript files.")
    for mf in mod_files:
        ext = extract_gdscript_file(mf, "Mod", known_classes, known_files)
        extractions.append(ext)

    # 2. Scan Tools
    print(f"\n[2/3] Extracting Automation & QA Tools from {TOOLS_DIR}...")
    tool_files = list(TOOLS_DIR.glob("*.py"))
    print(f"      Found {len(tool_files)} tool Python files.")
    for tf in tool_files:
        ext = extract_python_tools(tf)
        extractions.append(ext)

    # 3. Scan Decompiled Game Source
    print(f"\n[3/3] Extracting Decompiled Game Source from {DECOMPILED_DIR}...")
    game_files = list(DECOMPILED_DIR.rglob("*.gd"))
    print(f"      Found {len(game_files)} game GDScript files.")
    for gf in game_files:
        ext = extract_gdscript_file(gf, "Brotato", known_classes, known_files)
        extractions.append(ext)

    total_raw_nodes = sum(len(e["nodes"]) for e in extractions)
    total_raw_edges = sum(len(e["edges"]) for e in extractions)
    print(f"\n[STATS] Extracted {total_raw_nodes} raw nodes and {total_raw_edges} raw edges.")

    # 4. Build graph via graphify
    print("\nMerging into NetworkX graph using graphify.build.build()...")
    G = gb.build(extractions, directed=False, dedup=True, root=ROOT_DIR)
    print(f"Graph built: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges.")

    # 5. Cluster via Leiden & analyze
    print("\nClustering graph using graphify.cluster.cluster()...")
    communities = gc.cluster(G)
    print(f"Clustered into {len(communities)} communities.")
    cohesion = gc.score_all(G, communities)
    labels = gc.label_communities_by_hub(G, communities)

    from graphify.analyze import god_nodes, surprising_connections, suggest_questions
    gods = god_nodes(G)
    surprises = surprising_connections(G, communities)
    questions = suggest_questions(G, communities, labels)

    # 6. Export outputs
    print("\nExporting Graphify artifacts...")
    out_json = OUT_DIR / "graph.json"
    out_html = OUT_DIR / "graph.html"
    out_report = OUT_DIR / "GRAPH_REPORT.md"

    ge.to_json(G, communities, str(out_json), force=True, community_labels=labels)
    print(f"  [SAVED] {out_json}")

    ge.to_html(G, communities, str(out_html), community_labels=labels)
    print(f"  [SAVED] {out_html}")

    detection = {"total_files": len(mod_files) + len(tool_files) + len(game_files), "total_words": 250000}
    report = gr.generate(G, communities, cohesion, labels, gods, surprises, detection,
                         {"input": 0, "output": 0}, "Brotato + Online Coop Mod", suggested_questions=questions)
    out_report.write_text(report, encoding="utf-8")
    print(f"  [SAVED] {out_report}")

    print("\n" + "=" * 70)
    print(" GRAPHIFY KNOWLEDGE GRAPH GENERATED SUCCESSFULLY!")
    print("=" * 70)

if __name__ == "__main__":
    main()
