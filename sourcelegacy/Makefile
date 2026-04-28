# packJPG XP Makefile — Windows XP (x86) target
# Requires: i686-w64-mingw32-g++ with XP-compatible runtime
#
# Usage:
#   make          -> bin/packJPG_win_xp.exe
#   make dev      -> bin/packJPG_win_xp_dev.exe (with developer functions)
#   make clean    -> remove build artifacts

TARGET   = packJPG_win_xp
CXX      = i686-w64-mingw32-g++
RC       = i686-w64-mingw32-windres

# C++14: avoids std::filesystem while keeping modern C++ features.
# _WIN32_WINNT=0x0501: targets Windows XP SP2+.
CXXFLAGS = -I. -I../source -O2 -Wall -funroll-loops -ffast-math \
           -fomit-frame-pointer -std=c++14 \
           -D_WIN32_WINNT=0x0501 -DWINVER=0x0501 \
           -D_WIN32_IE=0x0501

LDFLAGS  = -static -static-libgcc -static-libstdc++

SRC      = ../source/aricoder.cpp bitops.cpp packjpg.cpp
BIN      = bin

.DEFAULT_GOAL := all

$(BIN):
	mkdir -p $(BIN)

all: $(BIN)
	$(CXX) $(CXXFLAGS) -o $(BIN)/$(TARGET).exe $(SRC) -s $(LDFLAGS)
	@echo "[OK] $(BIN)/$(TARGET).exe"

dev: $(BIN)
	$(CXX) $(CXXFLAGS) -DDEV_BUILD -o $(BIN)/$(TARGET)_dev.exe $(SRC) -s $(LDFLAGS)
	@echo "[OK] $(BIN)/$(TARGET)_dev.exe"

clean:
	@echo clean...
	@-rm -f $(BIN)/$(TARGET).exe $(BIN)/$(TARGET)_dev.exe

.PHONY: all dev clean
