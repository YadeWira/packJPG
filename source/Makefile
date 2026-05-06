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

.PHONY: all dev lib dll clean linux-x64 win-x64 win-x86 all-platforms \
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

dll: CXXFLAGS += -DBUILD_DLL
dll: LDFLAGS  += -Wl,--out-implib,libpackJPG.a -fvisibility=hidden
dll: $(OBJ)
	$(CXX) -shared -o $(TARGET).dll $^ $(LDFLAGS)

clean:
	@echo clean...
	@-rm -f *.o *.a $(TARGET) $(TARGET).exe $(TARGET).dll \
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
