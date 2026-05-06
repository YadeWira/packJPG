# packJPG legacy Makefile — Windows XP/Vista/7/8 (x86 + x64) targets
# Requires: i686-w64-mingw32-g++ and x86_64-w64-mingw32-g++ with XP-compatible runtime
#
# Usage:
#   make          -> bin/packJPG_win_legacy_x86.exe + bin/packJPG_win_legacy_x64.exe
#   make x86      -> bin/packJPG_win_legacy_x86.exe only
#   make x64      -> bin/packJPG_win_legacy_x64.exe only
#   make dev      -> bin/packJPG_win_legacy_x86_dev.exe (with developer functions)
#   make clean    -> remove build artifacts

CXX_X86  = i686-w64-mingw32-g++
CXX_X64  = x86_64-w64-mingw32-g++

# C++14: avoids std::filesystem while keeping modern C++ features.
# _WIN32_WINNT=0x0501: targets Windows XP SP2+ (works for both x86 and x64
# legacy editions; Vista/Win7/Win8 also satisfied).
# v4.0d: -flto enables link-time optimization (mingw-w64 GCC supports it).
CXXFLAGS = -I. -I../source -O2 -Wall -funroll-loops -ffast-math \
           -fomit-frame-pointer -flto -std=c++14 \
           -D_WIN32_WINNT=0x0501 -DWINVER=0x0501 \
           -D_WIN32_IE=0x0501

LDFLAGS  = -static -static-libgcc -static-libstdc++ -flto

SRC      = ../source/aricoder.cpp bitops.cpp packjpg.cpp
BIN      = bin

T_X86    = $(BIN)/packJPG_win_legacy_x86.exe
T_X64    = $(BIN)/packJPG_win_legacy_x64.exe
T_DEV    = $(BIN)/packJPG_win_legacy_x86_dev.exe

.DEFAULT_GOAL := all

$(BIN):
	mkdir -p $(BIN)

all: x86 x64

x86: $(BIN)
	$(CXX_X86) $(CXXFLAGS) -o $(T_X86) $(SRC) -s $(LDFLAGS)
	@echo "[OK] $(T_X86)"

x64: $(BIN)
	$(CXX_X64) $(CXXFLAGS) -o $(T_X64) $(SRC) -s $(LDFLAGS)
	@echo "[OK] $(T_X64)"

dev: $(BIN)
	$(CXX_X86) $(CXXFLAGS) -DDEV_BUILD -o $(T_DEV) $(SRC) -s $(LDFLAGS)
	@echo "[OK] $(T_DEV)"

clean:
	@echo clean...
	@-rm -f $(BIN)/packJPG_win_legacy_*.exe $(BIN)/packJPG_win_xp*.exe

.PHONY: all x86 x64 dev clean
