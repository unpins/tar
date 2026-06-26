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
  # `archive_read_support_format_all()` registers the xar/mtree/zip/7z
  # handlers, each referencing `EVP_DigestInit` — constructor self-
  # registration the linker can't DCE — so static libcrypto.a would drag
  # all of OpenSSL 3.x. `--with-mbedtls` keeps AES-ZIP read, mtree
  # sha256digest, and encrypted 7z working at ~500 KB instead of ~4 MB.
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
      #     *format* page instead of the command manual.)
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
      '';
    in
    unpins-lib.lib.mkStandaloneFlake {
      inherit self;
      name = "tar";

      # Build via the unpin-llvm engine + emit a bitcode multicall module.
      # The binary is linked as `bsdtar` (libarchive's frontend) and only
      # renamed to `tar` in postInstall, so the capture sidecar — and thus the
      # program entry — is keyed on `bsdtar`; `tar` rides along as the alias.
      engine = "unpin-llvm";
      multicall = {
        programs = [{ name = "bsdtar"; aliases = [ "tar" ]; }];
      };
      # Upstream nixpkgs attr is `libarchive`; name it so the engine's stdenv
      # override targets the attr `build` actually uses.
      pkgsAttr = "libarchive";
      build = pkgs:
        let
          isLinux = pkgs.stdenv.hostPlatform.isLinux;
          noOpenssl = pkgs.lib.filter
            (d: !(pkgs.lib.hasInfix "openssl" (d.name or "")));
        in
        (pkgs.pkgsStatic.libarchive.override { xarSupport = false; }).overrideAttrs (old: {
          # Crypto backend: mbedtls on LINUX only. mbedtls is libarchive's
          # optional crypto (encrypted ZIP/7z read, mtree message digests); it is
          # small and avoids dragging all of OpenSSL in via EVP constructor
          # self-registration. nixpkgs libarchive keeps openssl as an
          # unconditional buildInput AND names it in preFixup, so under the engine
          # cc OpenSSL would otherwise be compiled with -flto (tens of minutes per
          # arch) for a lib that is never linked — filter it out everywhere and
          # rewrite preFixup to keep only the lzo .la fixup.
          #
          # darwin omits the extra crypto backend (--without-mbedtls): the
          # nixpkgs-mbedtls + darwin engine-cc combination does not build cleanly
          # (clang-detected-as-GNU cmake flags, -static-libgcc in the test link, a
          # threading postConfigure that can't find its script). tar's core —
          # every archive format and compression — is unaffected; only the niche
          # encrypted-archive/digest features are unavailable there.
          buildInputs = (noOpenssl (old.buildInputs or [ ]))
            ++ pkgs.lib.optional isLinux pkgs.pkgsStatic.mbedtls;
          propagatedBuildInputs = noOpenssl (old.propagatedBuildInputs or [ ]);
          configureFlags = (old.configureFlags or [ ]) ++ [ "--without-openssl" ]
            ++ (if isLinux then [ "--with-mbedtls" ] else [ "--without-mbedtls" ]);
          preFixup = ''
            sed -i $lib/lib/libarchive.la \
              -e 's|-llzo2|-L${pkgs.pkgsStatic.lzo}/lib -llzo2|'
          '';
          postInstall = (old.postInstall or "") + ''
            mv "$out/bin/bsdtar" "$out/bin/tar"
            find "$out/bin" -type f -not -name tar -delete
          '' + manCurate;
        } // pkgs.lib.optionalAttrs (!isLinux) {
          # darwin: libarchive's libtool otherwise builds a libarchive.dylib and
          # passes -soname, which ld64.lld rejects ("unknown argument '-soname'").
          # Push --disable-shared via configureFlagsArray — nix-lib strips a plain
          # --disable-shared from the Nix configureFlags list on darwin (to keep
          # libSystem dynamic), so the bash array is the way to make it stick.
          preConfigure = (old.preConfigure or "") + ''
            configureFlagsArray+=("--disable-shared")
          '';
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
