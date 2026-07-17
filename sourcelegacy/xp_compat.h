#pragma once
// xp_compat.h — Windows XP compatibility layer for packJPG
// Replaces std::filesystem with Win32 API calls.
// Targets _WIN32_WINNT=0x0501 (Windows XP SP2+).

#include <windows.h>
#include <string>
#include <vector>
#include <algorithm>
#include <cctype>

// ─── Filesystem helpers ───────────────────────────────────────────────────────

// Returns true if the path exists (file or directory)
static inline bool xp_path_exists( const std::string& path ) {
    DWORD attr = GetFileAttributesA( path.c_str() );
    return attr != INVALID_FILE_ATTRIBUTES;
}

// Returns true if the path is a directory
static inline bool xp_is_directory( const std::string& path ) {
    DWORD attr = GetFileAttributesA( path.c_str() );
    return attr != INVALID_FILE_ATTRIBUTES && ( attr & FILE_ATTRIBUTE_DIRECTORY ) != 0;
}

// Deletes a file. Returns true on success.
static inline bool xp_remove_file( const std::string& path ) {
    return DeleteFileA( path.c_str() ) != 0;
}

// Returns file size in bytes, or -1 on error.
static inline long long xp_file_size( const std::string& path ) {
    WIN32_FILE_ATTRIBUTE_DATA info;
    if ( !GetFileAttributesExA( path.c_str(), GetFileExInfoStandard, &info ) )
        return -1LL;
    ULARGE_INTEGER sz;
    sz.HighPart = info.nFileSizeHigh;
    sz.LowPart  = info.nFileSizeLow;
    return (long long) sz.QuadPart;
}

// Creates a directory and all missing parents (like mkdir -p).
static inline bool xp_create_directories( const std::string& path ) {
    if ( path.empty() ) return false;
    // try creating as-is first
    if ( CreateDirectoryA( path.c_str(), NULL ) ) return true;
    if ( GetLastError() == ERROR_ALREADY_EXISTS ) return true;
    // recursively create parent
    size_t pos = path.find_last_of( "/\\" );
    if ( pos == std::string::npos ) return false;
    if ( !xp_create_directories( path.substr( 0, pos ) ) ) return false;
    if ( CreateDirectoryA( path.c_str(), NULL ) ) return true;
    return GetLastError() == ERROR_ALREADY_EXISTS;
}

// Returns true if the filename extension is .jpg, .jpeg, .pjg, or .jls (case-insensitive)
static inline bool xp_is_jpg_or_pjg( const std::string& path ) {
    size_t dot = path.rfind( '.' );
    if ( dot == std::string::npos ) return false;
    std::string ext = path.substr( dot );
    for ( auto& ch : ext ) ch = (char)tolower( (unsigned char)ch );
    return ext == ".jpg" || ext == ".jpeg" || ext == ".pjg" || ext == ".jls";
}

// Replaces extension of a path string. ext should include the dot (e.g. ".pjg").
static inline std::string xp_replace_extension( const std::string& path, const std::string& ext ) {
    size_t dot = path.rfind( '.' );
    size_t sep = path.find_last_of( "/\\" );
    // only replace if dot is after last separator
    if ( dot != std::string::npos && ( sep == std::string::npos || dot > sep ) )
        return path.substr( 0, dot ) + ext;
    return path + ext;
}

// Recursively collects .jpg/.jpeg/.pjg files from a directory into out.
static void xp_collect_files_recursive( const std::string& dir, std::vector<std::string>& out ) {
    std::string pattern = dir;
    if ( !pattern.empty() && pattern.back() != '\\' && pattern.back() != '/' )
        pattern += '\\';
    pattern += '*';

    WIN32_FIND_DATAA fdata;
    HANDLE hFind = FindFirstFileA( pattern.c_str(), &fdata );
    if ( hFind == INVALID_HANDLE_VALUE ) return;

    do {
        if ( strcmp( fdata.cFileName, "." ) == 0 || strcmp( fdata.cFileName, ".." ) == 0 )
            continue;
        std::string full = dir;
        if ( !full.empty() && full.back() != '\\' && full.back() != '/' )
            full += '\\';
        full += fdata.cFileName;

        if ( fdata.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY ) {
            xp_collect_files_recursive( full, out );
        } else if ( xp_is_jpg_or_pjg( full ) ) {
            out.push_back( full );
        }
    } while ( FindNextFileA( hFind, &fdata ) );

    FindClose( hFind );
}

// Recursive variant that records the original src_root (the dir argument
// passed to the top-level call) alongside each emitted path. v4.0c -fs
// flag uses this to mirror the source folder structure under -od.
static void xp_collect_files_recursive_with_root( const std::string& dir,
                                                  const std::string& src_root,
                                                  std::vector<std::pair<std::string,std::string>>& out ) {
    std::string pattern = dir;
    if ( !pattern.empty() && pattern.back() != '\\' && pattern.back() != '/' )
        pattern += '\\';
    pattern += '*';

    WIN32_FIND_DATAA fdata;
    HANDLE hFind = FindFirstFileA( pattern.c_str(), &fdata );
    if ( hFind == INVALID_HANDLE_VALUE ) return;

    do {
        if ( strcmp( fdata.cFileName, "." ) == 0 || strcmp( fdata.cFileName, ".." ) == 0 )
            continue;
        std::string full = dir;
        if ( !full.empty() && full.back() != '\\' && full.back() != '/' )
            full += '\\';
        full += fdata.cFileName;

        if ( fdata.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY ) {
            xp_collect_files_recursive_with_root( full, src_root, out );
        } else if ( xp_is_jpg_or_pjg( full ) ) {
            out.push_back( std::make_pair( full, src_root ) );
        }
    } while ( FindNextFileA( hFind, &fdata ) );

    FindClose( hFind );
}

// Computes the relative path from `parent` to `child` (mirrors the
// std::filesystem::relative semantics used by the modern source tree).
// Returns:
//   - the relative path with backslash separators on success
//   - "." when child equals parent
//   - empty string when there is no common prefix (i.e., child is not under parent)
// Both paths are compared case-insensitively (Windows convention).
// Trailing separators are tolerated; mixed `/` and `\` are normalised.
static inline std::string xp_relative_path( const std::string& child,
                                            const std::string& parent ) {
    if ( child.empty() || parent.empty() ) return std::string();
    // Normalise: use backslash, strip trailing separator
    auto norm = []( std::string s ) {
        for ( auto& c : s ) if ( c == '/' ) c = '\\';
        while ( !s.empty() && s.back() == '\\' ) s.pop_back();
        return s;
    };
    std::string c_n = norm( child );
    std::string p_n = norm( parent );
    if ( c_n.size() < p_n.size() ) return std::string();
    // Case-insensitive prefix compare
    for ( size_t i = 0; i < p_n.size(); ++i ) {
        char a = (char)tolower( (unsigned char)c_n[ i ] );
        char b = (char)tolower( (unsigned char)p_n[ i ] );
        if ( a != b ) return std::string();
    }
    if ( c_n.size() == p_n.size() ) return std::string( "." );
    if ( c_n[ p_n.size() ] != '\\' ) return std::string(); // partial-name match, not a child
    return c_n.substr( p_n.size() + 1 );
}
