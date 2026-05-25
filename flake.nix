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
  # Crypto backend: **mbedtls** instead of openssl. bsdtar.c never calls
  # crypto directly, but `archive_read_support_format_all()` registers
  # the xar/mtree/zip/7z format handlers, each of which references
  # `EVP_DigestInit`. Static-linking against libcrypto.a then drags all
  # of OpenSSL 3.x with every provider (~4 MB, including post-quantum
  # ML-DSA/SLH-DSA), which is wildly disproportionate to the bsdtar use
  # case. libarchive's `--with-mbedtls` selects mbedcrypto for the same
  # symbols (SHA1/SHA256/AES/PBKDF2/HMAC) at a fraction of the cost
  # (~500 KB vs ~4 MB). Feature parity preserved: AES-encrypted ZIP
  # read, mtree sha256digest, encrypted 7z, all still work.
  #
  # `xarSupport=false` drops libxml2 (XAR is Apple .pkg legacy). Real
  # tar workflows don't touch XAR.
  #
  # `--without-openssl --with-mbedtls` go on every target so the
  # configure invocation stays symmetric, but mbedtls only ends up in
  # the *Linux* buildInputs because:
  #   - darwin: libarchive auto-prefers LIBSYSTEM (CommonCrypto) via
  #     configure.ac's host_os case before reaching the mbedtls block.
  #   - windows: libarchive auto-prefers CNG (bcrypt.dll, system).
  #   - musl Linux: no LIBC crypto, no LIBSYSTEM, no WIN crypto — only
  #     mbedtls/nettle/openssl available, so the dep must be present.
  # `--with-mbedtls` is safe to always pass: if no mbedtls is in the
  # include/lib path, libarchive's probe fails silently and falls back
  # to whatever it found first (LIBSYSTEM/WIN).
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
