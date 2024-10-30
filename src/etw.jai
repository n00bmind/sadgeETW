#import "Windows_Utf8";
#import "System";
#import "Thread";

#load "win32_etw.jai";


Counter :: struct
{
    name: string;
    sourceIndex: u32;
}


MapPMCCounters :: ( counterNames: []string ) -> []Counter
{
    counters:= NewArray( counterNames.count, Counter );

    sourceListBufferSize: ULONG;
    TraceQueryInformation( 0, .TraceProfileSourceListInfo, null, 0, *sourceListBufferSize );

    sourceListBuffer: *u8 = alloc( sourceListBufferSize,, temp );
    TraceQueryInformation( 0, .TraceProfileSourceListInfo, sourceListBuffer, sourceListBufferSize, *sourceListBufferSize );

    offset := 0;
    counterIndex := 0;
    // Figure out the index to each PMC from their name
    while true
    {
        sourceInfo := cast(*PROFILE_SOURCE_INFO) (sourceListBuffer + offset);

        name, name_ok := wide_to_utf8_new( xx *sourceInfo.Description,, temp );
        assert( name_ok );

        for counterNames
        {
            if it == name
            {
                counters[counterIndex].name = it;
                counters[counterIndex].sourceIndex = sourceInfo.Source;
                counterIndex += 1;
                break;
            }
        }

        if sourceInfo.NextEntryOffset == 0
            break;

        offset += sourceInfo.NextEntryOffset;
    }

    return counters;
}

ETWSession :: struct
{
    processingThread: Thread;
    properties: *EVENT_TRACE_PROPERTIES;
    sessionHandle: TRACEHANDLE;
    traceHandle: TRACEHANDLE;
}

InitETWSession :: ( counters: []Counter, sessionOut: *ETWSession ) -> bool
{
    instanceName, ok := utf8_to_wide_new( "SadgeETW",, temp );
    assert( ok );

    propsBufferSize := size_of(EVENT_TRACE_PROPERTIES) + 128;
    sessionOut.properties = cast(*EVENT_TRACE_PROPERTIES) alloc( propsBufferSize );

    props := sessionOut.properties;
    props.LoggerNameOffset = size_of(EVENT_TRACE_PROPERTIES);
    props.EnableFlags = EVENT_TRACE_FLAG_NO_SYSCONFIG | EVENT_TRACE_FLAG_SYSTEMCALL; // EVENT_TRACE_FLAG_CSWITCH; // |   // | EVENT_TRACE_FLAG_MEMORY_PAGE_FAULTS;
    props.LogFileMode = EVENT_TRACE_REAL_TIME_MODE | EVENT_TRACE_SYSTEM_LOGGER_MODE;
    props.Wnode.BufferSize = xx propsBufferSize;
    props.Wnode.Flags = WNODE_FLAG_TRACED_GUID;
    // Timestamps from QueryPerformanceCounter
    props.Wnode.ClientContext = 1;

    // TODO Test V2 props
    #if false
    {
        sessionProps: struct
        {
            Properties: EVENT_TRACE_PROPERTIES_V2;
            LoggerName: [128]WCHAR;
        };

        props2 := *sessionProps.Properties;
        props2.Wnode.BufferSize = size_of( type_of( sessionProps ) );
        // Timestamps from QueryPerformanceCounter
        // props2.Wnode.ClientContext = 1;
        // Timestamps from CPU cycle counter
        props2.Wnode.ClientContext = 3;
        props2.Wnode.Flags = WNODE_FLAG_TRACED_GUID | WNODE_FLAG_VERSIONED_PROPERTIES;
        props2.LogFileMode = EVENT_TRACE_REAL_TIME_MODE | EVENT_TRACE_SYSTEM_LOGGER_MODE;
        props2.VersionNumber = 2;
        props2.EnableFlags = EVENT_TRACE_FLAG_CSWITCH; // EVENT_TRACE_FLAG_SYSTEMCALL | EVENT_TRACE_FLAG_MEMORY_PAGE_FAULTS;
        // props2.LoggerNameOffset = size_of( type_of( sessionProps ) );
        props2.LoggerNameOffset = size_of( type_of( sessionProps.Properties ) );
    }

    // Start the tracing session
    sessionHandle: TRACEHANDLE;
    status := StartTraceW( *sessionHandle, instanceName, xx props );
    if status == ERROR_ALREADY_EXISTS
    {
        // stop existing trace in case it is already running
        status = ControlTraceW( 0, instanceName, xx props, EVENT_TRACE_CONTROL_STOP );
        assert( status == ERROR_SUCCESS || status == ERROR_MORE_DATA );

        status = StartTraceW( *sessionHandle, instanceName, xx props );
    }
    if status != ERROR_SUCCESS
    {
        msg := get_error_string( xx status );
        log_error( "StartTraceW failed with error % (%)", status, msg );
        return false;
    }
    sessionOut.sessionHandle = sessionHandle;


    // Set up PMCs of interest
    counterIds := NewArray( counters.count, ULONG );
    for * counterIds
    {
        <<it = counters[it_index].sourceIndex;
    }

    // NOTE Martins: "if this triggers ERROR_BUSY = 0xaa, then I believe that that someone else is collecting PMU counters
    // in the system, and I'm not sure how or if at all you to forcefully stop/reconfigure it. Rebooting helps."
    status = TraceSetInformation( sessionHandle, .TracePmcCounterListInfo, counterIds.data, cast(ULONG) (counterIds.count * size_of(ULONG)) );
    if status != ERROR_SUCCESS
    {
        msg := get_error_string( xx status );
        log_error( "TraceSetInformation(1) failed with error % (%)", status, msg );
        ShutdownETWSession( sessionOut );
        return false;
    }

    SyscallEnterId :: CLASSIC_EVENT_ID.{
        PerfInfoGuid,
        51, // SysCallEnter
        .[0,0,0,0,0,0,0]
    };
    SyscallExitId :: CLASSIC_EVENT_ID.{
        PerfInfoGuid,
        52, // SysCallExit
        .[0,0,0,0,0,0,0]
    };

    EventIds :: CLASSIC_EVENT_ID.[ SyscallEnterId, SyscallExitId ];
    status = TraceSetInformation( sessionHandle, .TracePmcEventListInfo, EventIds.data, EventIds.count * size_of(CLASSIC_EVENT_ID) );
    if status != ERROR_SUCCESS
    {
        msg := get_error_string( xx status );
        log_error( "TraceSetInformation(2) failed with error % (%)", status, msg );
        ShutdownETWSession( sessionOut );
        return false;
    }


    // Open the trace
    // TODO Can we set it up so we only start receiving events once at least one profiled zone is active?
    // (so we can sleep the processing thread..)
    // log( "##### Opening session for '%'..\n", wide_to_utf8_new( sessionProps.LoggerName.data,, temp ) );
    log( "Opening ETW session for '%'..\n", wide_to_utf8_new( instanceName,, temp ) );

    logFile: EVENT_TRACE_LOGFILEW;
    // logFile.LoggerName = sessionProps.LoggerName.data;
    logFile.LoggerName = instanceName;
    logFile.EventRecordCallback = EventRecordCallback;
    logFile.ProcessTraceMode = (PROCESS_TRACE_MODE_REAL_TIME | PROCESS_TRACE_MODE_EVENT_RECORD | PROCESS_TRACE_MODE_RAW_TIMESTAMP);

    traceHandle := OpenTraceW( *logFile );
    if traceHandle == cast(TRACEHANDLE) INVALID_HANDLE_VALUE //INVALID_PROCESSTRACE_HANDLE
    {
        err, msg := get_error_value_and_string();
        log_error( "OpenTraceW failed with error % (%)", err, msg );
        ShutdownETWSession( sessionOut );
        return false;
    }
    sessionOut.traceHandle = traceHandle;


    // Kick off processing thread
    sessionOut.processingThread.data = xx traceHandle;

    if !thread_init( *sessionOut.processingThread, ProcessingThreadProc )
    {
        log_error( "Failed to create processing thread!" );
        ShutdownETWSession( sessionOut );
        return false;
    }
    thread_start( *sessionOut.processingThread );
}

ShutdownETWSession :: ( session: *ETWSession )
{
    log( "Closing ETW session...\n" );

    status: ULONG;
    // stop producing new events
    if session.sessionHandle
    {
        status = ControlTraceW( session.sessionHandle, null, session.properties, EVENT_TRACE_CONTROL_STOP );
        if status != ERROR_SUCCESS
        {
            msg := get_error_string( xx status );
            log_error( "ControlTraceW failed with error % (%)", status, msg );
        }
    }

    // closes trace processing, this will make ETW to process all the pending events in buffers
    if session.traceHandle
    {
        status = CloseTrace( session.traceHandle );
        if status != ERROR_SUCCESS && status != ERROR_CTX_CLOSE_PENDING
        {
            msg := get_error_string( xx status );
            log_error( "CloseTrace failed with error % (%)", status, msg );
        }
    }

    // Wait for thread to finish
    if session.processingThread.index
    {
        while !thread_is_done( *session.processingThread, -1 )
        {}
        thread_deinit( *session.processingThread );
    }

    free( session.properties );
    <<session = .{};
}

ProcessingThreadProc :: ( thread: *Thread ) -> s64
{
    traceHandle := cast(TRACEHANDLE) thread.data;

    log( "##### Beginning of ProcessTrace output:\n" );
    status := ProcessTrace( *traceHandle, 1, null, null );
    if status != ERROR_SUCCESS
    {
        msg := get_error_string( xx status );
        log_error( "ERROR! ProcessTrace failed with error % (%)", status, msg );
    }

    log( "ProcessTrace DONE\n" );
    return 0;
}


GetEventProcessorIndex :: ( eventRecord: *EVENT_RECORD ) -> ULONG
{
    if eventRecord.EventHeader.Flags & EVENT_HEADER_FLAG_PROCESSOR_INDEX != 0
        return eventRecord.BufferContext.ProcessorIndex;
    else
        return eventRecord.BufferContext.ProcessorNumber;
}

globalProcessedEventCount: int;
EventRecordCallback :: ( eventRecord: *EVENT_RECORD ) #c_call
{
    ctx: Context;
    push_context ctx
    {
        header := eventRecord.EventHeader;

        ProcessorNumber : = GetEventProcessorIndex( eventRecord );
        ThreadId: ULONG  = header.ThreadId;
        timeCycles: s64 = header.TimeStamp.QuadPart;

        // Process event here.
        globalProcessedEventCount += 1;
        // NOTE Turns out logging is very slow (at least in debug)
        // log( "% -> New event for cpu % / thread %\n", timeCycles, ProcessorNumber, ThreadId );
        // log( "   %, user: %, extended: %\n", ToGuidString( header.ProviderId ), eventRecord.UserDataLength, eventRecord.ExtendedDataCount );
    }
}
