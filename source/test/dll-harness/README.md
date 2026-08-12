# packJPG DLL harness (LoadLibrary path)

Three tiny C hosts that exercise `packJPG.dll` through `LoadLibrary` +
`GetProcAddress`, the path packJPG's own CI does not cover today. No
dependencies beyond the Win32 API; every step flushes, so a hang is pinned
to an exact printed line rather than just "it stopped".

Build (from Linux, mingw-w64):

    x86_64-w64-mingw32-gcc -O2 -o host_single.exe     host_single.c
    x86_64-w64-mingw32-gcc -O2 -o host_worker.exe     host_worker_thread.c
    x86_64-w64-mingw32-gcc -O2 -o host_concurrent.exe host_concurrent.c

Run:

    host_single.exe     <packJPG.dll> <input.jpg>
    host_worker.exe     <packJPG.dll> <input.jpg>
    host_concurrent.exe <packJPG.dll> <input.jpg> <nthreads>

| file | what it covers |
|---|---|
| `host_single.c` | baseline: load, resolve, `set_intra_file_threads(1)`, compress from the main thread |
| `host_worker_thread.c` | same call from one raw `CreateThread` worker — a thread winpthreads never created |
| `host_concurrent.c` | N threads released simultaneously through an event gate, all entering the DLL at once |

## Results so far

All three PASS against the published `packJPG-5.0d-win64-lib.zip` DLL on
Windows 10 x64 (measured here) and the first two on Windows 7 SP1 x64
(measured by packJPG). `host_concurrent.exe <dll> <jpg> 4` returns 4/4 ok
with no hang.

They are therefore useful as positive smoke tests, not only as bug
reproducers: if a future change to the `dll` target or the winpthread flags
breaks the LoadLibrary path, these catch it.

## The one case they do NOT reproduce

ytool (FreePascal host) deadlocks on concurrent entry into a
posix-thread-model build of this DLL: ~0% CPU, `Stop-Process` cannot reap
it, and the `.dll` file stays locked until the machine restarts.
`ytool -t1` is fine. Since all three C hosts above are fine — including the
4-thread one — the trigger is specifically concurrency from FreePascal RTL
threads, not `LoadLibrary`, not `-static`, not the loader lock, not the
Windows version, and not concurrency as such.

ytool works around it by serializing every `pjglib_init_streams` +
`pjglib_convert_*` pair behind one lock (the same thing upstream packMP3
does), and by building its DLL with the default win32-model driver.
