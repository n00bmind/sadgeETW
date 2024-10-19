#import "Basic";
#import "Windows";
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
LPWSTR :: *u16;

ERROR_SUCCESS :: 0;
// TODO I'm not sure why this doesnt compile
// INVALID_PROCESSTRACE_HANDLE :: cast(TRACEHANDLE) INVALID_HANDLE_VALUE;

EVENT_TRACE_CONTROL_STOP :: 1;
EVENT_TRACE_FLAG_CSWITCH :: 0x00000010;  // context switches
EVENT_TRACE_REAL_TIME_MODE :: 0x00000100;  // Real time mode on
PROCESS_TRACE_MODE_REAL_TIME                :: 0x00000100;
PROCESS_TRACE_MODE_RAW_TIMESTAMP            :: 0x00001000;
PROCESS_TRACE_MODE_EVENT_RECORD             :: 0x10000000;

WNODE_FLAG_TRACED_GUID :: 0x00020000; // denotes a trace

KERNEL_LOGGER_NAMEA :: "NT Kernel Logger";


WNODE_HEADER :: struct
{
    BufferSize: ULONG;        // Size of entire buffer inclusive of this ULONG
    ProviderId: ULONG;    // Provider Id of driver returning this buffer
    union
    {
        HistoricalContext: ULONG64;  // Logger use
        struct
        {
            Version: ULONG;           // Reserved
            Linkage: ULONG;           // Linkage field reserved for WMI
        }
    }

    union
    {
        CountLost: ULONG;         // Reserved
        KernelHandle: HANDLE;     // Kernel handle for data block
        TimeStamp: LARGE_INTEGER; // Timestamp as returned in units of 100ns since 1/1/1601
    }
    Guid: GUID;                  // Guid for data block returned with results
    ClientContext: ULONG;
    Flags: ULONG;             // Flags, see below
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
PEVENT_TRACE_PROPERTIES :: *EVENT_TRACE_PROPERTIES;

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
        Class ::struct
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
PEVENT_RECORD :: *EVENT_RECORD;

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
    TimeZone:                TIME_ZONE_INFORMATION;
// #endif
    BootTime:                LARGE_INTEGER;
    PerfFreq:                LARGE_INTEGER; // Reserved
    StartTime:               LARGE_INTEGER; // Reserved
    ReservedFlags:           ULONG;         // ClockType
    BuffersLost:             ULONG;
}

EVENT_TRACE_LOGFILEA :: struct
{
    LogFileName:             LPSTR;                         // Logfile Name
    LoggerName:              LPSTR;                         // LoggerName
    CurrentTime:             LONGLONG;                      // timestamp of last event
    BuffersRead:             ULONG;                         // buffers read to date
    union
    {
        LogFileMode:         ULONG;                         // Mode of the logfile
        ProcessTraceMode:    ULONG;                         // Processing flags
    };
    CurrentEvent:            EVENT_TRACE;                   // Current Event from this stream
    LogfileHeader:           TRACE_LOGFILE_HEADER;          // logfile header structure
    BufferCallback:          PEVENT_TRACE_BUFFER_CALLBACKA; // callback before each buffer is read

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
PEVENT_TRACE_LOGFILEA :: *EVENT_TRACE_LOGFILEA;


// TODO Any way to do this auto linking, but for dlls?
wmi :: #system_library "wmi";

ControlTraceAType             :: #type ( TraceHandle: TRACEHANDLE, InstanceName: LPCSTR, Properties: PEVENT_TRACE_PROPERTIES, ControlCode: ULONG ) -> ULONG #c_call;
// StartTraceA :: ( TraceId: *TRACEHANDLE, InstanceName: LPCSTR, Properties: PEVENT_TRACE_PROPERTIES ) -> ULONG #foreign wmi;
StartTraceAType               :: #type ( TraceHandle: *TRACEHANDLE, InstanceName: LPCSTR, Properties: PEVENT_TRACE_PROPERTIES ) -> ULONG #c_call;
OpenTraceAType                :: #type ( LogFile: PEVENT_TRACE_LOGFILEA ) -> TRACEHANDLE #c_call;
ProcessTraceType              :: #type ( HandleArray: *TRACEHANDLE, HandleCount: ULONG, StartTime: *FILETIME, EndTime: *FILETIME ) -> ULONG #c_call;
PEVENT_CALLBACK               :: #type ( Event: PEVENT_TRACE ) #c_call;
PEVENT_RECORD_CALLBACK        :: #type ( EventRecord: PEVENT_RECORD ) #c_call;
PEVENT_TRACE_BUFFER_CALLBACKA :: #type ( LogFile: PEVENT_TRACE_LOGFILEA ) -> ULONG #c_call;

DefineGUID :: ( l: u32, w1: u16, w2: u16, b1: u8, b2: u8, b3: u8, b4: u8, b5: u8, b6: u8, b7: u8, b8: u8 ) -> GUID #expand
{
    return GUID.{ l, w1, w2, u8.[ b1, b2, b3, b4, b5, b6, b7, b8 ] };
}

main :: ()
{
    tracingThread: Thread;
    if !thread_init( *tracingThread, ThreadProc )
    {
        log_error( "Failed to create tracing thread!" );
        exit( 1 );
    }
    thread_start( *tracingThread );

    // Wait for it to finish
    while !thread_is_done( *tracingThread, -1 )
    {}

    thread_deinit( *tracingThread );
}

ThreadProc :: ( thread: *Thread ) -> s64
{
    wmi := LoadLibraryA( "wmi.dll" );
    if wmi == null
    {
        log_error( "Failed loading library wmi.dll!" );
        exit( 1 );
    }

    ControlTraceA: ControlTraceAType = GetProcAddress( wmi, "ControlTraceA" );
    if ControlTraceA == null
    {
        log_error( "Failed loading entry point for ControlTraceA!" );
        exit( 1 );
    }
    StartTraceA: StartTraceAType = GetProcAddress( wmi, "StartTraceA" );
    if StartTraceA == null
    {
        log_error( "Failed loading entry point for StartTraceA!" );
        exit( 1 );
    }
    OpenTraceA: OpenTraceAType = GetProcAddress( wmi, "OpenTraceA" );
    if OpenTraceA == null
    {
        log_error( "Failed loading entry point for OpenTraceA!" );
        exit( 1 );
    }
    ProcessTrace: ProcessTraceType = GetProcAddress( wmi, "ProcessTrace" );
    if ProcessTrace == null
    {
        log_error( "Failed loading entry point for ProcessTrace!" );
        exit( 1 );
    }

    /* 9e814aad-3204-11d2-9a82-006008a86939 */
    SystemTraceControlGuid :: #run DefineGUID(
        0x9e814aad,
        0x3204,
        0x11d2,
        0x9a, 0x82, 0x00, 0x60, 0x08, 0xa8, 0x69, 0x39
    );


    propsBufferSize := size_of(EVENT_TRACE_PROPERTIES) + KERNEL_LOGGER_NAMEA.count + 1;
    props := cast(*EVENT_TRACE_PROPERTIES) alloc( propsBufferSize );
    memset( props, 0, propsBufferSize );
    // We still need to manually copy this ourselves to be able to call ControlTrace
    memcpy( cast(*u8)props + size_of(EVENT_TRACE_PROPERTIES), temp_c_string( KERNEL_LOGGER_NAMEA ), KERNEL_LOGGER_NAMEA.count + 1 );

    props.LoggerNameOffset = size_of(EVENT_TRACE_PROPERTIES);
    props.Wnode.BufferSize = xx propsBufferSize;

    status := ControlTraceA( 0, temp_c_string( KERNEL_LOGGER_NAMEA ), props, EVENT_TRACE_CONTROL_STOP );
    if status != ERROR_SUCCESS
    {
        msg: string = "unknown";
        if status ==
        {
            case ERROR_ACCESS_DENIED; msg = "access denied";
            case ERROR_ALREADY_EXISTS; msg = "session already exists";
        }
        log_error( "ControlTraceA failed with error % (%)", status, msg );
        // exit( 1 );
    }


    memset( props, 0, propsBufferSize );
    props.LoggerNameOffset = size_of(EVENT_TRACE_PROPERTIES);
    props.EnableFlags = EVENT_TRACE_FLAG_CSWITCH;
    props.LogFileMode = EVENT_TRACE_REAL_TIME_MODE;
    props.Wnode.BufferSize = xx propsBufferSize;
    props.Wnode.Flags = WNODE_FLAG_TRACED_GUID;
    // Timestamps from QueryPerformanceCounter
    props.Wnode.ClientContext = 1;
    props.Wnode.Guid = SystemTraceControlGuid;

    sessionHandle: TRACEHANDLE;
    status = StartTraceA( *sessionHandle, temp_c_string( KERNEL_LOGGER_NAMEA ), props );

    if status != ERROR_SUCCESS
    {
        msg: string = "unknown";
        if status ==
        {
            case ERROR_ACCESS_DENIED; msg = "access denied";
            case ERROR_ALREADY_EXISTS; msg = "session already exists";
        }
        log_error( "StartTraceA failed with error % (%)", status, msg );
        exit( 1 );
    }


    logFile: EVENT_TRACE_LOGFILEA;
    logFile.LoggerName = temp_c_string( KERNEL_LOGGER_NAMEA );
    logFile.ProcessTraceMode = (PROCESS_TRACE_MODE_REAL_TIME | PROCESS_TRACE_MODE_EVENT_RECORD | PROCESS_TRACE_MODE_RAW_TIMESTAMP);
    logFile.EventRecordCallback = MyEventRecordCallback;

    traceHandle := OpenTraceA( *logFile );
    if traceHandle == cast(TRACEHANDLE) INVALID_HANDLE_VALUE //INVALID_PROCESSTRACE_HANDLE
    {
        err, msg := get_error_value_and_string();
        log_error( "OpenTraceA failed with error % (%)", err, msg );
        exit( 1 );
    }

    status = ProcessTrace( *traceHandle, 1, null, null );
    if status != ERROR_SUCCESS
    {
        msg: string = "unknown";
        if status ==
        {
            case ERROR_ACCESS_DENIED; msg = "access denied";
        }
        log_error( "ProcessTrace failed with error % (%)", status, msg );
        exit( 1 );
    }

    print( "OK\n" );
    return 0;
}

MyEventRecordCallback :: ( EventRecord: PEVENT_RECORD ) #c_call
{
    ctx: Context;
    push_context ctx
    {
        header := EventRecord.EventHeader;

        ProcessorNumber: UCHAR = EventRecord.BufferContext.ProcessorNumber;
        ThreadId: ULONG  = header.ThreadId;
        timeCycles: s64 = header.TimeStamp.QuadPart;

        // Process event here.
        print( "Got event for cpu % / thread % with timestamp %\n", ProcessorNumber, ThreadId, timeCycles );
    }
}

