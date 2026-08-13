/* Decisive test for PJPG's hypothesis: threads that PRE-EXIST the LoadLibrary.
   Same shape as host_concurrent.c, but the worker threads are created BEFORE
   the DLL is loaded, then released afterwards. If static TLS in a
   dynamically-loaded DLL is not allocated for pre-existing threads, these hang
   where host_concurrent's post-load threads do not. */
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
typedef void (*init_t)(void*,int,int,void*,int);
typedef int  (*conv_t)(char**,unsigned int*,char*);
typedef void (*intra_t)(int);
static init_t g_init; static conv_t g_conv;
static char* g_buf; static long g_n;
static HANDLE g_loaded;              /* signalled AFTER LoadLibrary */
static volatile LONG g_ok_count;
static DWORD WINAPI w(LPVOID p){
    long id=(long)(LONG_PTR)p;
    printf("    thread %ld: alive BEFORE LoadLibrary, waiting...\n", id); fflush(stdout);
    WaitForSingleObject(g_loaded, INFINITE);
    char* o=NULL; unsigned int sz=0; char m[512]={0};
    printf("    thread %ld: calling init+convert\n", id); fflush(stdout);
    g_init(g_buf,1,(int)g_n,NULL,1);
    int ok=g_conv(&o,&sz,m);
    printf("    thread %ld: ok=%d out=%u\n", id, ok, sz); fflush(stdout);
    if(ok) InterlockedIncrement(&g_ok_count);
    return 0;
}
int main(int c,char**v){
    if(c<4){printf("usage: host_pre <dll> <jpeg> <nthreads>\n");return 2;}
    int N=atoi(v[3]);
    FILE*f=fopen(v[2],"rb"); if(!f){printf("no jpeg\n");return 1;}
    fseek(f,0,SEEK_END); g_n=ftell(f); fseek(f,0,SEEK_SET);
    g_buf=malloc(g_n); if(fread(g_buf,1,g_n,f)!=(size_t)g_n){return 1;} fclose(f);

    g_loaded=CreateEvent(NULL,TRUE,FALSE,NULL);
    printf("[1] creating %d threads BEFORE LoadLibrary\n",N); fflush(stdout);
    HANDLE* th=malloc(sizeof(HANDLE)*N);
    for(long i=0;i<N;i++) th[i]=CreateThread(NULL,0,w,(LPVOID)(LONG_PTR)i,0,NULL);
    Sleep(500);                                  /* let them all block on the gate */

    printf("[2] NOW LoadLibrary (threads already exist)\n"); fflush(stdout);
    HMODULE h=LoadLibraryA(v[1]);
    if(!h){printf("    LoadLibrary failed %lu\n",GetLastError());return 1;}
    g_init=(init_t)GetProcAddress(h,"pjglib_init_streams");
    g_conv=(conv_t)GetProcAddress(h,"pjglib_convert_stream2mem");
    intra_t it=(intra_t)GetProcAddress(h,"pjglib_set_intra_file_threads");
    if(it) it(1);
    printf("    loaded, releasing pre-existing threads\n"); fflush(stdout);

    printf("[3] releasing gate\n"); fflush(stdout);
    SetEvent(g_loaded);
    DWORD r=WaitForMultipleObjects(N,th,TRUE,45000);
    if(r==WAIT_TIMEOUT){printf("[!] *** HUNG: only %ld/%d ok ***\n",(long)g_ok_count,N);fflush(stdout);return 3;}
    printf("[4] all %d finished ok=%ld, no hang\n",N,(long)g_ok_count); fflush(stdout);
    return 0;
}
