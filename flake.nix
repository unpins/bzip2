{
  description = "bzip2 (bzip2 + bzip2recover) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # bzip2 + bzip2recover folded into one multicall binary at $out/bin/bzip2,
  # with `bunzip2`/`bzcat`/`bzip2recover` as argv[0]-dispatch UNPIN_META
  # aliases. Windows goes through mingw — bzip2.c carries first-class _WIN32
  # support (BZ_LCCWIN32: setmode/O_BINARY), no Cosmopolitan needed.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
      # Curate the embedded man to exactly the shipped applets. nixpkgs bzip2
      # installs pages for the bz* shell-script wrappers (bzgrep/bzdiff/bzless/
      # bzmore/…) — which we DON'T ship — and none for bzip2recover (upstream
      # documents it inside bzip2.1). withMan would otherwise embed the script
      # pages and leave bzip2recover undocumented.
      curateMan = o: {
        postInstall = (o.postInstall or "") + ''
          md="''${man:-$out}/share/man/man1"
          if [ -d "$md" ]; then
            [ -e "$md/bzip2recover.1" ] || cp "$md/bzip2.1" "$md/bzip2recover.1"
            find "$md" -mindepth 1 -maxdepth 1 \
              ! -name 'bzip2.1*' ! -name 'bunzip2.1*' \
              ! -name 'bzcat.1*' ! -name 'bzip2recover.1*' \
              -delete
          fi
        '';
      };
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "bzip2";
      # No winManRoot: the cross build curates the same four applet pages the
      # native one does, so the .exe harvests its OWN man rather than a nixpkgs
      # graft. `--help` prints the version banner (to stderr; action-build
      # matches stdout+stderr) and exits 0 without reading stdin. `--version` is
      # not a real flag — bzip2 would read it as "compress stdin to stdout".
      smoke = [ "--help" ];
      smokePattern = "Version 1\\.0\\.8";

      # Every target self-folds bzip2 + bzip2recover from the captured
      # module.bc. bunzip2/bzcat are bzip2's own argv[0] self-dispatch, so they
      # are aliases; only bzip2 and bzip2recover are real programs.
      engine = "unpin-llvm";
      multicall = {
        windows = true;
        programs = [
          { name = "bzip2"; aliases = [ "bunzip2" "bzcat" ]; }
          { name = "bzip2recover"; }
        ];
      };
      # darwin needs --disable-shared pushed through configureFlagsArray:
      # nix-lib strips it from the Nix list there (to keep libSystem dynamic),
      # and without it bzip2's libtool builds a libbz2 dylib that ld64 rejects
      # with -soname.
      build = pkgs:
        if pkgs.stdenv.hostPlatform.isDarwin
        then pkgs.pkgsStatic.bzip2.overrideAttrs (o: (curateMan o) // {
          preConfigure = (o.preConfigure or "") + ''
            configureFlagsArray+=("--disable-shared")
          '';
        })
        else pkgs.pkgsStatic.bzip2.overrideAttrs curateMan;
      windowsBuild = pkgs: (ulib.mingwStaticCross pkgs).bzip2.overrideAttrs curateMan;
    };
}
