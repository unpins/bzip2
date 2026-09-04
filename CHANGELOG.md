# Changelog

## [Unreleased]

### Changed

- The Windows binary is now built by the same compiler as the Linux and macOS
  ones, and links against the Universal C Runtime, which is part of Windows 10
  and later. On Windows 7 or 8.1 that runtime has to be installed first — it
  comes through Windows Update. The previous release's binary did not need it.
