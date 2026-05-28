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
          '';
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
          '';
        });
    };
}
