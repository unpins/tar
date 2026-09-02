{
  description = "tar (bsdtar from libarchive) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # libarchive's bsdtar instead of GNU tar (gnutar): GNU tar forks to
  # external gzip/xz/bzip2/zstd binaries via compress.c, which breaks the
  # single-binary policy. bsdtar links zlib/liblzma/libbz2/libzstd and
  # handles every common format in-process. Drop the other utils libarchive
  # installs (bsdcat/bsdcpio/bsdunzip) so the package stays one binary.
  #
  # Crypto backend: **mbedtls** instead of openssl — policy + the
  # platform-conditional dep are in docs/crypto-backend.md. tar-specific:
  # bsdtar.c never calls crypto directly, but
  # `archive_read_support_format_all()` (explicit calls, not ctors — so it IS
  # DCE-able) registers the xar/mtree/zip/7z handlers, each referencing the
  # digest/cryptor layer; bsdtar calls format_all, so the crypto members are
  # pulled in. Backed by static libcrypto.a that would mean all of OpenSSL 3.x;
  # `--with-mbedtls` keeps AES-ZIP read, mtree sha256digest, and encrypted 7z
  # working at ~500 KB instead. The details (shared libarchive, and how
  # e2fsprogs links the same crypto-enabled `.a` without pulling crypto by
  # registering only format_tar) are on the `build` fn below.
  #
  # `xarSupport=false` drops libxml2 (XAR is Apple .pkg legacy). Real
  # tar workflows don't touch XAR.
  outputs = { self, unpins-lib }:
    let
      # Curate libarchive's man to the bsdtar binary we ship as `tar`. Runs in
      # postInstall on EVERY target (native AND mingw — the cross installs the
      # same bsdtar.1/tar.5/libarchive-formats.5 pages), so each build harvests
      # its OWN curated man via withMan; no nixpkgs graft.
      #   * bsdtar.1 → tar.1  — the command manual, renamed to match our binary
      #     so `unpin man tar` resolves to it. (Without the rename, the lookup
      #     for "tar" finds the lower-numbered-section-wins `tar.5` archive
      #     *format* page instead of the command manual.) A `.so` stub goes back
      #     under the old name at the end: `bsdtar` is announced too — it is what
      #     macOS and Debian's libarchive-tools call this command — and the
      #     rename had left it as a name the user can run with nothing to read.
      #   * tar.5, libarchive-formats.5  — the two format pages bsdtar.1's
      #     SEE ALSO cites (and the only ones a tar user consults).
      # Drops libarchive's 34 archive_*.3 / libarchive*.3 C-library API pages
      # and the bsdcat/bsdcpio/bsdunzip.1 pages for the sibling tools we delete.
      # man is uncompressed at postInstall (compression runs later in
      # fixupPhase), so rename + prune the raw pages here.
      manCurate = ''
        mv "$out/share/man/man1/bsdtar.1" "$out/share/man/man1/tar.1"
        find "$out/share/man" -type f \
          ! -path '*/man1/tar.1' \
          ! -path '*/man5/tar.5' \
          ! -path '*/man5/libarchive-formats.5' \
          -delete
        find "$out/share/man" -type d -empty -delete
        printf '.so man1/tar.1\n' > "$out/share/man/man1/bsdtar.1"
      '';
    in
    unpins-lib.lib.mkStandaloneFlake {
      inherit self;
      name = "tar";
      smoke = [ "--version" ];
      smokePattern = "^bsdtar [0-9]+\\.[0-9]+";

      # Build via the unpin-llvm engine + emit a bitcode multicall module.
      # The binary is linked as `bsdtar` (libarchive's frontend) and only
      # renamed to `tar` in postInstall, so the capture sidecar is keyed on
      # `bsdtar` — which is exactly what `linkName` is for. It used to be the
      # program's `name`, and `name` is also the applet name, so the entry
      # symbol and the dispatcher's first-listed name were the build-tree
      # spelling of a command we ship as `tar`. Same two announced names either
      # way; `bsdtar` is now the alias it always was in practice.
      engine = "unpin-llvm";
      multicall = {
        programs = [{ name = "tar"; linkName = "bsdtar"; aliases = [ "bsdtar" ]; }];
      };
      # Upstream nixpkgs attr is `libarchive`; name it so the engine's stdenv
      # override targets the attr `build` actually uses.
      pkgsAttr = "libarchive";
      # Crypto backend: **mbedtls on linux** (none on darwin/windows). tar shares
      # the catalog's one libarchive (lib.unpinLibarchive), built --with-mbedtls
      # on linux — so bsdtar keeps encrypted-ZIP/7z read + mtree digests at ~500 KB
      # rather than dragging OpenSSL 3.x's ~4 MB. bsdtar calls
      # `archive_read_support_format_all()`, which references the zip/7z/mtree
      # handlers → the digest/cryptor layer → mbedtls, so those crypto members are
      # pulled into tar. The SAME shared `.a` serves e2fsprogs without dragging
      # crypto there: format_all is explicit calls (not ctors), so a static `.a`
      # pulls a crypto member only if referenced, and e2fsprogs is patched to
      # register only format_tar — it links this exact crypto-enabled libarchive
      # yet references no crypto member. One shared libarchive, deduped by path in
      # the mega; tar keeps its crypto, the fs tools stay lean. darwin/windows
      # omit mbedtls (nixpkgs-mbedtls doesn't cross/darwin-build cleanly under the
      # engine cc) — core formats + compression are unaffected there.
      build = pkgs:
        let
          lib = pkgs.lib // unpins-lib.lib;
          # The catalog's ONE libarchive — the same store derivation e2fsprogs
          # links. bsdtar is linked against THIS store libarchive.a (below), not
          # the in-tree copy, so the capture records a STOREA external depArchive
          # and the mega folds a single shared libarchive rather than baking a
          # private copy into tar's module.bc.
          la = lib.unpinLibarchive pkgs;
        in
        la.overrideAttrs (old: {
          # tar is now a CONSUMER of the shared libarchive (it links its store
          # `.a`), so name it as a buildInput. That puts `${la.lib}` in tar's
          # module manifest depInputDirs (multicallExternalDepDirs walks
          # buildInputs), so the mega resolves libarchive for tar's applet from
          # the shared copy independently — not only when e2fsprogs happens to be
          # in the same mega. Deduped by path against every other consumer.
          buildInputs = (old.buildInputs or [ ]) ++ [ la ];
          # Redirect bsdtar's link from the in-tree `libarchive.la` (which libtool
          # resolves to .libs/libarchive.a → LOCALA → internalized per package) to
          # the shared store `.a`. autoreconfHook regenerates Makefile.in from the
          # patched Makefile.am, so patch the .am. libarchive_fe.a stays in-tree
          # (tiny frontend glue, tar-only — nothing to share); the store .la also
          # carries the transitive compression -l flags, so the link is otherwise
          # unchanged. (libarchive.a still builds in-tree via lib_LTLIBRARIES but
          # bsdtar no longer links it.)
          postPatch = (old.postPatch or "") + ''
            substituteInPlace Makefile.am \
              --replace-fail 'bsdtar_LDADD= libarchive.la' 'bsdtar_LDADD= ${la.lib}/lib/libarchive.la'
          '';
          postInstall = (old.postInstall or "") + ''
            mv "$out/bin/bsdtar" "$out/bin/tar"
            find "$out/bin" -type f -not -name tar -delete
          '' + manCurate;
        });
      windowsBuild = pkgs:
        let
          cross = unpins-lib.lib.mingwStaticCross pkgs;
          la = cross.libarchive.override { xarSupport = false; };
          noOpenssl = pkgs.lib.filter
            (d: !(pkgs.lib.hasInfix "openssl" (d.name or "")));
        in
        la.overrideAttrs (old: {
          # Drop openssl (never linked under --without-openssl, and otherwise
          # dragged into the windows mega). No extra crypto backend on windows
          # either (--without-mbedtls) — same nixpkgs-mbedtls portability story as
          # darwin; tar's core formats/compression are unaffected.
          buildInputs = noOpenssl (old.buildInputs or [ ]);
          propagatedBuildInputs = noOpenssl (old.propagatedBuildInputs or [ ]);
          configureFlags = (old.configureFlags or [ ]) ++ [
            "--without-openssl"
            "--without-mbedtls"
          ];
          preFixup = ''
            sed -i $lib/lib/libarchive.la \
              -e 's|-llzo2|-L${cross.lzo}/lib -llzo2|'
          '';
          postInstall = (old.postInstall or "") + ''
            mv "$out/bin/bsdtar.exe" "$out/bin/tar.exe"
            find "$out/bin" -type f -not -name "tar.exe" -delete
          '' + manCurate;
        });
    };
}
