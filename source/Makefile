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
	c++ -I. -O2 -std=c++17 test/lib_roundtrip_test.cpp  packJPGlib.a -lpthread -o test/lib_roundtrip_test
	c++ -I. -O2 -std=c++17 test/lib_concurrent_test.cpp packJPGlib.a -lpthread -o test/lib_concurrent_test
	c++ -I. -O2 -std=c++17 test/lib_batch_test.cpp      packJPGlib.a -lpthread -o test/lib_batch_test
	c++ -I. -O2 -std=c++17 test/lib_filemode_test.cpp   packJPGlib.a -lpthread -o test/lib_filemode_test
	c++ -I. -O2 -std=c++17 test/lib_maxoutput_test.cpp  packJPGlib.a -lpthread -o test/lib_maxoutput_test
	@echo "[OK] lib tests: lib_roundtrip_test, lib_concurrent_test, lib_batch_test, lib_filemode_test, lib_maxoutput_test"

dll: CXXFLAGS += -DBUILD_DLL
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
	$(CXX) -shared -o $(TARGET).dll $^ $(LDFLAGS)

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

WIN64       = x86_64-w64-mingw32-g++
WIN32       = i686-w64-mingw32-g++
CROSS_FLAGS = -I. -O3 -Wall -funroll-loops -ffast-math \
              -fomit-frame-pointer -std=c++17 \
              -D_WIN32_WINNT=0x0601 -DWINVER=0x0601
CROSS_LD    = -static -static-libgcc -static-libstdc++

bin:
	mkdir -p bin

linux-x64: bin
	$(CXX) $(CXXFLAGS) -DUNIX -o bin/$(TARGET)_linux_x64 $(CXXSRC) -s $(LDFLAGS)
	@echo "[OK] bin/$(TARGET)_linux_x64"

win-x64: bin
	$(WIN64) $(CROSS_FLAGS) -o bin/$(TARGET)_win_x64.exe $(CXXSRC) -s $(CROSS_LD)
	@echo "[OK] bin/$(TARGET)_win_x64.exe"

win-x86: bin
	$(WIN32) $(CROSS_FLAGS) -o bin/$(TARGET)_win_x86.exe $(CXXSRC) -s $(CROSS_LD)
	@echo "[OK] bin/$(TARGET)_win_x86.exe"

all-platforms: linux-x64 win-x64 win-x86
	@echo ""
	@echo "Output binaries:"
	@ls -lh bin/
