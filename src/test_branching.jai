#import "Math";

#load "etw.jai";


pmctrace_test :: #library,no_dll "pmctrace_test_asm";
CountNonZeroesWithBranch :: ( bufferSize: s64, buffer: *u8 ) -> s64 #foreign pmctrace_test;


Counters :: string.[
    "TotalIssues",
    "BranchInstructions",
    "BranchMispredictions",
];

ThreadContext :: struct
{
    thread: Thread;
    session: *ETWSession;
    bufferSize: s64;
    nonZeroCount: s64;

    batchZones: [32] ETWZone;
    bestResult: ETWResults;
}

TestThread :: ( thread: *Thread ) -> s64
{
    ctx := cast(*ThreadContext) thread.data;
    bufferData: *u8 = alloc( ctx.bufferSize,, temp );
    bufferSize := ctx.bufferSize;
    nonZeroCount := ctx.nonZeroCount;
    
    if bufferData
    {
        for i: 0 .. nonZeroCount - 1
        {
            ok, val := false, cast(u64) 0;
            while !ok
                ok, val = rdrand();
            // TODO To be more correct, we'd have to check that we dont ever get repeated values here..
            bufferData[ val % xx bufferSize ] = 1;
        }

        for batchIdx: 0 .. ctx.batchZones.count - 1
        {
            zone := *ctx.batchZones[batchIdx];

            BeginETWZone( ctx.session, zone );
            CountNonZeroesWithBranch( bufferSize, bufferData );
            EndETWZone( ctx.session, zone );
        }

        // Async get all results and record the best one
        ctx.bestResult.elapsedTSC = U64_MAX;
        for batchIdx: 0 .. ctx.batchZones.count - 1
        {
            zone := *ctx.batchZones[batchIdx];
            result := GetOrWaitForResults( zone );
            // FIXME Return immediately here upon error
            if result.completed && result.elapsedTSC < ctx.bestResult.elapsedTSC
                ctx.bestResult = result;
        }
    }
    else
        log_error( "Unable to allocate test memory" );

    return 0;
}

main :: ()
{
    #assert OS == .WINDOWS "Only Windows supported for now";

    counters := MapPMCCounters( Counters );
    log( "Mapped counters:\n" );
    for counters
    {
        log( "%: '%'\n", it.sourceIndex, it.name );
    }

    traceSession: ETWSession;
    if !InitETWSession( counters, *traceSession )
        exit( 1 );

    testThread: ThreadContext;
    testThread.session = *traceSession;
    testThread.bufferSize = 1024 * 1024;
    testThread.nonZeroCount = 0;

    if thread_init( *testThread.thread, TestThread )
    {
        testThread.thread.data = *testThread;
        thread_start( *testThread.thread );

        while !thread_is_done( *testThread.thread, -1 )
        {}
        thread_deinit( *testThread.thread );
    }
    else
        log_error( "Failed to create test thread!" );

    print( "\n\n##### Results:\n" );
    PrintResults( counters, testThread.bestResult );

    ShutdownETWSession( *traceSession );
}

