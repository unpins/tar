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
  # handles every common format in-process.
  outputs = { self, unpins-lib }:
    unpins-lib.lib.mkStandaloneFlake {
      inherit self;
      name = "tar";
      windows = true;
    };
}
