# Dynamic Agent Dataset Generation Repo

Headless generator for **raw world-model datasets** in
[Craftium](https://github.com/craftium-org/craftium) / VoxeLibre: a navigating
player agent plus a small set of **dynamic agents** (mobs/animals), with per-frame
ground truth. Extracted from the PERSIST project so this repo contains **only** the
dataset-generation pipeline — no world-model training code.

Each generated level produces, under `datasets/<name>/raw/<env>/<seed>/`:

| File | Contents |
|------|----------|
| `rgb.mp4` | the RGB observation video (clean: no HUD/hand) |
| `data.npz` | player + camera per frame (pos, yaw/pitch, cam_pos/dir, fov, voxel obs, actions) |
| `data_dynamic.npz` | per-frame mob ground truth (pos, velocity, yaw, collision/OBB boxes, animation, bones) |
| `level_metadata.json` | seed, spawn, minetest config |

## What each episode looks like
- **4–7 mobs** per level (varies per level; species mixed from a curated land-only pool), spawned **inside the player's forward view cone**, within ~10 blocks and soft-leashed to stay close (≤12).
- The player spawns on **dry land**, does **one slow (~3 s) 360° look-around** at a random time, then navigates normally. No continuous spinning.
- Levels where the player **enters water** or the camera **shakes violently** are **discarded and reseeded automatically**, so no bad clips are kept.

## Repository layout
```
dataset_toolkits/
  generate_raw_data.py   # main entry point (tyro CLI)
  dynamic_data.py        # reads mob log -> data_dynamic.npz
  guided_nav.py          # optional goal-directed observation controller (off by default)
utils/                   # get_file_hash/seed_everything + MultiDiscreteActionWrapper
tools/
  agent_splits.py        # deterministic 70/30 seen/unseen species split
  check_seen.py          # QA: is every mob actually on camera (>=10 frames, within 15 blocks)?
  prune_bad_levels.py    # QA: delete already-generated shaking levels
  harvest_agent_meshes.py
build_datasets.sh        # full suite: train 100 / eval1 28 / eval2 12
resume_extend.sh         # resume / grow a dataset without re-generating existing levels
smoke_test.sh            # quick 3-level test
reinstall.sh             # clone the craftium fork + build the venv (run this first)
redeploy_mods.sh         # fast redeploy of the Lua mods after a mod change (no recompile)
hprc/                    # TAMU HPRC (Grace/FASTER) Slurm pipeline for parallel generation
```

> The Craftium engine + mods are **not vendored** here; `reinstall.sh` clones them
> from the fork into `gym_envs/craftium` (git-ignored) and builds them into `.venv`.

## Setup (once)
Requires [`uv`](https://docs.astral.sh/uv/) and the Craftium system deps
(compiler, SDL2, mesa/GL, Xvfb, ffmpeg). On a machine that has those:
```bash
git clone https://github.com/subarnatamu2026-hub/dynamic-agent-dataset-generation
cd dynamic-agent-dataset-generation
./reinstall.sh          # clones the craftium fork into gym_envs/craftium + builds .venv
```
On a cluster without the system libs, use the container pipeline in [`hprc/`](hprc/README.md).

## Generate
```bash
# quick smoke test (3 levels, 600 frames = ~25 s each)
FRAMES=600 N=3 ./smoke_test.sh

# full suite (train 100 / eval1 28 / eval2 12)
./build_datasets.sh

# QA: how many mobs are actually seen on camera
python tools/check_seen.py "datasets/smoketest/raw/OpenWorldCreative-v0/*"
```

After changing the Lua mods (in the craftium fork), redeploy without a full rebuild:
```bash
./redeploy_mods.sh
```
Python-only changes need nothing — they run straight from the repo.

## Key generation options (`generate_raw_data.py`, via tyro `--flag`)
- `--num_dynamic_agents_min/max` (default 4 / 7) — mobs per level
- `--dynamic_agents_spawn_in_view` / `--dynamic_agents_spawn_view_half_angle` (45°) — spawn in front, on-screen
- `--dynamic_agents_max_radius` (10) / `--dynamic_agents_leash_radius` (12) — keep mobs close
- `--player_spin_once` + `--player_spin_seconds` (3.0) — one human-speed 360° look-around
- `--guided_navigation` (off) — opt-in tour that visits each mob
- `--skip_on_water` / `--shake_max_step` (2.0) — discard + reseed water/shaking levels
- `--ep_timesteps` (frames), `--fps_max` (24) — 600 frames ≈ 25 s

## Parallel generation on TAMU HPRC (Grace/FASTER)
See [`hprc/README.md`](hprc/README.md). In short, everything runs under `$SCRATCH`:
build the container image once, then submit the whole pipeline detached with
`hprc/submit_all.sh` — a Slurm job array where each task is a data-parallel worker
(`--rank`/`--world_size`) over a disjoint slice of level seeds, so more array
tasks = more CPU cores used at once.

## Credit
Extracted from the PERSIST world-model project; built on Craftium (a Luanti/Minetest
fork) and VoxeLibre.
