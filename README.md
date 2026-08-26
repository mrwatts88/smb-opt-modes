# smb-opt-modes — engine modifications from the SMB1 TAS project

A **5,921-line patch** against [MrWint/smb-opt](https://github.com/MrWint/smb-opt), pinned at
**`daa44287bc9ccab7e85b430e80bf7dff77542542`** ("worlds 3-8"), plus the tooling needed to apply,
rebuild and verify it.

Extracted 2026-08-26 from a private research project that attempted to beat HappyLee's 2011
"warps" TAS of *Super Mario Bros.* (TASVideos #1715M, 17,868 frames). **The attempt did not
find a faster route.** The engine work is worth keeping anyway — it is the part that generalises.

## What upstream is, and what this adds

`smb-opt` is a player-physics-only model of SMB1 (enemies ignored, 10–12 byte states, IDA\* with
precomputed exact x/y-gain heuristics), used by MrWint for segment searches. This patch extends it
along four axes.

### 1. Enemy modelling (upstream ignores enemies entirely)
- **`src/w11enemies.rs`**, **`src/w42enemies.rs`** *(new)* — per-level enemy models, difftested to
  **0 diffs** against the real core over random input batteries including stomps.
- Motivation: several candidate paths that the physics-only model called optimal were rejected by a
  core replay because an enemy was in the way. A model that cannot see enemies cannot certify a path.

### 2. A whole new case: 4-2 and its warp zone
- **`src/case/w42.rs`** *(new)* — 4-2 main area, warp-zone geometry, pipe entries, the lift.
- Plus ~20 other `src/case/*.rs` touched for the route's levels.

### 3. Two new admissible heuristics
- **`src/heuristics/ygate.rs`** *(new)* — a vertical gate: to be at some `x` you must first have been
  above height `h`, priced by a per-surface reachability table. Includes a `Blocker` term (a maximal
  solid run in a column costs the **min over going above or below it**, so it asserts no
  impossibility and stays admissible). Audited: 2,000 trials / 6,942 admissibility checks / **0
  violations**.
- **`src/heuristics/drift.rs`** *(new)* — bounds the collision-minted scroll offset.
- **`SMBOPT_YGATE_EXPLAIN=<x>`** dumps the gate's per-surface reasoning for matching states, and
  **`SMBOPT_DUMP_ENDCLASSES=1`** prints, per distinct return cost, the envelope of the classes
  carrying it. Both exist because a bound you cannot interrogate is a bound you cannot debug.

### 4. The bucketed ("diversity") beam — the most reusable idea here
Upstream's beam keeps the *N* lowest-`h` records per layer. That is a **global single-key greedy
order**, and it is structurally blind to any maneuver that must **pay before it gains**: such a
maneuver has worsening `h` on exactly the layers it needs to survive, so it is deleted before it can
pay.

`--beam-buckets` keeps the best *N* **per bucket** over coarse physical axes instead. This was not
theoretical — switching it on moved a result that a single-key beam had reported as a hard limit
(a 19-frame held-Left minting maneuver, i.e. motion *away* from the goal, which the low-`h` beam
deleted on its first frame).

Available axes: `off` (scroll offset), `y`, `spd`, `sub` (x-subpixel phase), `vf` (vertical force),
and **`cls`**. The `cls` axis carries `(x_spd_abs, moving_dir, facing_dir, is_on_ground,
running_speed)` — added after two independent negatives turned out to have been produced by a key
that contained **none** of those five fields, while the quantity being searched for depended on all
of them. The states it was looking for were landing frames, which an `h`-ranked beam always discards
in favour of the faster state in the same speed band.

**Generalisable lesson:** if a search's key cannot represent the answer, widening the search does not
help — and the failure is silent, because the run still terminates normally and reports a clean dry.

### Also added
`--stop-step` (stop at a layer and checkpoint), `--resume` (continue from a layer dir),
`--check-path N` (audit a reference path's bound and goal at startup, before layer 1 — far cheaper
than a zero-slack exhaustive rung), `--acc-mb`, `--lift`.

## Applying it

```sh
git clone https://github.com/MrWint/smb-opt.git
cd smb-opt
git checkout daa44287bc9ccab7e85b430e80bf7dff77542542
git apply /path/to/smb-opt-modes.patch
```

Upstream needs **Rust nightly-2018-06-01**. `Dockerfile.smbopt` pins it; building natively on a
modern toolchain will not work without a port.

```sh
docker build -f Dockerfile.smbopt -t smbopt .
docker run --rm -v "$PWD":/work -w /work smbopt cargo build --release
```

## Control gate — run this after every rebuild and cite it

```sh
target/release/smb-opt bfscx W42Main <wr_inputs.bin> 6584 575 587 --lift 0 --check-path 12
```

Must print layer sizes **6, 16, 34, 70, 134, 673, 3472, 16472, 69489, 257001**. Any deviation means
the build does not match the one every recorded result came from. This gate caught a real
mis-build; it is not ceremony.

## Regenerating the patch

`regen_patch.sh` rebuilds the patch from a working clone, with guards learned the hard way:

- **The clone must sit at the pin with every modification as an uncommitted working-tree change.**
  The patch is `git diff` against that pin, so committing in the clone moves `HEAD` and makes
  `git diff` return **empty** — regenerating a patch that silently applies nothing.
- **Untracked `.rs` files must be `git add -N`'d first**, or `git diff` omits them. A regen that
  dropped three new source files applied cleanly and then failed the build.

Both failure modes produce a patch that *looks* fine and silently does the wrong thing, which is why
the script refuses rather than warns: it aborts if `HEAD` is not the pin, if the result is under 100
lines, or if it would shrink the existing patch by more than 10%.

## Files

| file | what |
|---|---|
| `smb-opt-modes.patch` | the 5,921-line diff (5 new source files, ~30 modified) |
| `regen_patch.sh` | regenerate from a clone, with the guards above |
| `Dockerfile.smbopt` | the nightly-2018-06-01 build environment |
| `mac_sync_engine.sh` | hard-reset a clone to the pin, reapply, rebuild, stamp provenance |
| `mac_run.sh` | run the binary in the container; **refuses (exit 3) if the built patch's sha256 does not match the current one** |

`mac_run.sh`'s refusal exists because a stale binary produces plausible numbers with no error
anywhere. Provenance was enforced, not documented.

## License / attribution

Upstream `smb-opt` is MrWint's work; this repository contains **only a diff against it** plus build
tooling, and carries no upstream source. Refer to the upstream repository for its license and
respect it. The modifications here are released for anyone who finds them useful.
