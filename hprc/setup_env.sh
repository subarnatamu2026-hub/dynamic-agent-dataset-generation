#!/usr/bin/env bash
# One-time environment build for HPRC. Run this INSIDE the container, in an
# interactive compute session (not on the login node), e.g.:
#
#   srun --time=02:00:00 --cpus-per-task=8 --mem=16G --pty bash
#   module load Apptainer            # (name may differ: `module spider apptainer`)
#   apptainer exec --bind /scratch $SCRATCH/craftium.sif bash hprc/setup_env.sh
#
# It builds Craftium (compiles Minetest) + installs torch into .venv, all under
# your scratch dynamic-agent-dataset-generation checkout so it persists for the array jobs.
set -e

# Keep EVERYTHING on scratch (login-home has a small ~10GB quota that uv's
# managed-Python download blows past -> "Disk quota exceeded (os error 122)").
export UV_CACHE_DIR="${SCRATCH}/.uv-cache"
export UV_PYTHON_INSTALL_DIR="${SCRATCH}/.uv-python"   # uv installs Python here (not ~/.local)
export HF_HOME="${SCRATCH}/.hf-cache"
export XDG_CACHE_HOME="${SCRATCH}/.cache"
export PIP_CACHE_DIR="${SCRATCH}/.pip-cache"
export PLAYWRIGHT_BROWSERS_PATH=0

cd "${SCRATCH}/dynamic-agent-dataset-generation"

# Craftium (engine + mods) is NOT vendored in this repo; clone the fork into
# gym_envs/craftium (the pyproject path dependency) before uv sync. Guarded so a
# rerun doesn't re-clone.
if [ ! -e gym_envs/craftium/pyproject.toml ]; then
  echo "==> Cloning craftium fork into gym_envs/craftium"
  rm -rf gym_envs/craftium
  git clone --recursive -b claude/craftium-dynamic-agents-cauneh \
    https://github.com/subarnatamu2026-hub/craftium gym_envs/craftium
fi

echo "==> Building venv (torch + craftium). This compiles Minetest; ~15-30 min."
uv sync --group cu --group env

echo "==> Sanity check:"
source .venv/bin/activate
python -c "import craftium, torch, gymnasium, numpy; print('craftium OK, torch', torch.__version__)"
python -c "import craftium, os; d=os.path.dirname(craftium.__file__); \
print('mod present:', os.path.exists(d+'/craftium-envs/openworld-creative/mods/craftium_env/dynamic_agents.lua'))"
echo "==> Done. venv at ${SCRATCH}/dynamic-agent-dataset-generation/.venv"
