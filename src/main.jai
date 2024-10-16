#import "Basic";
#import "Windows";


LONG :: s32;
ULONG :: u32;
ULONG64 :: u64;
TRACEHANDLE :: u64;

ERROR_SUCCESS :: 0;

EVENT_TRACE_CONTROL_STOP :: 1;
EVENT_TRACE_FLAG_CSWITCH :: 0x00000010;  // context switches
EVENT_TRACE_REAL_TIME_MODE :: 0x00000100;  // Real time mode on

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


// TODO Any way to do this auto linking, but for dlls?
sechost :: #system_library "sechost";

ControlTraceAType :: #type ( TraceHandle: TRACEHANDLE, InstanceName: LPCSTR, Properties: PEVENT_TRACE_PROPERTIES, ControlCode: ULONG ) -> ULONG #c_call;
// StartTraceA :: ( TraceId: *TRACEHANDLE, InstanceName: LPCSTR, Properties: PEVENT_TRACE_PROPERTIES ) -> ULONG #foreign sechost;
StartTraceAType :: #type ( TraceHandle: *TRACEHANDLE, InstanceName: LPCSTR, Properties: PEVENT_TRACE_PROPERTIES ) -> ULONG #c_call;

DefineGUID :: ( l: u32, w1: u16, w2: u16, b1: u8, b2: u8, b3: u8, b4: u8, b5: u8, b6: u8, b7: u8, b8: u8 ) -> GUID #expand
{
    return GUID.{ l, w1, w2, u8.[ b1, b2, b3, b4, b5, b6, b7, b8 ] };
}

main :: ()
{
    sechost := LoadLibraryA( "sechost.dll" );
    if sechost == null
    {
        log_error( "Failed loading library sechost.dll!" );
        exit( 1 );
    }

    ControlTraceA: ControlTraceAType = GetProcAddress( sechost, "ControlTraceA" );
    if ControlTraceA == null
    {
        log_error( "Failed loading entry point for ControlTraceA!" );
        exit( 1 );
    }
    StartTraceA: StartTraceAType = GetProcAddress( sechost, "StartTraceA" );
    if StartTraceA == null
    {
        log_error( "Failed loading entry point for StartTraceA!" );
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
    else
    print( "OK\n" );
}
