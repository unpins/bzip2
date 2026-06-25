{
  description = "bzip2 (bzip2 + bzip2recover) as a single self-contained binary";

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
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "bzip2";
      # No winManRoot: the shared multicall.nix installPhase copies upstream's
      # single bzip2.1 to the four applet pages (bzip2/bunzip2/bzcat/
      # bzip2recover) into $out/share/man on EVERY target, so the windows .exe
      # harvests its OWN curated man — same set as native, no nixpkgs graft.
      # `--help` prints the version banner (to stderr; action-build matches
      # stdout+stderr) and exits 0 without reading stdin. `--version` is not a
      # real flag — bzip2 would treat it as "compress stdin to stdout".
      smoke = [ "--help" ];
      smokePattern = "Version 1\\.0\\.8";

      # The standalone self-folds bzip2 + bzip2recover into one dispatcher from
      # the captured module.bc; ./multicall.nix's ld-r/objcopy fold can't run on
      # the engine's -flto bitcode, so it's reserved for the Windows (mingw)
      # path. bunzip2/bzcat are bzip2's argv[0] self-dispatch → aliases; only
      # bzip2 and bzip2recover are real programs.
      engine = "unpin-llvm";
      multicall = {
        programs = [
          { name = "bzip2"; aliases = [ "bunzip2" "bzcat" ]; }
          { name = "bzip2recover"; }
        ];
      };
      # linux + darwin both self-fold through the engine (bitcode module), like
      # coreutils — no hand-rolled ld-r/objcopy fold (that recipe is ELF-only and
      # doesn't port to Mach-O). darwin needs --disable-shared pushed via
      # configureFlagsArray: nix-lib strips it from the Nix list on darwin (to
      # keep libSystem dynamic), and without it bzip2's libtool builds a libbz2
      # dylib that ld64 rejects with -soname. windows still uses ./multicall.nix.
      build = pkgs:
        if pkgs.stdenv.hostPlatform.isDarwin
        then pkgs.pkgsStatic.bzip2.overrideAttrs (o: {
          preConfigure = (o.preConfigure or "") + ''
            configureFlagsArray+=("--disable-shared")
          '';
        })
        else pkgs.pkgsStatic.bzip2;
      windowsBuild = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; bzip2 = (ulib.mingwStaticCross pkgs).bzip2; };
    };
}
