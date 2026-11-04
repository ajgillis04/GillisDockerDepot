#!/usr/bin/env python3
"""Set OpenWebUI's stored settings and model presets. Safe to run again.

OpenWebUI keeps settings in its database and ignores most environment variables
after first start, so they're written here. Run it with OpenWebUI stopped:

  docker stop openwebui.$HOST_NAME
  docker run --rm --env-file .env -v openwebui_data:/data -v "$PWD/compose/server2:/cfg:ro" \
    --entrypoint python3 ghcr.io/open-webui/open-webui:v0.13.0 /cfg/openwebui/apply-settings.py
  docker start openwebui.$HOST_NAME
"""
import json
import os
import shutil
import sqlite3
import time
import uuid

DB = "/data/webui.db"
CFG = "/cfg"
HOST = os.environ["HOST_NAME"].split("#")[0].strip()
TOKEN = os.environ["JUPYTER_SANDBOX_TOKEN"].split("#")[0].strip()
POLICY_MARK = "\n\nToday is {{CURRENT_WEEKDAY}}"

workflow = json.load(open(f"{CFG}/comfyui/z_image_turbo_api.json"))
policy = open(f"{CFG}/openwebui/tool-policy.md").read().strip()

SETTINGS = {
    # Web search
    "web.search.enable": True,
    "web.search.engine": "searxng",
    "web.search.searxng_query_url": f"http://searxng.{HOST}:8080/search",
    "web.search.result_count": 5,
    "web.loader.engine": "",  # "playwright" needs a browser this image doesn't have.
    # Image generation
    "image_generation.enable": True,
    "image_generation.engine": "comfyui",
    "image_generation.model": "z_image_turbo_int8_convrot.safetensors",
    "image_generation.size": "1024x1024",
    "image_generation.steps": 8,
    "image_generation.prompt.enable": False,
    "image_generation.comfyui.base_url": f"http://comfyui.{HOST}:8188",
    "image_generation.comfyui.workflow": json.dumps(workflow),
    "image_generation.comfyui.nodes": [
        {"type": "prompt", "key": "text", "node_ids": ["6"]},
        {"type": "model", "key": "unet_name", "node_ids": ["1"]},
        {"type": "width", "key": "width", "node_ids": ["5"]},
        {"type": "height", "key": "height", "node_ids": ["5"]},
        {"type": "n", "key": "batch_size", "node_ids": ["5"]},
        {"type": "steps", "key": "steps", "node_ids": ["9"]},
        {"type": "seed", "key": "seed", "node_ids": ["9"]},
    ],
    # Code runs server side in the locked-down sandbox, not in the browser.
    "code_execution.enable": True,
    "code_execution.engine": "jupyter",
    "code_execution.jupyter.url": "http://jupyter-sandbox:8888",
    "code_execution.jupyter.auth": "token",
    "code_execution.jupyter.auth_token": TOKEN,
    "code_interpreter.enable": True,
    "code_interpreter.engine": "jupyter",
    "code_interpreter.jupyter.url": "http://jupyter-sandbox:8888",
    "code_interpreter.jupyter.auth": "token",
    "code_interpreter.jupyter.auth_token": TOKEN,
    # Knowledge bases: keyword and vector search together, then a reranker picks the best.
    # Measured on 11,500 chunks: under 3 s for search, about 2 s to rerank 8 chunks on the CPU.
    "rag.enable_hybrid_search": True,
    "rag.reranking_model": "BAAI/bge-reranker-v2-m3",
    "rag.top_k": 12,
    "rag.top_k_reranker": 5,
    # New chats open on the fast model.
    "ui.default_models": "gillis-assistant",
}

CAPABILITIES = {
    "vision": True, "file_upload": True, "file_context": True, "web_search": True,
    "image_generation": True, "code_interpreter": True, "citations": True,
    "status_updates": True, "builtin_tools": True,
}

# gemma4:e4b scored best overall and fits 64K context on the GPU at about 75 tok/s.
# bonsai-2:27b was the best at code, at about 31 tok/s and 32K context.
MODELS = {
    "gillis-assistant": {"base": "gemma4:e4b", "num_ctx": 65536, "compact": 48000},
    "gillis-coder": {"base": "bonsai-2:27b", "num_ctx": 32768, "compact": 24000},
    "gillis-professor": {"base": "bonsai-2:27b", "num_ctx": 32768, "compact": 24000},
}

shutil.copy2(DB, f"{DB}.before-settings")
db = sqlite3.connect(DB)
now = int(time.time())

for key, value in SETTINGS.items():
    db.execute(
        "INSERT INTO config (key, value, updated_at) VALUES (?, ?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
        (key, json.dumps(value), now),
    )

for model_id, spec in MODELS.items():
    row = db.execute(
        "SELECT params, meta, name, user_id, version_id FROM model WHERE id = ?", (model_id,)
    ).fetchone()
    if row is None:
        print(f"skipped {model_id}: not found")
        continue
    params, meta = json.loads(row[0] or "{}"), json.loads(row[1] or "{}")
    name, owner, version_id = row[2], row[3], row[4]
    persona = (params.get("system") or "").split(POLICY_MARK)[0].rstrip()
    params.update(
        system=f"{persona}\n\n{policy}".strip(),
        function_calling="native",
        num_ctx=spec["num_ctx"],
        compact_token_threshold=spec["compact"],
    )
    for stale in ("num_gpu", "num_thread"):  # Ollama handles these better on its own.
        params.pop(stale, None)
    meta["capabilities"] = {**(meta.get("capabilities") or {}), **CAPABILITIES}
    meta["defaultFeatureIds"] = ["web_search", "image_generation", "code_interpreter"]
    # Stop models creating Python tools from chat: those run in OpenWebUI, outside the sandbox.
    meta["builtinTools"] = {**(meta.get("builtinTools") or {}), "tools": False}
    # Record a version too, so the model editor's history stays right and can roll back.
    snapshot = {"name": name, "base_model_id": spec["base"], "params": params,
                "meta": {k: v for k, v in meta.items() if k != "hidden"}}
    current = db.execute("SELECT snapshot FROM model_history WHERE id = ?", (version_id,)).fetchone()
    if not current or json.loads(current[0]) != snapshot:
        version_id, parent = str(uuid.uuid4()), version_id
        db.execute(
            "INSERT INTO model_history (id, model_id, parent_id, snapshot, user_id, commit_message, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (version_id, model_id, parent, json.dumps(snapshot), owner, "apply-settings.py", now),
        )
    db.execute(
        "UPDATE model SET base_model_id = ?, params = ?, meta = ?, version_id = ?, updated_at = ? WHERE id = ?",
        (spec["base"], json.dumps(params), json.dumps(meta), version_id, now, model_id),
    )
    print(f"updated {model_id} -> {spec['base']} (version {version_id[:8]})")

db.commit()
print("integrity:", db.execute("PRAGMA integrity_check").fetchone()[0])
db.close()
