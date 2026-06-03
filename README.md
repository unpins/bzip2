# bzip2

Standalone build of [bzip2](https://sourceware.org/bzip2/) — Julian Seward's
block-sorting compressor.

[![CI](https://github.com/unpins/bzip2/actions/workflows/bzip2.yml/badge.svg)](https://github.com/unpins/bzip2/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

## Usage

Run the `bzip2` program with [unpin](https://github.com/unpins/unpin):

```bash
unpin bzip2 -z file        # compress  -> file.bz2
unpin bzip2 -d file.bz2    # decompress
```

To install it onto your PATH:

```bash
unpin install bzip2
```

Installing also creates the `bunzip2`, `bzcat` and `bzip2recover` aliases
alongside `bzip2` — each dispatches via `argv[0]` to the same binary.

## Build locally

```bash
nix build github:unpins/bzip2
./result/bin/bzip2 --help
```

Or run directly:

```bash
nix run github:unpins/bzip2
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/bzip2/releases) page has standalone binaries for manual download.

## Build notes

- Single multicall binary. `bzip2` compresses/decompresses and serves
  `bunzip2` and `bzcat` by inspecting `argv[0]`; `bzip2recover` (salvage blocks
  from a damaged `.bz2`) is a second program folded in via the same `ld -r` +
  `objcopy --redefine-syms` recipe as the Info-ZIP tools. Dropped: the
  `bzdiff`/`bzgrep`/`bzmore` `/bin/sh` wrappers (they need an external shell +
  diff/grep/more).
- **Windows** is built with mingw (not Cosmopolitan): bzip2.c has first-class
  `_WIN32` support (`BZ_LCCWIN32` → `setmode`/`O_BINARY`), so the cross
  compiles cleanly.

## Man pages

Upstream ships a single `bzip2.1` documenting every applet; it is embedded
under each name, so `unpin man bzip2` and `unpin man bzip2 bzip2recover` both
work.
