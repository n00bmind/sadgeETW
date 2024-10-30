
TestSample :: #string END
“Did you,” so he asked him at one time, “did you too learn that secret
from the river: that there is no time?”

Vasudeva’s face was filled with a bright smile.

“Yes, Siddhartha,” he spoke. “It is this what you mean, isn’t it: that
the river is everywhere at once, at the source and at the mouth, at the
waterfall, at the ferry, at the rapids, in the sea, in the mountains,
everywhere at once, and that there is only the present time for it, not
the shadow of the past, not the shadow of the future?”

“This it is,” said Siddhartha. “And when I had learned it, I looked at
my life, and it was also a river, and the boy Siddhartha was only
separated from the man Siddhartha and from the old man Siddhartha by a
shadow, not by something real. Also, Siddhartha’s previous births were
no past, and his death and his return to Brahma was no future. Nothing
was, nothing will be; everything is, everything has existence and is
present.”

Siddhartha spoke with ecstasy; deeply, this enlightenment had delighted
him. Oh, was not all suffering time, were not all forms of tormenting
oneself and being afraid time, was not everything hard, everything
hostile in the world gone and overcome as soon as one had overcome
time, as soon as time would have been put out of existence by one’s
thoughts? In ecstatic delight, he had spoken, but Vasudeva smiled at
him brightly and nodded in confirmation; silently he nodded, brushed
his hand over Siddhartha’s shoulder, turned back to his work.

And once again, when the river had just increased its flow in the rainy
season and made a powerful noise, then said Siddhartha: “Isn’t it so,
oh friend, the river has many voices, very many voices? Hasn’t it the
voice of a king, and of a warrior, and of a bull, and of a bird of the
night, and of a woman giving birth, and of a sighing man, and a
thousand other voices more?”

“So it is,” Vasudeva nodded, “all voices of the creatures are in its
voice.”

“And do you know,” Siddhartha continued, “what word it speaks, when you
succeed in hearing all of its ten thousand voices at once?”

Happily, Vasudeva’s face was smiling, he bent over to Siddhartha and
spoke the holy Om into his ear. And this had been the very thing which
Siddhartha had also been hearing.
END


// Skylake+ can have 4 generic counters + 3 fixed (cycles, instructions, refcycles)
IntelCounters :: string.[
	"UnhaltedCoreCyclesFixed",
	"InstructionsRetiredFixed",
	"BranchMispredictions",
	"BranchInstructions",
	// on Intel can use L3 cache counters
	"LLCMisses",
	"LLCReference",
];

// AMD Zen can have 6 generic counters
AMDCounters :: string.[
	"TotalCycles",
	"TotalIssues",
	"BranchMispredictions",
	"BranchInstructions",
	// on AMD can use L1 cache counters
	"DcacheMisses",
	"DcacheAccesses",
];

ARMCounters :: string.[
	"TotalCycles",
	"TotalIssues",
	"BranchMispredictions",
	"BranchInstructions",
	"DcacheMisses",
	"DcacheAccesses",
];


#import "Basic";
#import "Windows";
#import "Machine_X64";
#import "meow_hash";

#load "etw.jai";


main :: ()
{
    #assert OS == .WINDOWS "Only Windows supported for now";

    siSysInfo : SYSTEM_INFO;
    GetNativeSystemInfo(*siSysInfo);

    // Choose the counter set to use based on the current CPU/architecture
    counterNames: []string;
    if siSysInfo.wProcessorArchitecture ==
    {
        case 5; #through;   // ARM
        case 12;            // ARM64
            counterNames = ARMCounters;

        case 9;             // x64
            cpu := get_cpu_info();
            if cpu.vendor ==
            {
                case .INTEL;
                    counterNames = IntelCounters;
                case .AMD;
                    counterNames = AMDCounters;
                case;
                    assert( false, "Unsupported architecture" );
            }

        case;
            assert( false, "Unsupported architecture" );
    }

    counters := MapPMCCounters( counterNames );
    log( "Mapped counters:\n" );
    for counters
    {
        log( "%: '%'\n", it.sourceIndex, it.name );
    }


    traceSession: ETWSession;
    if !InitETWSession( counters, *traceSession )
        exit( 1 );


    // Test example of a profiled section
    t0 := seconds_since_init();

    #asm { Hash: vec; }
    // Apparently required by a macro in the meow_hash module
    Len := cast(u64) TestSample.count;

    MeowHash( MeowDefaultSeed, Len, TestSample.data, Hash );
    
    t1 := seconds_since_init();

    print("[single-block] Hash: %-%-%-%, rate: %gbps\n",
        formatInt(MeowU32From(Hash, 3), 16),
        formatInt(MeowU32From(Hash, 2), 16),
        formatInt(MeowU32From(Hash, 1), 16),
        formatInt(MeowU32From(Hash, 0), 16),
        (Len / (t1 - t0)) / (1024 * 1024 * 1024));


    ShutdownETWSession( *traceSession );
}
