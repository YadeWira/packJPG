# packJPG Makefile — v2.6
# Targets: linux-x64 (default), win-x64, win-x86, all-platforms

TARGET   = packJPG
CC       = clang
CPP      = clang++
RC       = windres -O coff

# Updated to C++17: std::filesystem is built-in, -lstdc++fs no longer needed.
# Removed -fsched-spec-load: GCC-only flag, unsupported by clang.
CPPFLAGS = -I. -O3 -Wall -pedantic -funroll-loops -ffast-math \
           -fomit-frame-pointer -std=c++17

LDFLAGS  = -static -static-libgcc -static-libstdc++

CSRC     = $(wildcard *.c)
CPPSRC   = $(wildcard *.cpp)
DEPS     = $(wildcard *.h) Makefile
OBJ      = $(patsubst %.c,%.o,$(CSRC)) $(patsubst %.cpp,%.o,$(CPPSRC))

# --- platform detection ------------------------------------------------------

ifeq ($(OS),Windows_NT)
CPPFLAGS +=
LDFLAGS  += -lpthread -L libwinpthread-1.dll
RES       = icons.res
UPX      := upx --best --lzma $(TARGET).exe 2>/dev/null || true
else
CPPFLAGS += -DUNIX
RC        =
RES       =
UPX       =
endif

# --- default rules -----------------------------------------------------------

%.o: %.cpp $(DEPS)
	$(CPP) -c -o $@ $< $(CPPFLAGS)

%.res: %.rc
	@-$(RC) $< $@

$(TARGET): $(OBJ) $(RES)
	$(CPP) -o $@ $^ -s $(LDFLAGS)
	$(UPX)

# --- standard targets --------------------------------------------------------

.PHONY: all dev lib dll clean linux-x64 win-x64 win-x86 all-platforms

all: $(TARGET)

dev: CPPFLAGS += -DDEV_BUILD
dev: $(TARGET)

lib: CPPFLAGS += -DBUILD_LIB
lib: $(OBJ)
	ar r $(TARGET)lib.a $(OBJ)
	ranlib $(TARGET)lib.a

dll: CPPFLAGS += -DBUILD_DLL
dll: LDFLAGS  += -Wl,--out-implib,libpackJPG.a -fvisibility=hidden
dll: $(OBJ)
	$(CPP) -shared -o $(TARGET).dll $^ $(LDFLAGS)

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
              -fomit-frame-pointer -std=c++17
CROSS_LD    = -static -static-libgcc -static-libstdc++

bin:
	mkdir -p bin

linux-x64: bin
	$(CPP) $(CPPFLAGS) -DUNIX -o bin/$(TARGET)_linux_x64 $(CPPSRC) -s $(LDFLAGS)
	@echo "[OK] bin/$(TARGET)_linux_x64"

win-x64: bin
	$(WIN64) $(CROSS_FLAGS) -o bin/$(TARGET)_win_x64.exe $(CPPSRC) -s $(CROSS_LD)
	@echo "[OK] bin/$(TARGET)_win_x64.exe"

win-x86: bin
	$(WIN32) $(CROSS_FLAGS) -o bin/$(TARGET)_win_x86.exe $(CPPSRC) -s $(CROSS_LD)
	@echo "[OK] bin/$(TARGET)_win_x86.exe"

all-platforms: linux-x64 win-x64 win-x86
	@echo ""
	@echo "Output binaries:"
	@ls -lh bin/