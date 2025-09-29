# syntax=docker/dockerfile:1.6

ARG VLLM_TAG=latest

# ---- Runtime image (directly install from source) ----
FROM vllm/vllm-openai:${VLLM_TAG} AS runtime
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 CT_ROOT=/opt/cryptotensors
ENV PY=python3 PIP="python3 -m pip"

########## Install necessary tools ########## 
# Install basic dependencies (cryptotensors requires compilation)
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      tini curl ca-certificates build-essential pkg-config libssl-dev \
      python3 python3-pip python3-dev gcc g++ \
    && rm -rf /var/lib/apt/lists/*

# Install Rust/Cargo via rustup
ENV RUSTUP_HOME=/root/.rustup CARGO_HOME=/root/.cargo PATH=/root/.cargo/bin:$PATH \
    CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable && \
    rustc -V && cargo -V

########## Inject version.json ########## 
# Write version.json into site-packages
COPY version.json /usr/local/lib/python3.12/version.json


########## Install safetensors & cryptotensors from wheels ##########
COPY *.whl /tmp/

RUN ${PY} -m pip uninstall -y safetensors || true && \
    ${PIP} install --upgrade pip && \
    ${PIP} install --no-cache-dir /tmp/cryptotensors-*.whl && \
    ${PIP} install --no-cache-dir /tmp/safetensors-*.whl && \
    rm -f /tmp/*.whl


########## Inject client_init into vllm source code ########## 
# Inject patch snippet and directly modify vLLM’s weight_utils.py inside the container
COPY patch_weight_utils.py /tmp/patch_weight_utils.py
RUN python3 - <<'PY'
import sys, sysconfig, pathlib, re
pure = pathlib.Path(sysconfig.get_paths()["purelib"])
cands = list(pure.glob("vllm/**/model_loader/weight_utils.py"))
if not cands:
    print("[ERROR] vllm weight_utils.py not found", file=sys.stderr); sys.exit(1)
dst = cands[0]
src = dst.read_text(encoding="utf-8")
snippet = pathlib.Path("/tmp/patch_weight_utils.py").read_text(encoding="utf-8").strip("\n")
if "from cryptotensors import client_init" in src:
    print("[patch] already applied:", dst)
else:
    pat = re.compile(r'(?m)^(?P<indent>[ \t]*)with\s+safe_open\(\s*st_file\s*,[^)]*\)\s+as\s+f\s*:\s*$')
    m = pat.search(src)
    if not m:
        print("[ERROR] insertion point not found (with safe_open(...): line)", file=sys.stderr); sys.exit(1)
    def indent_block(block: str, indent: str) -> str:
        return "\n".join((indent + ln if ln.strip() else ln) for ln in block.splitlines())
    patched = src[:m.start()] + indent_block(snippet, m.group("indent")) + "\n" + src[m.start():]
    dst.write_text(patched, encoding="utf-8")
    print(f"[patch] applied to {dst}")
PY

# Verify patch
RUN python3 - <<'PY'
import sys, sysconfig, pathlib
pure = pathlib.Path(sysconfig.get_paths()["purelib"])
p = list(pure.glob("vllm/**/model_loader/weight_utils.py"))[0]
ok = "from cryptotensors import client_init" in p.read_text(encoding="utf-8")
print(f"[verify] {p} contains client_init? -> {ok}")
sys.exit(0 if ok else 2)
PY

########## Inject and modify entry script ########## 
# boot script
COPY boot.py /usr/local/bin/boot
RUN chmod +x /usr/local/bin/boot

WORKDIR ${CT_ROOT}
ENTRYPOINT ["/usr/bin/tini","-g","--","/usr/local/bin/boot"]
