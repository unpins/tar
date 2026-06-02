{
  description = "Standalone build of tar (bsdtar from libarchive)";

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
      build = pkgs:
        (pkgs.pkgsStatic.libarchive.override { xarSupport = false; }).overrideAttrs (old: {
          buildInputs = (old.buildInputs or [ ])
            ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.pkgsStatic.mbedtls;
          configureFlags = (old.configureFlags or [ ]) ++ [
            "--without-openssl"
            "--with-mbedtls"
          ];
          postInstall = (old.postInstall or "") + ''
            mv "$out/bin/bsdtar" "$out/bin/tar"
            find "$out/bin" -type f -not -name tar -delete
          '' + manCurate;
        });
      windowsBuild = pkgs:
        let
          cross = unpins-lib.lib.mingwStaticCross pkgs;
          la = cross.libarchive.override { xarSupport = false; };
        in
        la.overrideAttrs (old: {
          configureFlags = (old.configureFlags or [ ]) ++ [
            "--without-openssl"
            "--with-mbedtls"
          ];
          postInstall = (old.postInstall or "") + ''
            mv "$out/bin/bsdtar.exe" "$out/bin/tar.exe"
            find "$out/bin" -type f -not -name "tar.exe" -delete
          '' + manCurate;
        });
    };
}
