"""ComfyUI node that lets Ollama and ComfyUI share one GPU.

An RTX 3060 can't hold a chat model and an image model together. Put this node
between the prompt and the text encoder. When a workflow runs it:

  1. asks Ollama to unload whatever it has loaded, and waits for the VRAM to clear
  2. flags ComfyUI to drop its own models once the job ends, so the next chat
     gets the whole GPU back

The prompt text passes through unchanged.
"""

import json
import os
import time
import urllib.error
import urllib.request

from server import PromptServer

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://ollama:11434").rstrip("/")
WAIT_SECONDS = 20


def _call(path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(
        OLLAMA_URL + path, data=data, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def _unload_ollama():
    try:
        loaded = [m["name"] for m in _call("/api/ps").get("models", [])]
        for name in loaded:
            print(f"[vram-swap] unloading {name} from Ollama")
            _call("/api/generate", {"model": name, "keep_alive": 0})
        deadline = time.time() + WAIT_SECONDS
        while loaded and time.time() < deadline:
            loaded = _call("/api/ps").get("models", [])
            if loaded:
                time.sleep(0.5)
        if loaded:
            print("[vram-swap] Ollama still has models loaded, continuing anyway")
    except (urllib.error.URLError, OSError, ValueError) as error:
        # Image generation should still try if Ollama is down.
        print(f"[vram-swap] could not reach Ollama: {error}")


class GillisVramSwap:
    CATEGORY = "utils"
    FUNCTION = "run"
    RETURN_TYPES = ("STRING",)
    RETURN_NAMES = ("text",)

    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {"text": ("STRING", {"multiline": True, "default": ""})}}

    @classmethod
    def IS_CHANGED(cls, text):
        return float("nan")  # Never cached: the swap has to happen on every run.

    def run(self, text):
        _unload_ollama()
        queue = PromptServer.instance.prompt_queue
        queue.set_flag("unload_models", True)
        queue.set_flag("free_memory", True)
        return (text,)


NODE_CLASS_MAPPINGS = {"GillisVramSwap": GillisVramSwap}
NODE_DISPLAY_NAME_MAPPINGS = {"GillisVramSwap": "Free GPU from Ollama (VRAM swap)"}
