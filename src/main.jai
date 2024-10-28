#import "Basic";
#import "Windows";
#import "Windows_Utf8";
#import "System";
#import "Thread";


LONG :: s32;
LONGLONG :: s64;
UCHAR :: u8;
USHORT :: u16;
ULONG :: u32;
ULONG64 :: u64;
ULONGLONG :: u64;
TRACEHANDLE :: u64;
PVOID :: *void;
WCHAR :: u16;
LPWSTR :: *u16;

ERROR_SUCCESS                       :: 0;
ERROR_INVALID_PARAMETER             :: 87;
ERROR_CTX_CLOSE_PENDING             :: 7007;

// TODO I'm not sure why this doesnt compile
// INVALID_PROCESSTRACE_HANDLE :: cast(TRACEHANDLE) INVALID_HANDLE_VALUE;

EVENT_TRACE_CONTROL_STOP            :: 1;
EVENT_TRACE_FLAG_THREAD             :: 0x00000002;  // thread start & end
EVENT_TRACE_FLAG_CSWITCH            :: 0x00000010;  // context switches
EVENT_TRACE_FLAG_SYSTEMCALL         :: 0x00000080;  // system calls
EVENT_TRACE_FLAG_MEMORY_PAGE_FAULTS :: 0x00001000;  // all page faults
EVENT_TRACE_FLAG_NO_SYSCONFIG       :: 0x10000000;  // Do not do sys config rundown
EVENT_TRACE_REAL_TIME_MODE          :: 0x00000100;  // Real time mode on
EVENT_TRACE_SYSTEM_LOGGER_MODE      :: 0x02000000;  // Receive events from SystemTraceProvider
PROCESS_TRACE_MODE_REAL_TIME        :: 0x00000100;
PROCESS_TRACE_MODE_RAW_TIMESTAMP    :: 0x00001000;
PROCESS_TRACE_MODE_EVENT_RECORD     :: 0x10000000;
EVENT_HEADER_FLAG_PROCESSOR_INDEX   :: 0x0200;

WNODE_FLAG_TRACED_GUID              :: 0x00020000; // denotes a trace
WNODE_FLAG_VERSIONED_PROPERTIES     :: 0x00800000;

KERNEL_LOGGER_NAMEA                 :: "NT Kernel Logger";


WNODE_HEADER :: struct
{
    BufferSize:            ULONG;         // Size of entire buffer inclusive of this ULONG
    ProviderId:            ULONG;         // Provider Id of driver returning this buffer
    union
    {
        HistoricalContext: ULONG64;       // Logger use
        struct
        {
            Version:       ULONG;         // Reserved
            Linkage:       ULONG;         // Linkage field reserved for WMI
        }
    }

    union
    {
        CountLost:         ULONG;         // Reserved
        KernelHandle:      HANDLE;        // Kernel handle for data block
        TimeStamp:         LARGE_INTEGER; // Timestamp as returned in units of 100ns since 1/1/1601
    }
    Guid:                  GUID;          // Guid for data block returned with results
    ClientContext:         ULONG;
    Flags:                 ULONG;         // Flags, see below
}

EVENT_TRACE_PROPERTIES :: struct
{
    Wnode:               WNODE_HEADER;

    // data provided by caller
    BufferSize:          ULONG;  // buffer size for logging (kbytes)
    MinimumBuffers:      ULONG;  // minimum to preallocate
    MaximumBuffers:      ULONG;  // maximum buffers allowed
    MaximumFileSize:     ULONG;  // maximum logfile size (in MBytes)
    LogFileMode:         ULONG;  // sequential, circular
    FlushTimer:          ULONG;  // buffer flush timer, in seconds
    EnableFlags:         ULONG;  // trace enable flags
    union {
        AgeLimit:        LONG;   // unused
        FlushThreshold:  LONG;   // Number of buffers to fill before flushing
    }

    // data returned to caller
    NumberOfBuffers:     ULONG;  // no of buffers in use
    FreeBuffers:         ULONG;  // no of buffers free
    EventsLost:          ULONG;  // event records lost
    BuffersWritten:      ULONG;  // no of buffers written to file
    LogBuffersLost:      ULONG;  // no of logfile write failures
    RealTimeBuffersLost: ULONG;  // no of rt delivery failures
    LoggerThreadId:      HANDLE; // thread id of Logger
    LogFileNameOffset:   ULONG;  // Offset to LogFileName
    LoggerNameOffset:    ULONG;  // Offset to LoggerName
}

EVENT_TRACE_PROPERTIES_V2 :: struct
{
    Wnode:                 WNODE_HEADER;             // Always have WNODE_FLAG_VERSIONED_PROPERTIES.

    // data provided by caller
    BufferSize:            ULONG;                    // buffer size for logging (kbytes)
    MinimumBuffers:        ULONG;                    // minimum to preallocate
    MaximumBuffers:        ULONG;                    // maximum buffers allowed
    MaximumFileSize:       ULONG;                    // maximum logfile size (in MBytes)
    LogFileMode:           ULONG;                    // sequential, circular
    FlushTimer:            ULONG;                    // buffer flush timer, in seconds
    EnableFlags:           ULONG;                    // trace enable flags
    union {
        AgeLimit:          LONG;                     // unused
        FlushThreshold:    LONG;                     // Number of buffers to fill before flushing
    }

    // data returned to caller
    NumberOfBuffers:       ULONG;                    // no of buffers in use
    FreeBuffers:           ULONG;                    // no of buffers free
    EventsLost:            ULONG;                    // event records lost
    BuffersWritten:        ULONG;                    // no of buffers written to file
    LogBuffersLost:        ULONG;                    // no of logfile write failures
    RealTimeBuffersLost:   ULONG;                    // no of rt delivery failures
    LoggerThreadId:        HANDLE;                   // thread id of Logger
    LogFileNameOffset:     ULONG;                    // Offset to LogFileName
    LoggerNameOffset:      ULONG;                    // Offset to LoggerName

    // V2 data
    union {
        struct {
            VersionNumber: UCHAR;                // Should be set to 2 for this version.
        }
        V2Control:         ULONG;
    }
    FilterDescCount:       ULONG;                    // Number of filters
    FilterDesc:            *EVENT_FILTER_DESCRIPTOR; // Only applicable for Private Loggers
    union {
        struct {
            Wow:           ULONG;               // Logger was started by a WOW64 process (output only).
        }
        V2Options:         ULONG64;
    }
}

EVENT_FILTER_DESCRIPTOR :: struct
{
    Ptr:  ULONGLONG;
    Size: ULONG;
    Type: ULONG;
}

// overlays WNODE_HEADER
EVENT_TRACE_HEADER :: struct
{
    Size:                  USHORT;        // Size of entire record
    union
    {
        FieldTypeFlags:    USHORT;        // Indicates valid fields
        struct
        {
            HeaderType:    UCHAR;         // Header type - internal use only
            MarkerFlags:   UCHAR;         // Marker - internal use only
        }
    }
    union
    {
        Version:           ULONG;
        Class: struct
        {
            Type:          UCHAR;         // event type
            Level:         UCHAR;         // trace instrumentation level
            Version:       USHORT;        // version of trace record
        }
    }
    ThreadId:              ULONG;         // Thread Id
    ProcessId:             ULONG;         // Process Id
    TimeStamp:             LARGE_INTEGER; // time when event happens
    union
    {
        Guid:              GUID;          // Guid that identifies event
        GuidPtr:           ULONGLONG;     // use with WNODE_FLAG_USE_GUID_PTR
    }
    union
    {
        struct
        {
            KernelTime:    ULONG;         // Kernel Mode CPU ticks
            UserTime:      ULONG;         // User mode CPU ticks
        }
        ProcessorTime:     ULONG64;       // Processor Clock
        struct
        {
            ClientContext: ULONG;         // Reserved
            Flags:         ULONG;         // Event Flags
        }
    }
}

ETW_BUFFER_CONTEXT :: struct
{
    union
    {
        struct
        {
            ProcessorNumber: UCHAR;
            Alignment:       UCHAR;
        }
        ProcessorIndex:      USHORT;
    }
    LoggerId:                USHORT;
}

EVENT_TRACE :: struct
{
    Header:            EVENT_TRACE_HEADER; // Event trace header
    InstanceId:        ULONG;              // Instance Id of this event
    ParentInstanceId:  ULONG;              // Parent Instance Id.
    ParentGuid:        GUID;               // Parent Guid;
    MofData:           PVOID;              // Pointer to Variable Data
    MofLength:         ULONG;              // Variable Datablock Length
    union
    {
        ClientContext: ULONG;
        BufferContext: ETW_BUFFER_CONTEXT;
    };
}
PEVENT_TRACE :: *EVENT_TRACE;

EVENT_DESCRIPTOR :: struct
{
    Id:      USHORT;
    Version: UCHAR;
    Channel: UCHAR;
    Level:   UCHAR;
    Opcode:  UCHAR;
    Task:    USHORT;
    Keyword: ULONGLONG;
}

EVENT_HEADER :: struct
{
    Size:               USHORT;           // Event Size
    HeaderType:         USHORT;           // Header Type
    Flags:              USHORT;           // Flags
    EventProperty:      USHORT;           // User given event property
    ThreadId:           ULONG;            // Thread Id
    ProcessId:          ULONG;            // Process Id
    TimeStamp:          LARGE_INTEGER;    // Event Timestamp
    ProviderId:         GUID;             // Provider Id
    EventDescriptor:    EVENT_DESCRIPTOR; // Event Descriptor
    union
    {
        struct
        {
            KernelTime: ULONG;            // Kernel Mode CPU ticks
            UserTime:   ULONG;            // User mode CPU ticks
        }
        ProcessorTime:  ULONG64;          // Processor Clock for private session events
    }
    ActivityId:         GUID;             // Activity Id
}

EVENT_HEADER_EXTENDED_DATA_ITEM :: struct
{
    Reserved1:   USHORT;    // Reserved for internal use
    ExtType:     USHORT;    // Extended info type
    struct
    {
        // USHORT  Linkage             :  1;       // Indicates additional extended data item
        // USHORT  Reserved2           : 15;
        Linkage: USHORT;
    }
    DataSize:    USHORT;    // Size of extended info data
    DataPtr:     ULONGLONG; // Pointer to extended info data
} 
PEVENT_HEADER_EXTENDED_DATA_ITEM :: *EVENT_HEADER_EXTENDED_DATA_ITEM;

EVENT_RECORD :: struct
{
    EventHeader:       EVENT_HEADER;                     // Event header
    BufferContext:     ETW_BUFFER_CONTEXT;               // Buffer context
    ExtendedDataCount: USHORT;                           // Number of extended data items
    UserDataLength:    USHORT;                           // User data length
    ExtendedData:      PEVENT_HEADER_EXTENDED_DATA_ITEM; // Pointer to an array of extended data items
    UserData:          PVOID;                            // Pointer to user data
    UserContext:       PVOID;                            // Context from OpenTrace
}

// TODO BUG: This struct is defined as empty in Windows.jai, which cost me a good few hours of sleuthing!
MY_TIME_ZONE_INFORMATION :: struct
{
    Bias: LONG;
    StandardName: [ 32 ]WCHAR;
    StandardDate: SYSTEMTIME;
    StandardBias: LONG;
    DaylightName: [ 32 ]WCHAR;
    DaylightDate: SYSTEMTIME;
    DaylightBias: LONG;
}

TRACE_LOGFILE_HEADER :: struct
{
    BufferSize:              ULONG;         // Logger buffer size in Kbytes
    union
    {
        Version:             ULONG;         // Logger version
        VersionDetail :: struct
        {
            MajorVersion:    UCHAR;
            MinorVersion:    UCHAR;
            SubVersion:      UCHAR;
            SubMinorVersion: UCHAR;
        }
    }
    ProviderVersion:         ULONG;         // defaults to NT version
    NumberOfProcessors:      ULONG;         // Number of Processors
    EndTime:                 LARGE_INTEGER; // Time when logger stops
    TimerResolution:         ULONG;         // assumes timer is constant!!!
    MaximumFileSize:         ULONG;         // Maximum in Mbytes
    LogFileMode:             ULONG;         // specify logfile mode
    BuffersWritten:          ULONG;         // used to file start of Circular File
    union
    {
        LogInstanceGuid:     GUID;          // For RealTime Buffer Delivery
        struct
        {
            StartBuffers:    ULONG;         // Count of buffers written at start.
            PointerSize:     ULONG;         // Size of pointer type in bits
            EventsLost:      ULONG;         // Events lost during log session
            CpuSpeedInMHz:   ULONG;         // Cpu Speed in MHz
        }
    }
    // NOTE I assume this must mean "kernel mode"?
// #if defined(_WMIKM_)
//     PWCHAR          LoggerName;
//     PWCHAR          LogFileName;
//     RTL_TIME_ZONE_INFORMATION TimeZone;
// #else
    LoggerName:              LPWSTR;
    LogFileName:             LPWSTR;
    TimeZone:                MY_TIME_ZONE_INFORMATION;  // NOTE See definition above
// #endif
    BootTime:                LARGE_INTEGER;
    PerfFreq:                LARGE_INTEGER; // Reserved
    StartTime:               LARGE_INTEGER; // Reserved
    ReservedFlags:           ULONG;         // ClockType
    BuffersLost:             ULONG;
}

EVENT_TRACE_LOGFILEW :: struct
{
    LogFileName:             LPWSTR;                        // Logfile Name
    LoggerName:              LPWSTR;                        // LoggerName
    CurrentTime:             LONGLONG;                      // timestamp of last event
    BuffersRead:             ULONG;                         // buffers read to date
    union
    {
        LogFileMode:         ULONG;                         // Mode of the logfile
        ProcessTraceMode:    ULONG;                         // Processing flags
    };
    CurrentEvent:            EVENT_TRACE;                   // Current Event from this stream
    LogfileHeader:           TRACE_LOGFILE_HEADER;          // logfile header structure
    BufferCallback:          PEVENT_TRACE_BUFFER_CALLBACKW; // callback before each buffer is read

    //
    // following variables are filled for BufferCallback.
    //
    BufferSize:              ULONG;
    Filled:                  ULONG;
    EventsLost:              ULONG;
    //
    // following needs to be propaged to each buffer
    //
    union
    {
        EventCallback:       PEVENT_CALLBACK;               // callback for every event
        EventRecordCallback: PEVENT_RECORD_CALLBACK;
    };
    IsKernelTrace:           ULONG;                         // TRUE for kernel logfile
    Context:                 PVOID;                         // reserved for internal use
};
PEVENT_TRACE_LOGFILEW :: *EVENT_TRACE_LOGFILEW;

TRACE_QUERY_INFO_CLASS :: enum
{
    TraceGuidQueryList;
    TraceGuidQueryInfo;
    TraceGuidQueryProcess;
    TraceStackTracingInfo;   // Win7
    TraceSystemTraceEnableFlagsInfo;
    TraceSampledProfileIntervalInfo;
    TraceProfileSourceConfigInfo;
    TraceProfileSourceListInfo;
    TracePmcEventListInfo;
    TracePmcCounterListInfo;
    TraceSetDisallowList;
    TraceVersionInfo;
    TraceGroupQueryList;
    TraceGroupQueryInfo;
    TraceDisallowListQuery;
    TraceCompressionInfo;
    TracePeriodicCaptureStateListInfo;
    TracePeriodicCaptureStateInfo;
    TraceProviderBinaryTracking;
    TraceMaxLoggersQuery;
    MaxTraceSetInfoClass;
}
TRACE_INFO_CLASS :: TRACE_QUERY_INFO_CLASS;

PROFILE_SOURCE_INFO :: struct
{
    NextEntryOffset: ULONG;
    Source:          ULONG;
    MinInterval:     ULONG;
    MaxInterval:     ULONG;
    Reserved:        ULONG64;
    // TODO 
    Description:     [0]WCHAR;
}

CLASSIC_EVENT_ID :: struct
{
    EventGuid: GUID;
    Type:      UCHAR;
    Reserved:  [7]UCHAR;
}

TRACE_GUID_REGISTRATION :: struct
{
    Guid:      *GUID;           // Guid of data block being registered or updated.
    RegHandle: HANDLE;          // Guid Registration Handle is returned.
}

WMIDPREQUESTCODE :: enum
{
    WMI_GET_ALL_DATA :: 0;
    WMI_GET_SINGLE_INSTANCE :: 1;
    WMI_SET_SINGLE_INSTANCE :: 2;
    WMI_SET_SINGLE_ITEM :: 3;
    WMI_ENABLE_EVENTS :: 4;
    WMI_DISABLE_EVENTS :: 5;
    WMI_ENABLE_COLLECTION :: 6;
    WMI_DISABLE_COLLECTION :: 7;
    WMI_REGINFO :: 8;
    WMI_EXECUTE_METHOD :: 9;
    WMI_CAPTURE_STATE :: 10;
}

NtQueryPerformanceCounterType :: #type ( PerformanceCounter: *LARGE_INTEGER, PerformanceFrequency: *LARGE_INTEGER ) -> NTSTATUS #c_call;
PEVENT_CALLBACK               :: #type ( Event: PEVENT_TRACE ) #c_call;
PEVENT_RECORD_CALLBACK        :: #type ( EventRecord: *EVENT_RECORD ) #c_call;
PEVENT_TRACE_BUFFER_CALLBACKW :: #type ( LogFile: PEVENT_TRACE_LOGFILEW ) -> ULONG #c_call;
WMIDPREQUEST                  :: #type ( RequestCode: WMIDPREQUESTCODE, RequestContext: *void, BufferSize: *ULONG, Buffer: *void ) -> ULONG #c_call;

advapi32 :: #system_library "advapi32";

ControlTraceW             :: ( TraceHandle: TRACEHANDLE, InstanceName: LPCWSTR, Properties: *EVENT_TRACE_PROPERTIES, ControlCode: ULONG ) -> ULONG #foreign advapi32;
StartTraceW               :: ( TraceHandle: *TRACEHANDLE, InstanceName: LPCWSTR, Properties: *EVENT_TRACE_PROPERTIES ) -> ULONG #foreign advapi32;
OpenTraceW                :: ( LogFile: PEVENT_TRACE_LOGFILEW ) -> TRACEHANDLE #foreign advapi32;
TraceQueryInformation     :: ( SessionHandle: TRACEHANDLE, InformationClass: TRACE_INFO_CLASS, TraceInformation: *void, InformationLength: ULONG, ReturnLength: *ULONG ) -> ULONG #foreign advapi32;
TraceSetInformation       :: ( SessionHandle: TRACEHANDLE, InformationClass: TRACE_INFO_CLASS, TraceInformation: *void, InformationLength: ULONG ) -> ULONG #foreign advapi32;
ProcessTrace              :: ( HandleArray: *TRACEHANDLE, HandleCount: ULONG, StartTime: *FILETIME, EndTime: *FILETIME ) -> ULONG #foreign advapi32;
RegisterTraceGuidsW       :: ( RequestAddress: WMIDPREQUEST, RequestContext: *void, ControlGuid: *GUID, GuidCount: ULONG, TraceGuidReg: *TRACE_GUID_REGISTRATION, MofImagePath: LPCWSTR, MofResourceName: LPCWSTR, RegistrationHandle: *TRACEHANDLE ) -> ULONG #foreign advapi32;
TraceEvent                :: ( TraceHandle: TRACEHANDLE, EventTrace: *EVENT_TRACE_HEADER ) -> ULONG #foreign advapi32;
GetTraceLoggerHandle      :: ( Buffer: *void ) -> TRACEHANDLE #foreign advapi32;
EnableTrace               :: ( Enable: ULONG, EnableFlag: ULONG, EnableLevel: ULONG, ControlGuid: *GUID, TraceHandle: TRACEHANDLE ) -> ULONG #foreign advapi32;
CloseTrace                :: ( TraceHandle: TRACEHANDLE ) -> ULONG #foreign advapi32;

DefineGUID :: ( l: u32, w1: u16, w2: u16, b1: u8, b2: u8, b3: u8, b4: u8, b5: u8, b6: u8, b7: u8, b8: u8 ) -> GUID #expand
{
    return GUID.{ l, w1, w2, u8.[ b1, b2, b3, b4, b5, b6, b7, b8 ] };
}

/* 9e814aad-3204-11d2-9a82-006008a86939 */
SystemTraceControlGuid :: #run DefineGUID(
    0x9e814aad,
    0x3204,
    0x11d2,
    0x9a, 0x82, 0x00, 0x60, 0x08, 0xa8, 0x69, 0x39
);

/* 3d6fa8d1-fe05-11d0-9dda-00c04fd7ba7c */
ThreadGuid :: #run DefineGUID(
    0x3d6fa8d1,
    0xfe05,
    0x11d0,
    0x9d, 0xda, 0x00, 0xc0, 0x4f, 0xd7, 0xba, 0x7c
);

/* ce1dbfb4-137e-4da6-87b0-3f59aa102cbc */
PerfInfoGuid :: #run DefineGUID(
    0xce1dbfb4,
    0x137e,
    0x4da6,
    0x87, 0xb0, 0x3f, 0x59, 0xaa, 0x10, 0x2c, 0xbc
);

// {5E60DAA3-471D-49B2-B608-B1FF493AE160}
MyEventGuid :: #run DefineGUID(
    0x5e60daa3,
    0x471d,
    0x49b2,
    0xb6, 0x8, 0xb1, 0xff, 0x49, 0x3a, 0xe1, 0x60
);

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

    
    // TODO First execution after a reboot shows context switches, but any other runs after that dont!!
    // TODO Put a time limit on the main thread wait and ensure we're properly shutting down everything!?


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


        lolThread: Thread;
        if !thread_init( *lolThread, LolThreadProc )
        {
            log_error( "Failed to create lol thread!" );
            exit( 1 );
        }
        thread_start( *lolThread );
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

LolThreadProc :: ( thread: *Thread ) -> s64
{
    total: u64;
    while ( true )
    {
        total += 236;
        // print( "New total: %\n", total );
    }

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
        log( "% -> New event for cpu % / thread %\n", timeCycles, ProcessorNumber, ThreadId );
        log( "   %, user: %, extended: %\n", ToGuidString( header.ProviderId ), eventRecord.UserDataLength, eventRecord.ExtendedDataCount );
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
