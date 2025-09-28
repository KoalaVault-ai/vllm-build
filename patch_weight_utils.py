from cryptotensors import client_init
api_key     = os.getenv("CRYPTO_API_KEY")
model_owner = os.getenv("CRYPTO_MODEL_OWNER")
model_name  = os.getenv("CRYPTO_MODEL_NAME")
model_path  = os.getenv("CRYPTO_MODEL_PATH")

print("[boot] Client args parsed:", {
    "api_key": bool(api_key),
    "model_owner": model_owner,
    "model_name": model_name,
    "model_path": model_path,
}, flush=True)

client_init(
    api_key=str(api_key),
    model_owner=str(model_owner),
    model_name=str(model_name),
    model_path=str(model_path),
    # base_url=base_url,
)
print("[boot] Client initialized.", flush=True)
