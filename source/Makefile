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
        native pgo pgo-clean

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
	@cd /tmp/packjpg_pgo_work && $(CURDIR)/$(TARGET) a -np -o ./*.jpg \
	    >/dev/null 2>&1 || true
	@echo "[PGO] Workload phase 2: decode the just-encoded .pjg files"
	@cd /tmp/packjpg_pgo_work && find . -maxdepth 1 -name '*.jpg' -delete \
	    && $(CURDIR)/$(TARGET) x -np -o ./*.pjg >/dev/null 2>&1 || true
	@echo "[PGO] Phase 2: rebuild with -fprofile-use"
	@rm -f *.o $(TARGET)
	$(MAKE) all "CXXFLAGS=$(CXXFLAGS) -fprofile-use -Wno-missing-profile" \
	            "LDFLAGS=$(LDFLAGS) -fprofile-use"
	@rm -rf /tmp/packjpg_pgo_work
	@echo "[PGO] Done. $(TARGET) is now PGO-optimized."

pgo-clean:
	@rm -f *.o *.gcda $(TARGET) $(TARGET).exe

lib: CXXFLAGS += -DBUILD_LIB
lib: $(OBJ)
	ar r $(TARGET)lib.a $(OBJ)
	ranlib $(TARGET)lib.a

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

clean:
	@echo clean...
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
