# Environment

Exact versions used in the research campaign.

## CPython

| Component | Value |
|---|---|
| Version | CPython 3.15.0a7+ |
| Commit (campaign) | `c32e264227b` (April 1, 2026) |
| Commit (gh-144681 crash) | `6908372fb81` (March 2, 2026) |
| Commit (gh-144681 fixed) | `c32e264227b` |
| Commit (lowmem bug found) | `c32e264227b` (April 1, 2026) |
| Commit (lowmem bug resolved) | `d0e7c6acc93` (April 14, 2026) |
| Build flags | `--with-pydebug --enable-experimental-jit` |
| JIT threshold | 63 (lowered via `lafleur-jit-tweak`, default ~4,096) |
| Branch | `main` |

## lafleur

| Component | Value |
|---|---|
| Repository | https://github.com/devdanzin/lafleur |
| Branch | `main` |
| Install | `pip install -e .` from cloned source |
| Patches required | 4 compatibility patches for CPython 3.15 (see README) |

## System packages

```bash
sudo apt install -y \
  build-essential git tmux clang \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
  libsqlite3-dev libffi-dev liblzma-dev uuid-dev \
  libfiu-dev fiu-utils
```

## OS and hardware

| Component | Value |
|---|---|
| OS | Ubuntu 22.04 LTS (WSL2 on Windows 11) |
| Architecture | x86-64 |
| CPU | AMD Ryzen 9 9800X3D |
| Cores | 6 physical / 12 logical |
| RAM | 7.61 GB allocated to WSL2 |
| Storage | Local SSD + tmpfs RAM disk at `/mnt/fuzz_ram` (2 GB) |

## Additional build configurations

| Instance | Extra configure flags |
|---|---|
| ASAN | `CC=clang CFLAGS="-fsanitize=address -fno-omit-frame-pointer" LDFLAGS="-fsanitize=address"` |
| UBSAN | `CC=clang CFLAGS="-fsanitize=undefined -fno-omit-frame-pointer" LDFLAGS="-fsanitize=undefined"` |
| Free-threaded | `--disable-gil` |

All three also require `--with-pydebug --enable-experimental-jit` and `lafleur-jit-tweak` applied before building.
