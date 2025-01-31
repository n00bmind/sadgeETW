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
    bufferSize := ctx.bufferSize;
    nonZeroCount := ctx.nonZeroCount;
    // bufferData: *u8 = alloc( bufferSize,, temp );
    bufferData: *u8 = alloc( bufferSize );
    
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
        log_error( "Unable to allocate % bytes of test memory", bufferSize );

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

    testThreads: [16] ThreadContext;

    for * t: testThreads
    {
        t.session = *traceSession;
        t.bufferSize = 1024 * 1024;
        t.nonZeroCount = it_index * 4096;

        if thread_init( *t.thread, TestThread )
        {
            t.thread.data = t;
            thread_start( *t.thread );
        }
        else
            log_error( "Failed to create test thread %!", it_index );
    }

    print( "\n\n##### Results:\n" );
    for * t: testThreads
    {
        while !thread_is_done( *t.thread, -1 )
        {}
        thread_deinit( *t.thread );

        print( "\nThread % (% non-zeroes):\n", it_index, t.nonZeroCount );
        print( "- % TSC elapsed / % iterations / % context switches\n",
            t.bestResult.elapsedTSC, t.bufferSize, t.bestResult.contextSwitchCount );
        PrintResults( counters, t.bestResult );
    }

    ShutdownETWSession( *traceSession );
}

