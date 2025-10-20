#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import shutil
import importlib.util
import importlib

CANDIDATES = [
    "vllm.entrypoints.openai.api_server",
]

FORBIDDEN_KEYS = ["trust-remote-code", "trust_remote_code"]

def resolve_vllm_module() -> str:
    for mod in CANDIDATES:
        try:
            if importlib.util.find_spec(mod) is not None:
                return mod
        except Exception:
            pass
    return CANDIDATES[0]

def split_args(argv):
    """Split --koalavault-* arguments from vllm arguments"""
    client, vllm = [], []
    i = 0
    while i < len(argv):
        tok = argv[i]
        if tok.startswith("--koalavault-"):
            client.append(tok)
            # If it's in the form --xxx value, consume both tokens
            if "=" not in tok and i + 1 < len(argv) and not argv[i + 1].startswith("-"):
                client.append(argv[i + 1])
                i += 2
                continue
            i += 1
        else:
            vllm.append(tok)
            i += 1
    return client, vllm

def get_arg(args, key: str):
    """Support both --key value and --key=value"""
    for i, tok in enumerate(args):
        if tok == f"--{key}" and i + 1 < len(args):
            return args[i + 1]
        if tok.startswith(f"--{key}="):
            return tok.split("=", 1)[1]
    return None

def truthy_env(name: str) -> bool:
    v = os.environ.get(name)
    if v is None:
        return False
    return str(v).strip().lower() in {"1", "true", "yes", "on"}

def find_forbidden(vllm_args):
    """Return the forbidden items (list), covering --flag / --flag=val / --flag val and related env vars."""
    hits = []

    # CLI flags
    i = 0
    n = len(vllm_args)
    while i < n:
        tok = vllm_args[i]
        for k in FORBIDDEN_KEYS:
            if tok == f"--{k}":
                # Record formats like "--k" or "--k <val>"
                if i + 1 < n and not vllm_args[i + 1].startswith("-"):
                    hits.append(f"--{k} {vllm_args[i+1]}")
                    i += 2
                    break
                else:
                    hits.append(f"--{k}")
                    i += 1
                    break
            if tok.startswith(f"--{k}="):
                hits.append(tok)
                i += 1
                break
        else:
            i += 1  # Only advance when inner loop didn't break

    # ENV var
    if truthy_env("TRANSFORMERS_TRUST_REMOTE_CODE"):
        hits.append("ENV TRANSFORMERS_TRUST_REMOTE_CODE")

    return hits

def main():
    # ---- Setup cache directory structure ----
    # This runs at container startup to ensure correct structure regardless of mount scenarios
    # Supports: --tmpfs /tmp, --tmpfs /root/.cache, or no tmpfs at all
    
    # Step 1: Create /tmp subdirectories (targets for symlinks)
    os.makedirs("/tmp/triton", exist_ok=True)
    os.makedirs("/tmp/vllm", exist_ok=True)
    os.makedirs("/tmp/torch", exist_ok=True)
    os.makedirs("/tmp/flashinfer", exist_ok=True)
    
    # Step 2: Ensure /root/.cache/huggingface is a real directory (not a symlink)
    huggingface_path = "/root/.cache/huggingface"
    if os.path.islink(huggingface_path):
        os.unlink(huggingface_path)
    os.makedirs(huggingface_path, exist_ok=True)
    
    # Step 3: Create symlinks for runtime caches
    symlink_mappings = {
        "/root/.triton": "/tmp/triton",
        "/root/.cache/vllm": "/tmp/vllm",
        "/root/.cache/torch": "/tmp/torch",
        "/root/.cache/flashinfer": "/tmp/flashinfer",
    }
    
    for link_path, target_path in symlink_mappings.items():
        # Remove existing file/directory if it's not the correct symlink
        if os.path.lexists(link_path):
            if os.path.islink(link_path):
                if os.readlink(link_path) == target_path:
                    continue  # Already correct, skip
                os.unlink(link_path)
            else:
                # It's a regular file/directory, remove it
                if os.path.isdir(link_path):
                    shutil.rmtree(link_path)
                else:
                    os.remove(link_path)
        
        # Create the symlink
        os.symlink(target_path, link_path)
    
    argv = sys.argv[1:]
    crypto_args, vllm_args = split_args(argv)

    # ---- Get API key with clear priority and logging ----
    # Priority: CLI argument > Environment variable
    api_key_from_cli = get_arg(crypto_args, "koalavault-api-key")
    api_key_from_env = os.environ.get("KOALAVAULT_API_KEY")
    
    api_key = None
    api_key_source = None
    
    if api_key_from_cli and api_key_from_env:
        # Both provided - use CLI and warn about override
        api_key = api_key_from_cli
        api_key_source = "command-line argument"
        print(
            f"[koalavault] API key provided via both CLI and environment variable.\n"
            f"[koalavault] Using CLI argument (--koalavault-api-key) - environment variable ignored.",
            flush=True
        )
    elif api_key_from_cli:
        api_key = api_key_from_cli
        api_key_source = "command-line argument"
    elif api_key_from_env:
        api_key = api_key_from_env
        api_key_source = "environment variable (KOALAVAULT_API_KEY)"
    else:
        # No API key provided
        print(
            "[koalavault] No API key provided - running in standard vLLM mode.\n",
            flush=True
        )

    # ---- Only validate koalavault parameters if API key is provided ----
    if api_key:
        print(f"[koalavault] Initializing KoalaVault mode (key from {api_key_source})...", flush=True)
        # Block trust-remote-code
        forbidden = find_forbidden(vllm_args)
        if forbidden:
            print(
                "[koalavault] Unsupported option(s) detected and blocked:\n  - "
                + "\n  - ".join(forbidden)
                + "\n[koalavault] This container **does not support trust-remote-code**. "
                  "Please remove these options/env and retry.",
                flush=True,
            )
            sys.exit(7)

        # Parse combined model parameter in format "owner/model_name"
        model_combined = get_arg(crypto_args, "koalavault-model")
        if model_combined:
            if "/" in model_combined:
                model_owner, model_name = model_combined.split("/", 1)
            else:
                print(
                    f"[koalavault] ERROR: Invalid model format: '{model_combined}'\n"
                    f"[koalavault] Expected format: owner/model_name\n"
                    f"[koalavault] Example: --koalavault-model producer/my-model",
                    flush=True
                )
                sys.exit(2)
        else:
            model_owner = None
            model_name = None
        model_path  = get_arg(vllm_args, "model")

        # Check required parameters
        missing = []
        if not model_owner or not model_name: missing.append("--koalavault-model <owner/model_name>")
        if not model_path:  missing.append("--model <path>")
        if missing:
            print(
                f"[koalavault] ERROR: Missing required parameters for KoalaVault mode:\n"
                f"[koalavault]   {', '.join(missing)}\n"
                f"[koalavault]\n"
                f"[koalavault] Example usage:\n"
                f"[koalavault]   --koalavault-api-key sk-your-api-key \\\n"
                f"[koalavault]   --koalavault-model owner/model_name \\\n"
                f"[koalavault]   --model /models/my-model (or meta-llama/Llama-3.2-1B)",
                flush=True
            )
            sys.exit(2)

        # Write back environment variables (using weird names to avoid conflicts)
        os.environ["__KV_INTERNAL_API_KEY__"] = str(api_key)
        os.environ["__KV_INTERNAL_MODEL_OWNER__"]  = str(model_owner)
        os.environ["__KV_INTERNAL_MODEL_NAME__"]   = str(model_name)
        os.environ["__KV_INTERNAL_MODEL_PATH__"]   = str(model_path)

    # ---- Start vLLM: force execution with python -m ----
    import runpy
    import traceback

    mod = resolve_vllm_module()

    sys.argv = [mod] + vllm_args  # Simulate python -m <mod> <args...>
    
    try:
        runpy.run_module(mod, run_name="__main__")
    except SystemExit as e:
        # Let uvicorn / argparse control exit code normally
        raise
    except Exception as e:
        print(f"[koalavault] Module execution failed: {e}", flush=True)
        traceback.print_exc()
        sys.exit(6)


if __name__ == "__main__":
    main()
