# packJPG Makefile — v2.7 (v4.0d speed polish: LTO, native, PGO targets)
# Targets: linux-x64 (default), win-x64, win-x86, all-platforms,
#          native (-march=native), pgo (2-phase profile-guided build)

TARGET   = packJPG
CC       ?= clang
CXX      ?= clang++
RC       = windres -O coff

# v4.0d: -flto enables link-time optimization across translation units.
# Compatible with both gcc and clang. Negligible binary-size impact, ~2-5%
# faster runtime. Updated to C++17: std::filesystem is built-in.
# Removed -fsched-spec-load: GCC-only flag, unsupported by clang.
CXXFLAGS = -I. -O3 -Wall -pedantic -funroll-loops -ffast-math \
           -fomit-frame-pointer -flto -std=c++17

LDFLAGS  = -flto
LIBS     = -lpthread

# --- JPEG-LS support (optional, requires libcharls-dev + libjxl-dev) ---------
# Auto-detect: try compiling a one-liner that includes charls/charls.h.
# Override with  make JLS=1  (force on)  or  make JLS=0  (force off).
# Cross-compile targets (win-*) default to JLS=0 and use the vendored
# winlibs/ static libs instead (see below) — no mingw packages exist.
# dll auto-detects winlibs/ the same way (see DLL_WINLIBS wiring below).
#
# Native Linux prefers the vendored static libs under linuxlibs/ (see below)
# over this dynamic-link probe — a dynamically-linked binary depends on
# whatever libjxl/libcharls .so happens to be installed on the BUILD machine,
# which silently breaks the .deb on any other distro/version (this bit the
# v5.0a release: built against libjxl.so.0.7 on the CI runner, installed fine
# via apt but crashed at runtime on a system with only libjxl.so.0.11).
# Static linking removes the runtime dependency entirely.
JLS ?= $(shell echo 'int main(){}' | $(CXX) $(CXXFLAGS) -x c++ -lcharls -ljxl -ljxl_threads -o /dev/null - 2>/dev/null && echo 1 || echo 0)
HAVE_LINUXLIBS_X64 := $(wildcard linuxlibs/x86_64/libcharls.a)
ifneq ($(HAVE_LINUXLIBS_X64),)
  CXXFLAGS += -DHAVE_JPEGLS -DCHARLS_STATIC -DJXL_STATIC_DEFINE -Iwinlibs/include
  LIBS     += linuxlibs/x86_64/libcharls.a linuxlibs/x86_64/libjxl.a \
              linuxlibs/x86_64/libjxl_threads.a linuxlibs/x86_64/libjxl_cms.a \
              linuxlibs/x86_64/liblcms2.a linuxlibs/x86_64/libhwy.a \
              linuxlibs/x86_64/libbrotlienc.a linuxlibs/x86_64/libbrotlidec.a \
              linuxlibs/x86_64/libbrotlicommon.a
else ifeq ($(JLS),1)
  CXXFLAGS += -DHAVE_JPEGLS
  LIBS     += -lcharls -ljxl -ljxl_threads
endif

# --- Windows JPEG-LS (vendored) ----------------------------------------------
# No mingw packages of CharLS/libjxl exist, so the static libs are cross-
# compiled once and vendored under winlibs/ instead of built per-release —
# see winlibs/README.md for the reproducible build recipe. Auto-detects via
# file presence; a checkout missing winlibs/ (e.g. a stripped-down fork)
# falls back to no-JPEG-LS on Windows rather than failing the build.
#
# Built with the posix-thread-model mingw compiler (-posix suffix — see
# WIN64/WIN32 and the dll target below), used uniformly by every Windows
# target (win-x64/win-x86 CLI and the dll): the plain/win32-
# model alias is a portability trap on two fronts — it doesn't implement
# std::async/std::future at all on some distros' mingw-w64 packaging
# (compile-time errors, found pinning CI to ubuntu-22.04), and separately
# it crashes the DLL at DLL_PROCESS_DETACH. A single posix-built vendor set
# avoids maintaining two ABI-incompatible copies (their libjxl_threads.a
# would otherwise reference __gthr_win32_* symbols, not __gthr_posix_*).
WINLIBS_INC  = -Iwinlibs/include
WINJLS_DEFS  = -DHAVE_JPEGLS -DCHARLS_STATIC -DJXL_STATIC_DEFINE
# Link order matters: libcharls before libjxl before libjxl's own deps.
WINLIBS_X64  = winlibs/x86_64/libcharls.a winlibs/x86_64/libjxl.a \
               winlibs/x86_64/libjxl_threads.a winlibs/x86_64/libjxl_cms.a \
               winlibs/x86_64/liblcms2.a winlibs/x86_64/libhwy.a \
               winlibs/x86_64/libbrotlienc.a winlibs/x86_64/libbrotlidec.a \
               winlibs/x86_64/libbrotlicommon.a
WINLIBS_X86  = winlibs/i686/libcharls.a winlibs/i686/libjxl.a \
               winlibs/i686/libjxl_threads.a winlibs/i686/libjxl_cms.a \
               winlibs/i686/liblcms2.a winlibs/i686/libhwy.a \
               winlibs/i686/libbrotlienc.a winlibs/i686/libbrotlidec.a \
               winlibs/i686/libbrotlicommon.a
HAVE_WINLIBS_X64 := $(wildcard winlibs/x86_64/libcharls.a)
HAVE_WINLIBS_X86 := $(wildcard winlibs/i686/libcharls.a)

# dll doesn't go through CROSS_FLAGS/WIN64/WIN32 (build_lib_pkg.sh invokes it
# directly via CXX=<mingw-triple>-posix, sharing plumbing with the native
# Linux dll/so targets), so arch must be sniffed from $(CXX)'s name instead
# of a distinct target name.
ifneq ($(findstring i686,$(CXX)),)
  DLL_ARCH         := i686
  HAVE_DLL_WINLIBS := $(HAVE_WINLIBS_X86)
  DLL_WINLIBS      := $(WINLIBS_X86)
else
  DLL_ARCH         := x86_64
  HAVE_DLL_WINLIBS := $(HAVE_WINLIBS_X64)
  DLL_WINLIBS      := $(WINLIBS_X64)
endif

CSRC     = $(wildcard *.c)
CXXSRC   = $(wildcard *.cpp)
DEPS     = $(wildcard *.h) Makefile
OBJ      = $(patsubst %.c,%.o,$(CSRC)) $(patsubst %.cpp,%.o,$(CXXSRC))

# --- platform detection ------------------------------------------------------

ifeq ($(OS),Windows_NT)
CXXFLAGS +=
LIBS     += -L libwinpthread-1.dll
RES       = icons.res
UPX      := upx --best --lzma $(TARGET).exe 2>/dev/null || true
LDFLAGS   = -static -static-libgcc -static-libstdc++
else
CXXFLAGS += -DUNIX
RC        =
RES       =
UPX       =
# Statically link libgcc/libstdc++ so the released binary/.so doesn't
# require a minimum libstdc++.so.6 version at runtime — same portability
# class of fix as the vendored static CharLS/libjxl (see linuxlibs/
# README.md) and the CI build-image pin (see .github/workflows/ci.yml): a
# binary built with a newer GCC on a newer distro otherwise refuses to
# start on an older one. Added to CXXFLAGS (not LDFLAGS) since `so:`
# compiles+links in one invocation without referencing $(LDFLAGS).
CXXFLAGS += -static-libgcc -static-libstdc++
endif

# --- default rules -----------------------------------------------------------

%.o: %.cpp $(DEPS)
	$(CXX) -c -o $@ $< $(CXXFLAGS)

%.res: %.rc
	@-$(RC) $< $@

$(TARGET): $(OBJ) $(RES)
	$(CXX) -o $@ $^ -s $(LDFLAGS) $(LIBS)
	$(UPX)

# --- standard targets --------------------------------------------------------

.PHONY: all dev lib lib-tests dll so clean linux-x64 win-x64 win-x86 all-platforms \
        native pgo pgo-clean pja pja-tests pja-clean

all: $(TARGET)

dev: CXXFLAGS += -DDEV_BUILD
dev: $(TARGET)

# v4.0d: native build — adds -march=native -mtune=native for max-perf binaries
# built from source on the user's machine. Not used for distribution releases.
native: CXXFLAGS += -march=native -mtune=native
native: $(TARGET)

# v4.0d: profile-guided optimization. Two-phase build:
#   1. Build with -fprofile-generate, run on a representative encode workload
#   2. Rebuild with -fprofile-use linking the .gcda profile data
# Override PGO_WORKLOAD to point at a richer corpus:
#   make pgo PGO_WORKLOAD=/path/to/many/jpgs
PGO_WORKLOAD ?= ../test-files
pgo: pgo-clean
	@echo "[PGO] Phase 1: compile with -fprofile-generate"
	$(MAKE) all "CXXFLAGS=$(CXXFLAGS) -fprofile-generate" \
	            "LDFLAGS=$(LDFLAGS) -fprofile-generate"
	@echo "[PGO] Running workload from $(PGO_WORKLOAD) (encode + decode)"
	@mkdir -p /tmp/packjpg_pgo_work
	@cp $(PGO_WORKLOAD)/*.jpg /tmp/packjpg_pgo_work/ 2>/dev/null || \
	   { echo "ERROR: no jpgs in $(PGO_WORKLOAD)"; exit 1; }
	@cd /tmp/packjpg_pgo_work && $(CURDIR)/$(TARGET) a --no-pause -f ./*.jpg \
	    >/dev/null 2>&1 || true
	@# El `|| true` de arriba es correcto --packJPG sale != 0 si CUALQUIER
	@# archivo del lote avisa-- pero se traga tambien un fallo total. Sin
	@# .pjg no hay carga de trabajo, y la fase 2 se compila con un perfil
	@# vacio: mas lento que no hacer PGO, y en silencio.
	@n=`ls /tmp/packjpg_pgo_work/*.pjg 2>/dev/null | wc -l`; \
	 if [ "$$n" -eq 0 ]; then \
	   echo "ERROR: la carga de trabajo no produjo ni un .pjg -- perfil vacio"; \
	   exit 1; \
	 fi; echo "[PGO] $$n .pjg generados"
	@echo "[PGO] Workload phase 2: decode the just-encoded .pjg files"
	@cd /tmp/packjpg_pgo_work && find . -maxdepth 1 -name '*.jpg' -delete \
	    && $(CURDIR)/$(TARGET) x --no-pause -f ./*.pjg >/dev/null 2>&1 || true
	@n=`ls /tmp/packjpg_pgo_work/*.jpg 2>/dev/null | wc -l`; \
	 if [ "$$n" -eq 0 ]; then \
	   echo "ERROR: la fase de decodificacion no reconstruyo ni un .jpg"; \
	   exit 1; \
	 fi; echo "[PGO] $$n .jpg reconstruidos"
	@echo "[PGO] Phase 2: rebuild with -fprofile-use"
	@rm -f *.o lib_*.o $(TARGET)
	$(MAKE) all "CXXFLAGS=$(CXXFLAGS) -fprofile-use -Wno-missing-profile" \
	            "LDFLAGS=$(LDFLAGS) -fprofile-use"
	@rm -rf /tmp/packjpg_pgo_work
	@echo "[PGO] Done. $(TARGET) is now PGO-optimized."

pgo-clean:
	@rm -f *.o *.gcda $(TARGET) $(TARGET).exe

# Los objetos de la libreria se compilan APARTE, con el prefijo lib_.
#
# Antes `lib` reusaba $(OBJ) con un CXXFLAGS especifico del target. Los .o no
# recuerdan con que flags se compilaron, asi que un `make all` seguido de
# `make lib` archivaba los objetos del CLI --sin -DBUILD_LIB-- y producia un
# packJPGlib.a con CERO simbolos pjglib_*. Sin error, sin warning: el fallo
# aparece recien en el link del consumidor, como "undefined reference to
# pjglib_init_streams", que no dice nada sobre la causa.
#
# build_lib_pkg.sh ya hacia `make clean && make lib` para esquivarlo, y CI corre
# sobre checkout limpio, asi que nadie lo estaba pisando. Lo destapo `make
# pja-tests`, que necesita la .a y no puede exigir un arbol limpio.
LIBOBJ = $(OBJ:%.o=lib_%.o)

lib_%.o: %.cpp $(DEPS)
	$(CXX) -c -o $@ $< $(CXXFLAGS) -DBUILD_LIB

lib: $(LIBOBJ)
	@# Same thread-model rule as the dll target below. No check for a "mingw"
	@# name is needed and none is made: native drivers (g++, clang++) report
	@# "Thread model: posix", so this can only ever fire on a win32-model
	@# cross driver. Keying on the driver's *name* instead would leave any
	@# win32-model driver not called *mingw* silently unguarded.
	@#
	@# What this refuses: producing a win32-model packJPGlib.a. Two concrete
	@# consequences, neither of them subtle once you hit them —
	@#   1. winlibs/ (CharLS, libjxl and deps) are posix-built, so a win32 .a
	@#      hands the consumer undefined references to __gthr_win32_mutex_*
	@#      at THEIR link step, pointing at our library for their driver choice.
	@#   2. the win32 model ships an incomplete std::async/std::future in some
	@#      mingw-w64 packagings, and its thread_local teardown faults at exit
	@#      (the reason the dll target has refused it since v4.0e).
	@#
	@# What this does NOT and CANNOT catch is the mismatch that actually bit a
	@# consumer (packMP3): a *posix* .a absorbed into a win32-model host binary.
	@# That links clean, exit 0, no warning, and then deadlocks the first time
	@# the decoder takes a lock — process pinned at ~0% CPU, no error, no crash.
	@# Measured on real Windows x64 with one .a linked both ways: -posix
	@# round-trips byte-exact in ~104 ms, the plain driver never returns from
	@# decompression (killed at 90 s having burned 0.09 s of CPU). Nothing in
	@# the .a, the build or the API can detect that downstream, which is why
	@# packjpglib.h carries a thread-model warning for consumers.
	@model=`$(CXX) -v 2>&1 | sed -n 's/^Thread model: //p'`; \
	 case "$$model" in \
	   win32) echo "ERROR: $(CXX) uses the win32 thread model — refusing to build"; \
	          echo "       packJPGlib.a with it. The vendored winlibs (CharLS,"; \
	          echo "       libjxl) are posix-built, so this .a would hand your"; \
	          echo "       consumers undefined references to __gthr_win32_mutex_*;"; \
	          echo "       the win32 model also has an incomplete std::async and"; \
	          echo "       faulting thread_local teardown. Rebuild with posix:"; \
	          echo "         make lib CXX=$(CXX)-posix"; \
	          exit 1 ;; \
	 esac
	ar r $(TARGET)lib.a $(LIBOBJ)
	ranlib $(TARGET)lib.a
	@# La .a sin simbolos pjglib_* es el modo de falla de arriba. Verificarlo
	@# aca cuesta nada y convierte un fallo silencioso en uno inmediato.
	@n=`nm $(TARGET)lib.a 2>/dev/null | grep -c "T pjglib" || true`; \
	 if [ "$$n" -lt 1 ]; then \
	   echo "ERROR: $(TARGET)lib.a no exporta ningun simbolo pjglib_*."; \
	   echo "       Se compilo sin -DBUILD_LIB. Proba 'make clean' y de nuevo."; \
	   rm -f $(TARGET)lib.a; exit 1; \
	 fi; \
	 echo "[OK] $(TARGET)lib.a ($$n simbolos pjglib_*)"

# Build the static lib and the test harnesses. Tests:
#   lib_roundtrip_test  — mem-to-mem round-trip byte-equality
#   lib_concurrent_test — N threads hammering pjglib_convert_*
#   lib_batch_test      — pjglib_convert_batch byte-exact across a grid
lib-tests: lib
	c++ -I. -O2 -std=c++17 test/lib_roundtrip_test.cpp  packJPGlib.a $(LIBS) -o test/lib_roundtrip_test
	c++ -I. -O2 -std=c++17 test/lib_concurrent_test.cpp packJPGlib.a $(LIBS) -o test/lib_concurrent_test
	c++ -I. -O2 -std=c++17 test/lib_batch_test.cpp      packJPGlib.a $(LIBS) -o test/lib_batch_test
	c++ -I. -O2 -std=c++17 test/lib_filemode_test.cpp   packJPGlib.a $(LIBS) -o test/lib_filemode_test
	c++ -I. -O2 -std=c++17 test/lib_maxoutput_test.cpp  packJPGlib.a $(LIBS) -o test/lib_maxoutput_test
	@echo "[OK] lib tests: lib_roundtrip_test, lib_concurrent_test, lib_batch_test, lib_filemode_test, lib_maxoutput_test"

dll: JLS=0
dll: CXXFLAGS += -DBUILD_DLL
ifneq ($(HAVE_DLL_WINLIBS),)
dll: CXXFLAGS += $(WINJLS_DEFS) $(WINLIBS_INC)
endif
# Self-contained DLL: statically link libgcc / libstdc++ / winpthread so the
# shipped packJPG.dll has no external runtime DLL dependencies (it can be
# dropped next to a host .exe on a clean Win7/Win10 box). Without these,
# cross-compiling from Linux leaves the DLL depending on libgcc_s_seh-1.dll
# and libstdc++-6.dll. -s strips symbols. -Wl,-Bstatic forces the static
# winpthread (std::thread/std::async pull it in).
dll: LDFLAGS  += -Wl,--out-implib,libpackJPG.a -fvisibility=hidden \
                 -static -static-libgcc -static-libstdc++ \
                 -Wl,-Bstatic -lpthread -s
dll: $(OBJ)
	@# CRITICAL: the DLL must be built with the *posix* MinGW thread model.
	@# The codec uses non-trivial thread_local objects (std::unique_ptr/std::string).
	@# Under the win32 thread model, their __cxa_thread_atexit destructors crash
	@# (0xC0000005) at DLL_PROCESS_DETACH on real Windows after the first convert —
	@# the conversion succeeds, then the process faults on exit. The posix model
	@# (winpthread-backed __cxa_thread_atexit) tears them down cleanly.
	@# Build with: make dll CXX=x86_64-w64-mingw32-g++-posix
	@model=`$(CXX) -v 2>&1 | sed -n 's/^Thread model: //p'`; \
	 case "$$model" in \
	   win32) echo "ERROR: $(CXX) uses the win32 thread model — the DLL would crash"; \
	          echo "       at exit on real Windows. Rebuild with the posix model:"; \
	          echo "         make dll CXX=$(CXX)-posix"; \
	          exit 1 ;; \
	 esac
ifneq ($(HAVE_DLL_WINLIBS),)
	$(CXX) -shared -o $(TARGET).dll $^ $(LDFLAGS) $(DLL_WINLIBS)
else
	@echo "[--] winlibs/$(DLL_ARCH) not found — building dll without JPEG-LS"
	$(CXX) -shared -o $(TARGET).dll $^ $(LDFLAGS)
endif

# --- Unix shared library (.so) -----------------------------------------------
# Native Linux/Unix shared object. Same C-linkage API as the Windows DLL.
# BUILD_LIB enables the pjglib_* entry points; BUILD_SO tags them with default
# visibility so they stay exported under -fvisibility=hidden. Compiled +
# linked in one step with -fPIC (the shared .o's differ from the static ones,
# so this target does not reuse $(OBJ)). No thread-model caveat here — that
# bug is specific to MinGW DLLs on Windows.
#   make so            -> libpackJPG.so (default visibility only for the API)
SONAME = lib$(TARGET).so
so:
	$(CXX) $(CXXFLAGS) -DBUILD_LIB -DBUILD_SO -fPIC -fvisibility=hidden \
	       -shared -Wl,-soname,$(SONAME) -o $(SONAME) $(CXXSRC) -s $(LIBS)
	@echo "[OK] $(SONAME) — exported symbols:"
	@nm -D --defined-only $(SONAME) | awk '{print "      "$$3}' | grep pjglib_ || true

# --- contenedor PJA (Rust) ---------------------------------------------------
# Deliberadamente FUERA de `all`. El codec se compila sin Rust instalado y va a
# seguir siendo asi: quien solo quiera packJPG no necesita una toolchain mas.
# `make pja` es el opt-in.
#
# CARGO se puede pisar (make pja CARGO=/ruta/cargo). Si no esta, el target
# falla con una instruccion, no con "command not found" a 40 lineas de
# profundidad.
CARGO    ?= cargo
PJA_DIR   = pja
PJA_LIB   = $(PJA_DIR)/target/release/libpjaffi.a

$(PJA_LIB): $(wildcard $(PJA_DIR)/*/src/*.rs) $(wildcard $(PJA_DIR)/*/Cargo.toml) $(PJA_DIR)/Cargo.toml
	@command -v $(CARGO) >/dev/null 2>&1 || { \
	  echo "ERROR: no encuentro '$(CARGO)'. El contenedor PJA se compila con"; \
	  echo "       la toolchain de Rust (https://rustup.rs), que NO hace falta"; \
	  echo "       para packJPG en si. Instalala, o pasa la ruta:"; \
	  echo "         make pja CARGO=/ruta/a/cargo"; \
	  exit 1; }
	$(CARGO) build --release --manifest-path $(PJA_DIR)/Cargo.toml

pja: $(PJA_LIB)
	@echo "[OK] $(PJA_LIB)"

# pjatool y test_frontera son consumidores de C++ de la frontera FFI.
# pjatool ademas usa la libreria de packJPG, asi que necesita packJPGlib.a
# — o sea -DBUILD_LIB. Sin eso el link se cae con undefined reference a
# pjglib_init_streams, que no dice nada sobre la causa.
pja-tests: $(PJA_LIB) lib
	$(CXX) $(CXXFLAGS) -I$(PJA_DIR)/include $(PJA_DIR)/test_frontera.cpp \
	    $(PJA_LIB) $(LDFLAGS) $(LIBS) -ldl -o $(PJA_DIR)/test_frontera
	$(CXX) $(CXXFLAGS) -DBUILD_LIB -I. -I$(PJA_DIR)/include $(PJA_DIR)/pjatool.cpp \
	    $(TARGET)lib.a $(PJA_LIB) $(LDFLAGS) $(LIBS) -ldl -o $(PJA_DIR)/pjatool
	@echo "[OK] pja tests: $(PJA_DIR)/test_frontera, $(PJA_DIR)/pjatool"
	@echo "     las pruebas de Rust van aparte: $(CARGO) test --release --manifest-path $(PJA_DIR)/Cargo.toml"

# Aparte de `clean` a proposito: target/ de cargo son cientos de megas de
# dependencias compiladas y borrarlo cuesta minutos de rebuild. `clean` saca
# solo lo que produce este Makefile.
pja-clean:
	@echo pja-clean...
	@-rm -rf $(PJA_DIR)/target
	@-rm -f $(PJA_DIR)/test_frontera $(PJA_DIR)/pjatool

clean:
	@echo clean...
	@-rm -f $(PJA_DIR)/test_frontera $(PJA_DIR)/pjatool
	@-rm -f *.o *.a $(TARGET) $(TARGET).exe $(TARGET).dll *.so \
	        bin/$(TARGET)_linux_x64 \
	        bin/$(TARGET)_win_x64.exe \
	        bin/$(TARGET)_win_x86.exe

# --- cross-compilation targets -----------------------------------------------
#
# Requires mingw-w64:
#   Ubuntu/Debian : sudo apt install mingw-w64
#   Arch          : sudo pacman -S mingw-w64-gcc
#   macOS         : brew install mingw-w64
#
# Usage:
#   make linux-x64      -> bin/packJPG_linux_x64
#   make win-x64        -> bin/packJPG_win_x64.exe
#   make win-x86        -> bin/packJPG_win_x86.exe
#   make all-platforms  -> all three

# -posix (not the plain/win32-model alias): win32 thread model doesn't
# implement std::async/std::future on some distros' mingw-w64 packaging
# (compile-time "declared but never defined" errors) — found pinning CI to
# ubuntu-22.04, where the default alias differs from what happened to work
# on other distros. -posix is winpthread-backed, unambiguous everywhere.
WIN64       = x86_64-w64-mingw32-g++-posix
WIN32       = i686-w64-mingw32-g++-posix
CROSS_FLAGS = -I. -O3 -Wall -funroll-loops -ffast-math \
              -fomit-frame-pointer -std=c++17 \
              -D_WIN32_WINNT=0x0601 -DWINVER=0x0601
CROSS_LD    = -static -static-libgcc -static-libstdc++
# WINLIBS_INC/WINJLS_DEFS/WINLIBS_X64/WINLIBS_X86/HAVE_WINLIBS_X64/X86 are
# defined earlier (near the JLS auto-detect section) so the dll target can
# reference them too.

bin:
	mkdir -p bin

linux-x64: bin
	$(CXX) $(CXXFLAGS) -DUNIX -o bin/$(TARGET)_linux_x64 $(CXXSRC) -s $(LDFLAGS) $(LIBS)
	@echo "[OK] bin/$(TARGET)_linux_x64"

win-x64: JLS=0
win-x64: bin
ifneq ($(HAVE_WINLIBS_X64),)
	$(WIN64) $(CROSS_FLAGS) $(WINJLS_DEFS) $(WINLIBS_INC) -o bin/$(TARGET)_win_x64.exe $(CXXSRC) -s $(CROSS_LD) $(WINLIBS_X64)
else
	@echo "[--] winlibs/x86_64 not found — building win-x64 without JPEG-LS"
	$(WIN64) $(CROSS_FLAGS) -o bin/$(TARGET)_win_x64.exe $(CXXSRC) -s $(CROSS_LD)
endif
	@echo "[OK] bin/$(TARGET)_win_x64.exe"

win-x86: JLS=0
win-x86: bin
ifneq ($(HAVE_WINLIBS_X86),)
	$(WIN32) $(CROSS_FLAGS) $(WINJLS_DEFS) $(WINLIBS_INC) -o bin/$(TARGET)_win_x86.exe $(CXXSRC) -s $(CROSS_LD) $(WINLIBS_X86)
else
	@echo "[--] winlibs/i686 not found — building win-x86 without JPEG-LS"
	$(WIN32) $(CROSS_FLAGS) -o bin/$(TARGET)_win_x86.exe $(CXXSRC) -s $(CROSS_LD)
endif
	@echo "[OK] bin/$(TARGET)_win_x86.exe"

all-platforms: linux-x64 win-x64 win-x86
	@echo ""
	@echo "Output binaries:"
	@ls -lh bin/
