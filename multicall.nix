# bzip2 ships two real programs — `bzip2` (compress/decompress; also serves
# `bunzip2` and `bzcat`, which it self-detects by `strstr`-ing argv[0]) and
# `bzip2recover` (salvage blocks from a damaged .bz2). The rest (bzdiff/bzcmp,
# bzgrep/bzegrep/bzfgrep, bzmore/bzless) are /bin/sh wrappers needing an
# external shell + diff/grep/more — dropped.
#
# We post-link both programs into one multicall binary at $out/bin/bzip2 and
# expose `bunzip2`, `bzcat`, `bzip2recover` as argv[0]-dispatch UNPIN_META
# aliases (bunzip2/bzcat route to bzip2's main, which self-detects).
#
# Same ld -r + prefix-rename recipe as zip/unzip: per program we compile its
# objects from $src, `ld -r` them into one partial, then `objcopy
# --redefine-syms` renames main → <prog>_main and every other strong global
# foo → <prog>__foo (objcopy rewrites defs AND the relocations referencing
# them), so each partial is self-contained and the two can't collide. We
# compile straight from $src rather than scavenging the nixpkgs autotools/
# libtool build, because that one hides its objects in .libs as PIC .lo's.
#
# Shared by the native `build` (pkgsStatic ELF / Mach-O) and `windowsBuild`
# (mingw — bzip2.c has first-class _WIN32 support: BZ_LCCWIN32 + setmode/
# O_BINARY) paths.
{ lib }:
{ pkgs, bzip2 }:
let
  # Detect Windows from the *input* derivation's stdenv, not `pkgs`: inside
  # mkStandaloneFlake the `pkgs` handed to windowsBuild is the x86_64-linux
  # root (the cross lives inside mingwStaticCross), so its hostPlatform is
  # linux. `bzip2.stdenv.hostPlatform` is the actual mingw cross. (The cosmo
  # path renames to .exe in its own stdenv fixup, but the mingw stdenv leaves
  # `$CC -o bzip2` as `bzip2`, so we must rename it ourselves.)
  isWindows = bzip2.stdenv.hostPlatform.isWindows or false;

  multicall = bzip2.overrideAttrs (old: {
    pname = "bzip2-multi";
    outputs = [ "out" ];
    installFlags = [ ];

    postBuild = (old.postBuild or "") + ''
      set -e
      mkdir -p multicall/obj

      # libbz2 object set + per-program mains (upstream Makefile OBJS).
      LIBBZ2="blocksort huffman crctable randtable compress decompress bzlib"
      CF="-O2 -D_FILE_OFFSET_BITS=64"

      for s in $LIBBZ2; do
        $CC $CF -c "$s.c" -o "multicall/obj/$s.o"
      done
      $CC $CF -c bzip2.c        -o multicall/obj/bzip2.o
      $CC $CF -c bzip2recover.c -o multicall/obj/recover.o

      declare -A TOOLOBJS
      TOOLOBJS[bzip2]="bzip2.o blocksort.o huffman.o crctable.o randtable.o compress.o decompress.o bzlib.o"
      TOOLOBJS[bzip2recover]="recover.o"
      TOOLS="bzip2 bzip2recover"

      # Mach-O leads C symbols with '_'; detect once from bzip2.o's `main`.
      if $NM --defined-only multicall/obj/bzip2.o 2>/dev/null \
           | awk '$3=="_main"{f=1} END{exit !f}'; then up=_; else up=""; fi

      for t in $TOOLS; do
        real=""
        for o in ''${TOOLOBJS[$t]}; do
          if [ -f "multicall/obj/$o" ]; then real="$real multicall/obj/$o"
          else echo "multicall: $t object $o missing" >&2; exit 1; fi
        done
        $LD -r -o "multicall/$t.o" $real
        $NM --defined-only "multicall/$t.o" 2>/dev/null \
          | awk -v t="$t" -v up="$up" '
              $2 ~ /^[A-TX-Z]$/ && $2 != "W" && $2 != "V" {
                sym = $3
                core = sym
                if (up != "" && index(core, up) == 1) core = substr(core, 2)
                if (index(core, ".") != 0) next
                if (core !~ /^[A-Za-z_][A-Za-z0-9_]*$/) next
                if (core == "main") print sym " " up t "_main"
                else                print sym " " up t "__" core
              }' | sort -u > "multicall/$t.redef"
        [ -s "multicall/$t.redef" ] && \
          $OBJCOPY --redefine-syms="multicall/$t.redef" "multicall/$t.o"
      done

      # Dispatcher: `bzip2recover` (basename contains "recover") → recover's
      # main; everything else → bzip2_main with the ORIGINAL argv preserved, so
      # bzip2's own argv[0] check still recognises `bunzip2`/`bzcat`.
      {
        cat <<'CHEAD'
#include <string.h>
int bzip2_main(int, char **);
int bzip2recover_main(int, char **);
static void base_of(char *dst, size_t cap, const char *src) {
    const char *p = src, *s;
    s = strrchr(p, '/'); if (s) p = s + 1;
#ifdef _WIN32
    s = strrchr(p, '\\'); if (s) p = s + 1;
#endif
    size_t n = strlen(p); if (n >= cap) n = cap - 1;
    memcpy(dst, p, n); dst[n] = 0;
    if (n > 4 && strcmp(dst + n - 4, ".exe") == 0) dst[n - 4] = 0;
}
int main(int argc, char **argv) {
    char base[64];
    const char *a0 = (argc > 0 && argv[0]) ? argv[0] : "bzip2";
    base_of(base, sizeof base, a0);
    if (strstr(base, "recover")) return bzip2recover_main(argc, argv);
    return bzip2_main(argc, argv);
}
CHEAD
      } > multicall/dispatcher.c
      $CC -O2 -c -o multicall/dispatcher.o multicall/dispatcher.c

      # Final link: cc-wrapper adds -static (pkgsStatic/mingw). One pass —
      # partials are self-contained.
      $CC multicall/bzip2.o multicall/bzip2recover.o multicall/dispatcher.o \
        -o multicall/bzip2
      [ -f multicall/bzip2 ] || mv multicall/bzip2.exe multicall/bzip2
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$out/share/man/man1"
      install -m755 multicall/bzip2 "$out/bin/bzip2"
      for a in bunzip2 bzcat bzip2recover; do ln -s bzip2 "$out/bin/$a"; done
      # Upstream ships a single bzip2.1 documenting all four names; copy it per
      # applet so `unpin man bzip2 <applet>` resolves.
      for m in bzip2 bunzip2 bzcat bzip2recover; do
        cp bzip2.1 "$out/share/man/man1/$m.1"
      done
      runHook postInstall
    '';
  });

  aliased = lib.withAliases pkgs
    {
      primary = "bzip2";
      aliasesFromSymlinksIn = "bin";
    }
    multicall;
in
if isWindows
then aliased.overrideAttrs (o: {
  postFixup = (o.postFixup or "") + ''
    [ -f "$out/bin/bzip2" ] && mv "$out/bin/bzip2" "$out/bin/bzip2.exe"
  '';
})
else aliased
