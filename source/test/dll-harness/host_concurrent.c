/* Concurrent-entry repro: N threads each LoadLibrary-resolved pjglib_convert_stream2mem
   at once. Mirrors ytool's per-stream parallelism. Pure C, no C++ runtime. */
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
typedef void (*init_t)(void*,int,int,void*,int);
typedef int  (*conv_t)(char**,unsigned int*,char*);
typedef void (*intra_t)(int);
static init_t g_init; static conv_t g_conv;
static char* g_buf; static long g_n; static volatile LONG g_done;
static HANDLE g_gate;
static DWORD WINAPI w(LPVOID p){
    long id=(long)(LONG_PTR)p;
    WaitForSingleObject(g_gate, INFINITE);      /* release all threads together */
    char* o=NULL; unsigned int sz=0; char m[512]={0};
    g_init(g_buf,1,(int)g_n,NULL,1);
    int ok=g_conv(&o,&sz,m);
    printf("    thread %ld: ok=%d out=%u\n", id, ok, sz); fflush(stdout);
    InterlockedIncrement(&g_done);
    return 0;
}
int main(int c,char**v){
    if(c<4){printf("usage: conc <dll> <jpeg> <nthreads>\n");return 2;}
    int N=atoi(v[3]);
    HMODULE h=LoadLibraryA(v[1]);
    if(!h){printf("LoadLibrary failed %lu\n",GetLastError());return 1;}
    g_init=(init_t)GetProcAddress(h,"pjglib_init_streams");
    g_conv=(conv_t)GetProcAddress(h,"pjglib_convert_stream2mem");
    intra_t it=(intra_t)GetProcAddress(h,"pjglib_set_intra_file_threads");
    if(it) it(1);
    FILE*f=fopen(v[2],"rb"); fseek(f,0,SEEK_END); g_n=ftell(f); fseek(f,0,SEEK_SET);
    g_buf=malloc(g_n); if(fread(g_buf,1,g_n,f)!=(size_t)g_n){return 1;} fclose(f);
    printf("[*] %d concurrent threads, %ld-byte jpeg\n",N,g_n); fflush(stdout);
    g_gate=CreateEvent(NULL,TRUE,FALSE,NULL);
    HANDLE* th=malloc(sizeof(HANDLE)*N);
    for(long i=0;i<N;i++) th[i]=CreateThread(NULL,0,w,(LPVOID)(LONG_PTR)i,0,NULL);
    Sleep(200);
    SetEvent(g_gate);                            /* fire all at once */
    DWORD r=WaitForMultipleObjects(N,th,TRUE,45000);
    if(r==WAIT_TIMEOUT){printf("[!] *** HUNG: only %ld/%d finished ***\n",(long)g_done,N);fflush(stdout);return 3;}
    printf("[*] all %d finished, no hang\n",N); fflush(stdout);
    return 0;
}
