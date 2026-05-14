# tar

Standalone build of [tar](https://www.libarchive.org/) — specifically `bsdtar` from libarchive, not GNU tar.

[![CI](https://github.com/unpins/tar/actions/workflows/tar.yml/badge.svg)](https://github.com/unpins/tar/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

## Why bsdtar instead of GNU tar?

GNU tar (`gnutar`) handles compressed archives by forking to external `gzip` / `xz` / `bzip2` / `zstd` binaries — that breaks the single-binary distribution model. `bsdtar` links zlib / liblzma / libbz2 / libzstd directly and handles every common format in-process.

The CLI is compatible for everyday use (`-c`, `-x`, `-t`, `-z`, `-j`, `-J`, `--zstd`, …). For GNU-tar-specific flags (`--owner=`, `--no-same-owner`, etc.) consult `man bsdtar`.

## Installation

Install with [unpin](https://github.com/unpins/unpin):

```bash
unpin tar
```

Or run without installing:

```bash
unpin run tar
```

## Build locally

```bash
nix build github:unpins/tar
./result/bin/tar --version
```

Or run directly:

```bash
nix run github:unpins/tar -- --version
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/tar/releases) page has standalone binaries and a `.tar.zst` data archive (man pages and completions) for manual download.
