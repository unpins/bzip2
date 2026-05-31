{
  description = "Standalone build of bzip2";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # bzip2 + bzip2recover folded into one multicall binary at $out/bin/bzip2,
  # with `bunzip2`/`bzcat`/`bzip2recover` as argv[0]-dispatch UNPIN_META
  # aliases. See ./multicall.nix. Windows goes through mingw — bzip2.c carries
  # first-class _WIN32 support (BZ_LCCWIN32: setmode/O_BINARY), no Cosmopolitan
  # needed.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
      pkgsX = unpins-lib.inputs.nixpkgs.legacyPackages.x86_64-linux;
      # The Windows binary's man is grafted from nixpkgs' bzip2.man, which
      # carries all ten pages (the bzdiff/bzgrep/bzmore shell-script docs too).
      # We ship only bzip2/bunzip2/bzcat/bzip2recover, so pin a curated tree —
      # upstream has a single bzip2.1, copied per applet (the native side does
      # the same in the multicall installPhase).
      winMan = pkgsX.runCommand "bzip2-win-man" { } ''
        mkdir -p "$out/share/man/man1"
        for p in bzip2 bunzip2 bzcat bzip2recover; do
          zcat ${pkgsX.bzip2.man}/share/man/man1/bzip2.1.gz > "$out/share/man/man1/$p.1"
        done
      '';
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "bzip2";
      winManRoot = winMan;
      # `--help` prints the version banner (to stderr; action-build matches
      # stdout+stderr) and exits 0 without reading stdin. `--version` is not a
      # real flag — bzip2 would treat it as "compress stdin to stdout".
      smoke = [ "--help" ];
      smokePattern = "Version 1\\.0\\.8";
      build = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; bzip2 = pkgs.pkgsStatic.bzip2; };
      windowsBuild = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; bzip2 = (ulib.mingwStaticCross pkgs).bzip2; };
    };
}
