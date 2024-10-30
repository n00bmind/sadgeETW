#import "Basic";
#import "Windows_Utf8";
#import "System";
#import "Thread";

#load "win32_etw.jai";


// {DCAEDCFA-DB98-476D-A786-96EB54152529}
MyProviderGuid :: #run DefineGUID(
    0xdcaedcfa,
    0xdb98,
    0x476d,
    0xa7, 0x86, 0x96, 0xeb, 0x54, 0x15, 0x25, 0x29
);

globalProviderSessionHandle: TRACEHANDLE;


main :: ()
{
    USE_KERNEL_LOGGER :: false;

    #if USE_KERNEL_LOGGER
    {
        kernelLoggerName, ok, kernelLoggerNameSize := utf8_to_wide_new( KERNEL_LOGGER_NAMEA,, temp );
        instanceName := kernelLoggerName;
    }
    else
    {
        instanceName, ok := utf8_to_wide_new( "SadgeETW",, temp );
    }
    assert( ok );


    propsBufferSize := size_of(EVENT_TRACE_PROPERTIES) + 128;
    props := cast(*EVENT_TRACE_PROPERTIES) alloc( propsBufferSize );

    #if false
    {
        memset( props, 0, propsBufferSize );
        // We still need to manually copy this ourselves to be able to call ControlTrace
        memcpy( cast(*u8)props + size_of(EVENT_TRACE_PROPERTIES), kernelLoggerName, kernelLoggerNameSize + 2 );

        props.LoggerNameOffset = size_of(EVENT_TRACE_PROPERTIES);
        props.Wnode.BufferSize = xx propsBufferSize;

        status := ControlTraceW( 0, kernelLoggerName, props, EVENT_TRACE_CONTROL_STOP );
        if status != ERROR_SUCCESS
        {
            msg: string = "unknown";
            if status ==
            {
                case ERROR_ACCESS_DENIED; msg = "access denied";
                case ERROR_ALREADY_EXISTS; msg = "session already exists";
            }
            log_error( "ControlTraceW failed with error % (%)", status, msg );
            // exit( 1 );
        }
    }

    #if true
    {
        memset( props, 0, propsBufferSize );
        props.LoggerNameOffset = size_of(EVENT_TRACE_PROPERTIES);
        // TODO How do we indicate that we want to listen for the events we will emit with TraceEvent!?
        props.EnableFlags = EVENT_TRACE_FLAG_NO_SYSCONFIG | EVENT_TRACE_FLAG_SYSTEMCALL; // EVENT_TRACE_FLAG_CSWITCH; // |   // | EVENT_TRACE_FLAG_MEMORY_PAGE_FAULTS;
        // props.LogFileMode = EVENT_TRACE_REAL_TIME_MODE;
        props.LogFileMode = EVENT_TRACE_REAL_TIME_MODE | EVENT_TRACE_SYSTEM_LOGGER_MODE;
        props.Wnode.BufferSize = xx propsBufferSize;
        props.Wnode.Flags = WNODE_FLAG_TRACED_GUID;
        // Timestamps from QueryPerformanceCounter
        props.Wnode.ClientContext = 1;
        // props.Wnode.Guid = SystemTraceControlGuid;
    }

    #if false
    {
        sessionProps: struct
        {
            Properties: EVENT_TRACE_PROPERTIES_V2;
            LoggerName: [128]WCHAR;
        };

        memset( *sessionProps, 0, size_of( type_of( sessionProps ) ) );
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

    

    // TODO Defer Cleanup()

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
        exit( 1 );
    }


    #if false
    {
        // TODO Do we need this crap after all?
        eventClassGuids := TRACE_GUID_REGISTRATION.[
            .{ *MyEventGuid, null }
        ];
        providerRegistrationHandle: TRACEHANDLE;
        status = RegisterTraceGuidsW( MyProviderControlCallback, null, *MyProviderGuid, eventClassGuids.count, eventClassGuids.data,
        null, null, *providerRegistrationHandle );
        if status != ERROR_SUCCESS
        {
            msg := get_error_string( xx status );
            log_error( "RegisterTraceGuidsW failed with error % (%)", status, msg );
            exit( 1 );
        }

        status = EnableTrace( 1, 1, 1, *MyProviderGuid, sessionHandle );
        if status != ERROR_SUCCESS
        {
            msg := get_error_string( xx status );
            log_error( "EnableTrace failed with error % (%) / handle is: 0x%", status, msg, formatHex( sessionHandle ) );
            exit( 1 );
        }
    }


    // Figure out the index to each PMC from their name
    sourceListBufferSize: ULONG;
    TraceQueryInformation( 0, .TraceProfileSourceListInfo, null, 0, *sourceListBufferSize );

    sourceListBuffer: *u8 = alloc( sourceListBufferSize,, temp );
    TraceQueryInformation( 0, .TraceProfileSourceListInfo, sourceListBuffer, sourceListBufferSize, *sourceListBufferSize );

    log( "List of profile sources:\n" );
    sourceInfo := cast(*PROFILE_SOURCE_INFO) sourceListBuffer;
    // Loop through all entries and print the string that starts in Description
    while sourceInfo != null
    {
        name, name_ok := wide_to_utf8_new( xx *sourceInfo.Description,, temp );
        if name_ok
            log( "% - %\n", sourceInfo.Source, name );
        else
            log( "<invalid>n" );

        if sourceInfo.NextEntryOffset == 0
            break;

        sourceListBuffer += sourceInfo.NextEntryOffset;
        sourceInfo = cast(*PROFILE_SOURCE_INFO) sourceListBuffer;
    }

    // Select which PMC we want to receive and on which events (apparently can only accept 4 of each?)
    // TotalIssues, BranchInstructions, BranchMispredictions, CacheMisses
    // TODO Do the actual mapping of each of these!
    // NOTE Martins: "if this triggers ERROR_BUSY = 0xaa, then I believe that that someone else is collecting PMU counters
    // in the system, and I'm not sure how or if at all you to forcefully stop/reconfigure it. Rebooting helps."
    PMCIds :: ULONG.[ 2, 6, 11, 10 ];
    status = TraceSetInformation( sessionHandle, .TracePmcCounterListInfo, PMCIds.data, PMCIds.count * size_of(ULONG) );
    if status != ERROR_SUCCESS
    {
        msg := get_error_string( xx status );
        log_error( "TraceSetInformation(1) failed with error % (%)", status, msg );
        exit( 1 );
    }

    // TODO In reality we only want to receive PMCs for the custom events we emit
    // TODO Only some events support attaching PMCs.. check Martins code!
    // https://learn.microsoft.com/en-us/windows/win32/etw/thread-v2
    threadEventId :: CLASSIC_EVENT_ID.{
        ThreadGuid,
        // 1, // Thread start
        // 3, // Enumerate threads
        0x24, // ? - Context switches
        .[0,0,0,0,0,0,0]
    };
    perfInfoEventId :: CLASSIC_EVENT_ID.{
        PerfInfoGuid,
        52, // SysCallExit
        .[0,0,0,0,0,0,0]
    };

    EventIds :: CLASSIC_EVENT_ID.[ perfInfoEventId ];    
    status = TraceSetInformation( sessionHandle, .TracePmcEventListInfo, EventIds.data, EventIds.count * size_of(CLASSIC_EVENT_ID) );
    if status != ERROR_SUCCESS
    {
        msg := get_error_string( xx status );
        log_error( "TraceSetInformation(2) failed with error % (%)", status, msg );
        exit( 1 );
    }



    // log( "##### Opening session for '%'..\n", wide_to_utf8_new( sessionProps.LoggerName.data,, temp ) );
    log( "##### Opening session for '%'..\n", wide_to_utf8_new( instanceName,, temp ) );

    logFile: EVENT_TRACE_LOGFILEW;
    // logFile.LoggerName = sessionProps.LoggerName.data;
    logFile.LoggerName = instanceName;
    logFile.EventRecordCallback = MyEventRecordCallback;
    logFile.ProcessTraceMode = (PROCESS_TRACE_MODE_REAL_TIME | PROCESS_TRACE_MODE_EVENT_RECORD | PROCESS_TRACE_MODE_RAW_TIMESTAMP);

    traceHandle := OpenTraceW( *logFile );
    if traceHandle == cast(TRACEHANDLE) INVALID_HANDLE_VALUE //INVALID_PROCESSTRACE_HANDLE
    {
        err, msg := get_error_value_and_string();
        log_error( "OpenTraceW failed with error % (%)", err, msg );
        exit( 1 );
    }


    processingThread: Thread;
    processingThread.data = xx traceHandle;

    if !thread_init( *processingThread, ProcessingThreadProc )
    {
        log_error( "Failed to create processing thread!" );
        exit( 1 );
    }
    thread_start( *processingThread );


    MyEvent :: struct
    {
        Header: EVENT_TRACE_HEADER;
    }

    #if true
    {
        myEvent: MyEvent;
        myEvent.Header.Size = size_of(EVENT_TRACE_HEADER);
        myEvent.Header.Flags = WNODE_FLAG_TRACED_GUID; // | WNODE_FLAG_USE_MOF_PTR;
        myEvent.Header.Guid = MyEventGuid;
        // myEvent.Header.Class.Type = MY_EVENT_TYPE;
        myEvent.Header.Class.Type = 1;
        // myEvent.Header.Class.Version = 1;
        // myEvent.Header.Class.Level = g_EnableLevel;

        status = TraceEvent( sessionHandle, xx *myEvent );
        if status != ERROR_SUCCESS
        {
            msg := get_error_string( xx status );
            log_error( "TraceEvent failed with error % (%) / handle is: 0x%", status, msg, formatHex( sessionHandle ) );
            exit( 1 );
        }
    }

    #if false
    {
        ntdll := LoadLibraryA( "ntdll.dll" );
        if ntdll == null
        {
            log_error( "Failed loading library ntdll.dll!" );
            exit( 1 );
        }
        NtQueryPerformanceCounter: NtQueryPerformanceCounterType = GetProcAddress( ntdll, "NtQueryPerformanceCounter" );
        if NtQueryPerformanceCounter == null
        {
            log_error( "Failed loading entry point for NtQueryPerformanceCounter!" );
            exit( 1 );
        }

        // while true
        {
            pc, freq: LARGE_INTEGER;
            NtQueryPerformanceCounter( *pc, *freq );

            log( ">>> Counter: %\n", pc.QuadPart );
        }
    }

    Sleep( 1000 );

    log( "Closing trace...\n" );

    // stop producing new events
    status = ControlTraceW( sessionHandle, null, xx props, EVENT_TRACE_CONTROL_STOP );
    if status != ERROR_SUCCESS
    {
        msg := get_error_string( xx status );
        log_error( "ControlTraceW failed with error % (%)", status, msg );
        // exit( 1 );
    }

    // closes trace processing, this will make ETW to process all the pending events in buffers
    status = CloseTrace( traceHandle );
    if status != ERROR_SUCCESS && status != ERROR_CTX_CLOSE_PENDING
    {
        msg := get_error_string( xx status );
        log_error( "CloseTrace failed with error % (%)", status, msg );
        // exit( 1 );
    }

    // Wait for thread to finish
    while !thread_is_done( *processingThread, -1 )
    {}
    thread_deinit( *processingThread );

    log( "Processed events: %\n", globalProcessedEventCount );
    log( "OK" );
}

ProcessingThreadProc :: ( thread: *Thread ) -> s64
{
    traceHandle := cast(TRACEHANDLE) thread.data;

    log( "##### Beginning of ProcessTrace output:\n" );
    status := ProcessTrace( *traceHandle, 1, null, null );
    if status != ERROR_SUCCESS
    {
        msg := get_error_string( xx status );
        log_error( "ProcessTrace failed with error % (%)", status, msg );
        exit( 1 );
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

formatHex :: #bake_arguments formatInt(base = 16, padding = #char "0");

// TODO Ideally should be our own formatter
ToGuidString :: ( guid: GUID ) -> string
{
    return tprint( "%-%-%-%0%0-%0%0%0%0%0%0",
                    formatHex( guid.Data1, minimum_digits = 8 ),
                    formatHex( guid.Data2, minimum_digits = 4 ),
                    formatHex( guid.Data3, minimum_digits = 4 ),
                    formatHex( guid.Data4[0], minimum_digits = 2 ),
                    formatHex( guid.Data4[1], minimum_digits = 2 ),
                    formatHex( guid.Data4[2], minimum_digits = 2 ),
                    formatHex( guid.Data4[3], minimum_digits = 2 ),
                    formatHex( guid.Data4[4], minimum_digits = 2 ),
                    formatHex( guid.Data4[5], minimum_digits = 2 ),
                    formatHex( guid.Data4[6], minimum_digits = 2 ),
                    formatHex( guid.Data4[7], minimum_digits = 2 ),
               );
}

globalProcessedEventCount: int;
MyEventRecordCallback :: ( eventRecord: *EVENT_RECORD ) #c_call
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

MyProviderControlCallback :: ( requestCode: WMIDPREQUESTCODE, requestContext: *void, reserved: *ULONG, header: *void ) -> ULONG #c_call
{
    ctx: Context;
    push_context ctx
    {
        status: ULONG = ERROR_INVALID_PARAMETER;

        if requestCode ==
        {
            case .WMI_ENABLE_EVENTS;
            {
                globalProviderSessionHandle = GetTraceLoggerHandle( header );
                if cast(HANDLE)globalProviderSessionHandle == INVALID_HANDLE_VALUE
                {
                    err, msg := get_error_value_and_string();
                    log_error( "GetTraceLoggerHandle failed with error % (%)", err, msg );
                }
                else
                {
                    log( "##### Got provider handle: 0x%\n", formatHex( globalProviderSessionHandle ) );
                }
            }
            case .WMI_DISABLE_EVENTS;
            {

            }
        }

        return status;
    }
}
