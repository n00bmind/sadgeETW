#import "Basic";
#import "Windows";

#load "etw.jai";

CounterNames :: string.[
    "TotalCycles",
];

main :: ()
{
    counters := MapPMCCounters( CounterNames );

    traceSession: ETWSession;
    if !InitETWSession( counters, *traceSession )
        exit( 1 );

    print( "Trace session open. Press a key to close..\n" );
    k := getch();

    ShutdownETWSession( *traceSession );
}

CHAR :: s8;
ENABLE_LINE_INPUT :: 0x0002;
ENABLE_ECHO_INPUT :: 0x0004;

kernel32 :: #system_library "kernel32";
ReadConsoleW :: (hConsoleInput: HANDLE, lpBuffer: *void, nNumberOfCharsToRead: DWORD,
                lpNumberOfCharsRead: *DWORD, pInputControl: *void ) -> BOOL #foreign kernel32;

getch :: () -> CHAR
{
    mode, cc: DWORD;
    h := GetStdHandle( STD_INPUT_HANDLE );

    if (h == null) {
        return 0; // console not found
    }

    GetConsoleMode( h, *mode );
    SetConsoleMode( h, mode & ~ cast(u32)(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT) );
    c: CHAR = 0;
    ReadConsoleW( h, *c, 1, *cc, null );
    SetConsoleMode( h, mode );
    return c;
}
