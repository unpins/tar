# Changelog

## [Unreleased]

### Changed

- The Windows binary is now built by the same compiler as the Linux and macOS
  ones, and is 7% smaller (1.89 MB to 1.76 MB). Checked on Windows 10: it lists
  and extracts an archive to the same files as the previous binary, and
  archives it writes with gzip, xz, zstd and bzip2 compression all read back
  correctly in the previous binary.

  It now uses the Universal C Runtime, which is part of Windows 10 and later.
  On Windows 7 or 8.1 that runtime has to be installed first — it comes through
  Windows Update. The previous binary did not need it.
