#import "Basic";
#import "Windows_Utf8";
#import "System";
#import "Thread";
#import "Machine_X64";

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

ETWThreadState :: struct
{
    zoneStack: [MaxZoneDepth] *ETWZone;
    stackTop: u32;
    threadId: DWORD;
    suspended: bool;
}

PushZone :: ( using thread: *ETWThreadState, zone: *ETWZone )
{
    assert( stackTop < MaxZoneDepth );

    zoneStack[stackTop] = zone;
    stackTop += 1;
}
PopZone :: ( using thread: *ETWThreadState, zone: *ETWZone )
{
    assert( stackTop > 0 );

    stackTop -= 1;
    zoneStack[stackTop] = null;
}

ETWCPUState :: struct
{
    waitingForSysExit: *ETWZone;
    lastSysEnterCounters: [MaxCounters]u64;
    lastSysEnterTSC: u64;
    trackedThreadId: DWORD;     // Thread currently running on this core
    lastSysEnterValid: bool;
}

ETWSession :: struct
{
    counters: []Counter;
    cpus: []ETWCPUState;
    trackedThreads: [..]ETWThreadState;
    processingThread: Thread;
    sessionKey: u64;
    properties: *EVENT_TRACE_PROPERTIES;
    sessionHandle: TRACEHANDLE;
    traceHandle: TRACEHANDLE;
}

MaxCounters :: 8;
MaxZoneDepth :: 16;

InitETWSession :: ( counters: []Counter, sessionOut: *ETWSession ) -> bool
{
    sessionOut.sessionKey = rdtsc();

    assert( counters.count < MaxCounters );
    sessionOut.counters = counters;

    sysInfo : SYSTEM_INFO;
    GetNativeSystemInfo( *sysInfo );
    sessionOut.cpus = NewArray( sysInfo.dwNumberOfProcessors, ETWCPUState );

    // Pre-allocate space for tracking threads
    array_reserve( *sessionOut.trackedThreads, sessionOut.cpus.count );

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


ETWResults :: struct
{
    counterValues: [MaxCounters]u64;
    elapsedTSC: u64;
    contextSwitchCount: u32;
    completed: bool;
}

ETWZone:: struct
{
    results: ETWResults;
    onThreadId: DWORD;
}

BeginETWZone :: ( session: *ETWSession, zone: *ETWZone )
{
    event: ZoneMakerEvent;
    event.header.Size = size_of(ZoneMakerEvent);
    event.header.Flags = WNODE_FLAG_TRACED_GUID; // | WNODE_FLAG_USE_MOF_PTR;
    event.header.Guid = ZoneMarkerEventGuid;
    event.header.Class.Type = ZoneEnter;
    event.userData.sessionKey = session.sessionKey;
    event.userData.zone = zone;

    // zone.onThreadId = 

    status := TraceEvent( session.sessionHandle, xx *event );
    if status != ERROR_SUCCESS
    {
        msg := get_error_string( xx status );
        log_error( "TraceEvent failed with error % (%) / handle is: 0x%", status, msg, formatHex( session.sessionHandle ) );
        // TODO Track which zones had errors?
    }
}

EndETWZone :: ( session: *ETWSession, zone: *ETWZone )
{
    event: ZoneMakerEvent;
    event.header.Size = size_of(ZoneMakerEvent);
    event.header.Flags = WNODE_FLAG_TRACED_GUID; // | WNODE_FLAG_USE_MOF_PTR;
    event.header.Guid = ZoneMarkerEventGuid;
    event.header.Class.Type = ZoneExit;
    event.userData.sessionKey = session.sessionKey;
    event.userData.zone = zone;

    status := TraceEvent( session.sessionHandle, xx *event );
    if status != ERROR_SUCCESS
    {
        msg := get_error_string( xx status );
        log_error( "TraceEvent failed with error % (%) / handle is: 0x%", status, msg, formatHex( session.sessionHandle ) );
        // TODO Track which zones had errors?
    }
}

IsComplete :: ( zone: *ETWZone ) -> bool
{
    // FIXME Acquire barrier
    return zone.results.completed;
}

GetOrWaitForResults :: ( zone: *ETWZone ) -> ETWResults
{
    // FIXME Account for errors
    while !IsComplete( zone )
        YieldProcessor();

    return zone.results;
}

PrintResults :: ( counters: []Counter, results: ETWResults )
{
    for c : counters
    {
        print( "%: %\n", c.name, results.counterValues[it_index] );
    }
}


#scope_file

// TODO Use atomics
globalProcessedEventCount: int;

formatHex :: #bake_arguments formatInt(base = 16, padding = #char "0");

ZoneExit  :UCHAR : 0;
ZoneEnter :UCHAR : 1;

ZoneMakerEvent :: struct
{
    header: EVENT_TRACE_HEADER;
    UserData :: struct
    {
        sessionKey: u64;
        zone: *ETWZone;
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

ContextSwitchUserData :: struct
{
    newThreadId: DWORD;
    oldThreadId: DWORD;
}


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


GetEventProcessorIndex :: ( event: *EVENT_RECORD ) -> ULONG
{
    if event.EventHeader.Flags & EVENT_HEADER_FLAG_PROCESSOR_INDEX != 0
        return event.BufferContext.ProcessorIndex;
    else
        return event.BufferContext.ProcessorNumber;
}

FindThreadState :: ( session: *ETWSession, threadId: DWORD ) -> *ETWThreadState
{
    for * t : session.trackedThreads
    {
        if t.threadId == threadId
            return t;
    }
    return null;
}

FindOrAddThreadState :: ( session: *ETWSession, threadId: DWORD ) -> *ETWThreadState
{
    t := FindThreadState( session, threadId );
    if t
        return t;

    newThread := array_add( *session.trackedThreads );
    newThread.threadId = threadId;
    return newThread;
}

FetchPMCValues :: ( session: *ETWSession, event: *EVENT_RECORD, dataOut: *[]u64 )
{
    assert( dataOut.count >= session.counters.count );

    for i: 0 .. cast(int)event.ExtendedDataCount - 1
    {
        item := event.ExtendedData + i;
        if item.ExtType == EVENT_HEADER_EXT_TYPE_PMC_COUNTERS
        {
            expectedDataSize := session.counters.count * size_of(ULONG64);
            assert( item.DataSize == expectedDataSize );

            memcpy( dataOut.data, xx item.DataPtr, item.DataSize );

            // for globalStartCounterData
            // log( "    counter %: %\n", it_index, it );
        }
    }
}

ApplyPMCsAsOpen :: ( results: *ETWResults, values: []u64, tsc: u64 )
{
    prev := results.counterValues;
    for idx: 0 .. values.count - 1
    {
        results.counterValues[idx] -= values[idx];
        print( "% - % = %\n", prev[idx], values[idx], results.counterValues[idx] );
    }
    
    results.elapsedTSC -= tsc;
}

ApplyPMCsAsClose :: ( results: *ETWResults, values: []u64, tsc: u64 )
{
    prev := results.counterValues;
    for idx: 0 .. values.count - 1
    {
        results.counterValues[idx] += values[idx];
        print( "% + % = %\n", prev[idx], values[idx], results.counterValues[idx] );
    }
    
    results.elapsedTSC += tsc;
}

EventRecordCallback :: ( event: *EVENT_RECORD ) #c_call
{
    ctx: Context;
    push_context ctx
    {
        session := cast(*ETWSession) event.UserContext;
        header := event.EventHeader;

        eventGUID := header.ProviderId;
        opcode := header.EventDescriptor.Opcode;
        // TODO Check whether this is (presumably) a *logical* core index? Otherwise our method of assigning thread ids to cores falls apart on hyperthreaded chips
        cpuIdx := GetEventProcessorIndex( event );
        threadId: ULONG = header.ThreadId;
        timeCycles: u64 = xx header.TimeStamp.QuadPart;

        assert( cpuIdx < session.cpus.count, "Event received on a CPU index outside of the system's range!?" );
        cpu := *session.cpus[ cpuIdx ];

        if eventGUID == ZoneMarkerEventGuid
        {
            eventData := cast(*ZoneMakerEvent.UserData) event.UserData;
            zone := eventData.zone;

            // Only process zone marker events corresponding to the current session
            if eventData.sessionKey == session.sessionKey
            {
                entered := opcode == ZoneEnter;
                log( "% -> % zone for cpu % / thread %\n", timeCycles, ifx entered then "Begin" else "End", cpuIdx, threadId );
                // log( "    user: %, extended: %\n", event.UserDataLength, event.ExtendedDataCount );

                if opcode == ZoneEnter
                {
                    thread := FindOrAddThreadState( session, threadId );
                    // Add a new zone to the stack for this thread
                    PushZone( thread, zone );

                    // Set thread as current on this cpu
                    cpu.trackedThreadId = threadId;
                    // Set this zone as waiting for SysExit event on this cpu
                    assert( cpu.waitingForSysExit == null, "Additional zone opened on the same thread before SysExit event started the prior zone" );
                    cpu.waitingForSysExit = zone;
                }
                else if opcode == ZoneExit
                {
                    assert( cpu.lastSysEnterValid, "No valid SysEnter for received ZoneExit" );

                    // Apply the counters and TSC we saved from the preceeding SysEnter event
                    srcCounters: []u64 = .{ session.counters.count, cpu.lastSysEnterCounters.data };
                    ApplyPMCsAsClose( *zone.results, srcCounters, cpu.lastSysEnterTSC );
                    cpu.lastSysEnterValid = false;
                    // No longer tracking this thread on this cpu
                    // TODO Is 0 really invalid for thread ids? Assert if unsure
                    cpu.trackedThreadId = 0;

                    thread := FindThreadState( session, threadId );
                    assert( thread != null, "Received ZoneExit for untracked thread" );
                    // Remove this zone from the stack for this thread
                    PopZone( thread, zone );

                    // FIXME Release fence
                    zone.results.completed = true;
                }
                else
                {
                    assert( false, "Unrecognized ZoneMarkerEvent type (%)", opcode );
                }
            }
        }
        else if eventGUID == ThreadGuid
        {
            // Only care about context switches
            if opcode == SwitchThreadOpCode
            {
                logMsg := false;
                counterValues: [MaxCounters] u64;
                // TODO Why do we even need this crap again? How is casting supposed to work for "array views" then?
                countersView: []u64 = .{ session.counters.count, counterValues.data };

                assert( event.UserDataLength == 24 );
                eventData := cast(*ContextSwitchUserData) event.UserData;

                // Is the thread we're switching from one of ours?
                if( cpu.trackedThreadId == eventData.oldThreadId )
                {
                    logMsg = true;

                    // Ensure we're not suspending a thread before properly starting its top zone
                    assert( cpu.waitingForSysExit == null );
                    // No longer tracking this thread on this cpu
                    cpu.trackedThreadId = 0;

                    suspendedThread := FindThreadState( session, eventData.oldThreadId );
                    assert( suspendedThread != null );
                    suspendedThread.suspended = true;

                    FetchPMCValues( session, event, *countersView );

                    for zone : suspendedThread.zoneStack
                    {
                        // Apply the current PMCs as "ending" counters
                        ApplyPMCsAsClose( *zone.results, countersView, timeCycles );
                        zone.results.contextSwitchCount += 1;
                    }
                }

                // TODO This should probably be a hashtable lookup to minimize wasted time here
                resumedThread := FindThreadState( session, eventData.newThreadId );
                if resumedThread
                {
                    logMsg = true;

                    // Start tracking this thread on this cpu
                    cpu.trackedThreadId = eventData.newThreadId;

                    assert( resumedThread.suspended );
                    resumedThread.suspended = false;

                    FetchPMCValues( session, event, *countersView );

                    for zone : resumedThread.zoneStack
                    {
                        // Apply the current PMCs as "starting" counters
                        ApplyPMCsAsOpen( *zone.results, countersView, timeCycles );
                        zone.results.contextSwitchCount += 1;
                    }
                }

                if logMsg
                {
                    log( "% -> SwitchThread on cpu % / from thread % -> to thread %\n", timeCycles, cpuIdx,
                         eventData.oldThreadId, eventData.newThreadId );
                }
            }
        }
        else if eventGUID == PerfInfoGuid
        {
            if opcode == SysCallExitOpCode
            {
                zone := cpu.waitingForSysExit;
                if zone
                {
                    cpu.waitingForSysExit = null;

                    log( "% -> SysCallExit on cpu % / thread %\n", timeCycles, cpuIdx, threadId );

                    counterValues: [MaxCounters] u64;
                    countersView: []u64 = .{ session.counters.count, counterValues.data };

                    FetchPMCValues( session, event, *countersView );
                    ApplyPMCsAsOpen( *zone.results, countersView, timeCycles );
                }
            }
            else if opcode == SysCallEnterOpCode
            {
                if cpu.trackedThreadId
                {
                    log( "% -> SysCallEnter on cpu % / thread %\n", timeCycles, cpuIdx, threadId );

                    // Remember the state at this SysEnter so it can be applied to a zone later if there is a following ZoneExit event
                    countersView: []u64 = .{ session.counters.count, cpu.lastSysEnterCounters.data };
                    FetchPMCValues( session, event, *countersView );
                    cpu.lastSysEnterTSC = timeCycles;
                    cpu.lastSysEnterValid = true;
                }
            }
        }

        globalProcessedEventCount += 1;
    }
}

YieldProcessor :: ()
{
    #asm {
        pause;
    }
}

