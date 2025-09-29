import os
from cryptotensors import client_init

api_key     = os.getenv("__KV_INTERNAL_API_KEY__")
model_owner = os.getenv("__KV_INTERNAL_MODEL_OWNER__")
model_name  = os.getenv("__KV_INTERNAL_MODEL_NAME__")
model_path  = os.getenv("__KV_INTERNAL_MODEL_PATH__")

# Only initialize client if API key is provided
if api_key:
    client_init(
        api_key=str(api_key),
        model_owner=str(model_owner),
        model_name=str(model_name),
        model_path=str(model_path),
        # base_url=base_url,
    )
    print("[koalavault] Client initialized successfully.", flush=True)
else:
    print("[koalavault] Skipping client initialization.", flush=True)
