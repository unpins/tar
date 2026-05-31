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

The [Releases](https://github.com/unpins/tar/releases) page has standalone binaries for manual download.

## Man pages

`tar.1` (the bsdtar command manual), `tar.5`, and `libarchive-formats.5` are embedded in the binary — read them with `unpin man tar`. libarchive's C-library API pages (`archive_*.3`) and the man pages for the sibling tools it normally installs (`bsdcat`/`bsdcpio`/`bsdunzip`, which we don't ship) are dropped.

## Build notes

### Embedded resources

All compression and crypto code is statically linked into the binary as compiled libraries; there are no runtime data files. The man pages above ride inside the binary (no companion archive).

### Crypto backend per platform

libarchive uses crypto for hash verification (mtree/xar SHA digests) and for AES-encrypted ZIP/7z entries. Each platform picks the lightest source that supports those primitives:

- **Linux** — `mbedcrypto.a` (from mbedTLS). Replaces OpenSSL, which would otherwise drag the full provider stack (legacy + post-quantum ML-DSA/SLH-DSA) for a few SHA/AES symbols. Net effect: ~5.8 MB smaller binary, identical user-facing features.
- **macOS** — `LIBSYSTEM` (CommonCrypto / `<CommonCrypto/CommonDigest.h>`). System framework, no extra linkage.
- **Windows** — `WIN` backend (`bcrypt.dll`, the CNG API). System DLL, no extra linkage.

AES-256 encrypted ZIP extraction (`tar -xf foo.zip --passphrase=…`), encrypted 7z, and `--options=sha256digest` for mtree all work identically on every target.

### Excluded format

- **XAR** is disabled (`xarSupport = false`). XAR is Apple's legacy `.pkg` format; it requires `libxml2` (~1 MB statically), and almost no one creates XAR archives outside the macOS Installer toolchain. Reading or writing `.xar` files fails with "Unrecognized archive format". Everything else libarchive supports — POSIX/PAX/USTAR/GNU tar, gzip/xz/bzip2/zstd, ZIP, 7z, cpio, ISO9660, MTREE, RAR/RAR5 (read), LHA, AR, WARC — still works.
