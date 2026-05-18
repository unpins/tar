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
  outputs = { self, unpins-lib }:
    unpins-lib.lib.mkStandaloneFlake {
      inherit self;
      name = "tar";
      build = pkgs:
        pkgs.pkgsStatic.libarchive.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            mv "$out/bin/bsdtar" "$out/bin/tar"
            find "$out/bin" -type f -not -name tar -delete
          '';
        });
      # Same shape as native (libarchive's bsdtar renamed to tar). Imports
      # stay system-only (bcrypt/KERNEL32/msvcrt); mingwStaticCross's stdenv
      # adapter handles --enable-static --disable-shared for libarchive + its
      # deps (zlib, xz, bzip2, zstd, openssl, lzo).
      windowsBuild = pkgs:
        let cross = unpins-lib.lib.mingwStaticCross pkgs; in
        cross.libarchive.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            mv "$out/bin/bsdtar.exe" "$out/bin/tar.exe"
            find "$out/bin" -type f -not -name "tar.exe" -delete
          '';
        });
    };
}
