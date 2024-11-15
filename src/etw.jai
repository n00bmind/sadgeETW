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

ETWCoreState :: struct
{
    
}

ETWSession :: struct
{
    counters: []Counter;
    processingThread: Thread;
    properties: *EVENT_TRACE_PROPERTIES;
    sessionHandle: TRACEHANDLE;
    traceHandle: TRACEHANDLE;
}

InitETWSession :: ( counters: []Counter, sessionOut: *ETWSession ) -> bool
{
    sessionOut.counters = counters;

    SessionProps :: struct
    {
        properties: EVENT_TRACE_PROPERTIES_V2;
        name: [128]WCHAR;
    };

    instanceName, ok, instanceNameSize := utf8_to_wide_new( "SadgeETW",, temp );
    assert( ok && instanceNameSize <= size_of(type_of( SessionProps.name )) );

    props := New( SessionProps );
    p := *props.properties;
    sessionOut.properties = cast(*EVENT_TRACE_PROPERTIES) p;

    // Stop existing trace in case it is already running
    p.Wnode.BufferSize = size_of( SessionProps );
    p.LoggerNameOffset = size_of(type_of( SessionProps.properties ));

    status := ControlTraceW( 0, instanceName, xx p, EVENT_TRACE_CONTROL_STOP );
    if !(status == ERROR_SUCCESS || status == ERROR_MORE_DATA || status == ERROR_WMI_INSTANCE_NOT_FOUND)
    {
        msg := get_error_string( xx status );
        log_error( "ControlTraceW returned error % (%)", status, msg );
        return false;
    }

    <<p = .{};
    p.Wnode.BufferSize = size_of( SessionProps );
    // Timestamps from CPU cycle counter
    p.Wnode.ClientContext = 3;
    p.Wnode.Flags = WNODE_FLAG_TRACED_GUID | WNODE_FLAG_VERSIONED_PROPERTIES;
    p.VersionNumber = 2;
    p.LoggerNameOffset = size_of(type_of( SessionProps.properties ));
    p.LogFileMode = EVENT_TRACE_REAL_TIME_MODE | EVENT_TRACE_SYSTEM_LOGGER_MODE;
    p.EnableFlags = EVENT_TRACE_FLAG_NO_SYSCONFIG | EVENT_TRACE_FLAG_SYSTEMCALL; // EVENT_TRACE_FLAG_CSWITCH; // |   // | EVENT_TRACE_FLAG_MEMORY_PAGE_FAULTS;

    // Start the tracing session
    sessionHandle: TRACEHANDLE;
    status = StartTraceW( *sessionHandle, instanceName, xx p );
    if status != ERROR_SUCCESS
    {
        msg := get_error_string( xx status );
        log_error( "StartTraceW failed with error % (%)", status, msg );
        return false;
    }
    sessionOut.sessionHandle = sessionHandle;


    // TODO Why does this constantly fail on the laptop!?
    #if true
    {
        // Set up PMCs of interest
        counterIds := NewArray( counters.count, ULONG,, temp );
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
    }

    SyscallEnterId :: CLASSIC_EVENT_ID.{
        PerfInfoGuid,
        SysCallEnterOpCode,
        .[0,0,0,0,0,0,0]
    };
    SyscallExitId :: CLASSIC_EVENT_ID.{
        PerfInfoGuid,
        SysCallExitOpCode,
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
    // TODO Presumably that thread is just suspended on a semaphore or similar?
    // log( "##### Opening session for '%'..\n", wide_to_utf8_new( sessionProps.LoggerName.data,, temp ) );
    log( "Opening ETW session for '%'..\n", wide_to_utf8_new( instanceName,, temp ) );

    logFile: EVENT_TRACE_LOGFILEW;
    // logFile.LoggerName = sessionProps.LoggerName.data;
    logFile.LoggerName = instanceName;
    logFile.EventRecordCallback = EventRecordCallback;
    logFile.ProcessTraceMode = (PROCESS_TRACE_MODE_REAL_TIME | PROCESS_TRACE_MODE_EVENT_RECORD | PROCESS_TRACE_MODE_RAW_TIMESTAMP);
    // FIXME Not great, if the user copies its session struct to somewhere for storage, this becomes invalid!
    logFile.Context = sessionOut;

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

    return true;
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


formatHex :: #bake_arguments formatInt(base = 16, padding = #char "0");

ZoneMakerEvent :: struct
{
    header: EVENT_TRACE_HEADER;
    UserData :: struct
    {
        zoneEnter: bool;
    }
    userData: UserData;
}

// {5E60DAA3-471D-49B2-B608-B1FF493AE160}
ZoneMarkerEventGuid :: #run DefineGUID(
    0x5e60daa3,
    0x471d,
    0x49b2,
    0xb6, 0x8, 0xb1, 0xff, 0x49, 0x3a, 0xe1, 0x60
);

BeginETWZone :: ( session: *ETWSession )
{
    enterEvent: ZoneMakerEvent;
    enterEvent.header.Size = size_of(ZoneMakerEvent);
    enterEvent.header.Flags = WNODE_FLAG_TRACED_GUID; // | WNODE_FLAG_USE_MOF_PTR;
    enterEvent.header.Guid = ZoneMarkerEventGuid;
    enterEvent.userData.zoneEnter = true;

    status := TraceEvent( session.sessionHandle, xx *enterEvent );
    if status != ERROR_SUCCESS
    {
        msg := get_error_string( xx status );
        log_error( "TraceEvent failed with error % (%) / handle is: 0x%", status, msg, formatHex( session.sessionHandle ) );
        // TODO Track which zones had errors?
    }
}

EndETWZone :: ( session: *ETWSession )
{
    exitEvent: ZoneMakerEvent;
    exitEvent.header.Size = size_of(ZoneMakerEvent);
    exitEvent.header.Flags = WNODE_FLAG_TRACED_GUID; // | WNODE_FLAG_USE_MOF_PTR;
    exitEvent.header.Guid = ZoneMarkerEventGuid;
    exitEvent.userData.zoneEnter = false;

    status := TraceEvent( session.sessionHandle, xx *exitEvent );
    if status != ERROR_SUCCESS
    {
        msg := get_error_string( xx status );
        log_error( "TraceEvent failed with error % (%) / handle is: 0x%", status, msg, formatHex( session.sessionHandle ) );
        // TODO Track which zones had errors?
    }
}

ETWResults :: struct
{

}

GetOrWaitForResults :: ( session: *ETWSession ) -> ETWResults
{
    // TODO 
    Sleep( 3000 );

}


#scope_file

// TODO Use atomics
globalProcessingStarted := false;
globalProcessedEventCount: int;
globalCurrentZoneThreadId: ULONG;
globalStartCounterData: []u64;
globalLastCounterData: []u64;

ProcessingThreadProc :: ( thread: *Thread ) -> s64
{
    traceHandle := cast(TRACEHANDLE) thread.data;

    log( "\n##### Beginning of ProcessTrace output:\n" );
    status := ProcessTrace( *traceHandle, 1, null, null );
    if status != ERROR_SUCCESS
    {
        msg := get_error_string( xx status );
        log_error( "ERROR! ProcessTrace failed with error % (%)", status, msg );
        log_error( "Handle is: %\n", traceHandle );
    }

    log( "ProcessTrace exited (% events processed)\n", globalProcessedEventCount );
    return 0;
}


GetEventProcessorIndex :: ( eventRecord: *EVENT_RECORD ) -> ULONG
{
    if eventRecord.EventHeader.Flags & EVENT_HEADER_FLAG_PROCESSOR_INDEX != 0
        return eventRecord.BufferContext.ProcessorIndex;
    else
        return eventRecord.BufferContext.ProcessorNumber;
}

EventRecordCallback :: ( eventRecord: *EVENT_RECORD ) #c_call
{
    ctx: Context;
    push_context ctx
    {
        header := eventRecord.EventHeader;

        processorNumber : = GetEventProcessorIndex( eventRecord );
        threadId: ULONG  = header.ThreadId;
        timeCycles: s64 = header.TimeStamp.QuadPart;

        session := cast(*ETWSession) eventRecord.UserContext;

        if header.ProviderId == ZoneMarkerEventGuid
        {
            userData := cast(*ZoneMakerEvent.UserData)eventRecord.UserData;

            log( "% -> % zone for cpu % / thread %\n", timeCycles, ifx userData.zoneEnter then "Begin" else "End", processorNumber, threadId );
            log( "    user: %, extended: %\n", eventRecord.UserDataLength, eventRecord.ExtendedDataCount );

            // TODO Multiple zones / threads
            if userData.zoneEnter
                globalCurrentZoneThreadId = threadId;
            else
            {
                globalCurrentZoneThreadId = 0;
                for globalLastCounterData
                    log( "    counter %: %\n", it_index, it );

                if globalLastCounterData.count && globalStartCounterData.count
                {
                    log( "\n\nRESULTS:\n" );
                    for i: 0 .. session.counters.count - 1
                    log( "'%': %\n", session.counters[i].name, globalLastCounterData[i] - globalStartCounterData[i] );
                }
                else
                    log( "\n\nNO RESULTS.\n" );
            }
        }

        // Inside a zone, process systemcall events
        // TODO ThreadId seems to be -1 for all these !?? arrrrghgkjskfh
        if globalCurrentZoneThreadId /* == threadId */ && header.ProviderId == PerfInfoGuid
        {
            op := header.EventDescriptor.Opcode;

            if op == SysCallExitOpCode && globalStartCounterData.count == 0
            {
                log( "% -> Syscall exit with % ext data for cpu % / thread %\n", timeCycles, eventRecord.ExtendedDataCount,
                     processorNumber, threadId );

                for i: 0 .. cast(int)eventRecord.ExtendedDataCount - 1
                {
                    item := eventRecord.ExtendedData + i;
                    if item.ExtType == EVENT_HEADER_EXT_TYPE_PMC_COUNTERS
                    {
                        dataSize := session.counters.count * size_of(ULONG64);
                        assert( item.DataSize == dataSize );

                        globalStartCounterData = NewArray( session.counters.count, u64 );
                        memcpy( globalStartCounterData.data, xx item.DataPtr, dataSize );

                        for globalStartCounterData
                            log( "    counter %: %\n", it_index, it );
                    }
                }
            }
            else if op == SysCallEnterOpCode
            {
                // log( "% -> Syscall enter with % ext data for cpu % / thread %\n", timeCycles, eventRecord.ExtendedDataCount,
                //      processorNumber, threadId );

                for i: 0 .. cast(int)eventRecord.ExtendedDataCount - 1
                {
                    item := eventRecord.ExtendedData + i;
                    if item.ExtType == EVENT_HEADER_EXT_TYPE_PMC_COUNTERS
                    {
                        dataSize := session.counters.count * size_of(ULONG64);
                        assert( item.DataSize == dataSize );

                        if globalLastCounterData.count == 0
                            globalLastCounterData = NewArray( session.counters.count, u64 );
                        memcpy( globalLastCounterData.data, xx item.DataPtr, dataSize );
                    }
                }
            }
        }

        globalProcessedEventCount += 1;
    }
}
