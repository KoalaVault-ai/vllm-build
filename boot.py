#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
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
    """Split --crypto_* arguments from vllm arguments"""
    client, vllm = [], []
    i = 0
    while i < len(argv):
        tok = argv[i]
        if tok.startswith("--crypto_") or tok.startswith("--crypto-"):
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
    print("[boot] Using patched boot script v2025-09-28", flush=True)
    argv = sys.argv[1:]
    crypto_args, vllm_args = split_args(argv)

    # ---- Block trust-remote-code ----
    forbidden = find_forbidden(vllm_args)
    if forbidden:
        print(
            "[boot] Unsupported option(s) detected and blocked:\n  - "
            + "\n  - ".join(forbidden)
            + "\n[boot] This container **does not support trust-remote-code**. "
              "Please remove these options/env and retry.",
            flush=True,
        )
        sys.exit(7)

    # ---- ENV takes priority, CLI as fallback ----
    base_url = os.environ.get("BASE_URL")
    api_key  = os.environ.get("API_KEY") or get_arg(crypto_args, "crypto_api_key")

    model_owner = get_arg(crypto_args, "crypto_model_owner")
    model_name  = get_arg(crypto_args, "crypto_model_name")
    model_path  = get_arg(vllm_args, "model")

    # Debug (do not print key in plaintext)
    print("[boot] Resolved config:", {
        "api_key_provided": bool(api_key),
        "model_owner": model_owner,
        "model_name": model_name,
        "base_url": base_url,
        "model_path": model_path,
    }, flush=True)

    # Check required parameters
    missing = []
    if not api_key:     missing.append("API_KEY or --crypto_api_key")
    if not model_owner: missing.append("--crypto_model_owner")
    if not model_name:  missing.append("--crypto_model_name")
    if not model_path:  missing.append("--model")
    if not base_url:    missing.append("BASE_URL")
    if missing:
        print(f"[boot] Missing required params: {', '.join(missing)}", flush=True)
        sys.exit(2)

    # Write back environment variables
    os.environ["CRYPTO_API_KEY"]      = str(api_key)
    os.environ["CRYPTO_MODEL_OWNER"]  = str(model_owner)
    os.environ["CRYPTO_MODEL_NAME"]   = str(model_name)
    os.environ["CRYPTO_MODEL_PATH"]   = str(model_path)
    os.environ["CRYPTO_BASE_URL"]     = str(base_url)
    os.environ["MODELVAULT_BASE_URL"] = str(base_url)

    # client init
    try:
        from cryptotensors import client_init
        client_init(
            api_key=api_key,
            model_owner=model_owner,
            model_name=model_name,
            model_path=model_path,
        )
        print("[boot] Client initialized.", flush=True)
    except Exception as e:
        print(f"[boot] client_init failed: {e}", flush=True)
        sys.exit(3)

    # ---- Start vLLM: force execution with python -m ----
    import runpy

    mod = resolve_vllm_module()
    print(f"[boot] Executing module via runpy: {mod}", flush=True)

    sys.argv = [mod] + vllm_args  # Simulate python -m <mod> <args...>
    try:
        runpy.run_module(mod, run_name="__main__")
    except SystemExit as e:
        # Let uvicorn / argparse control exit code normally
        raise
    except Exception as e:
        print(f"[boot] run_module({mod}) failed: {e}", flush=True)
        sys.exit(6)


if __name__ == "__main__":
    main()
