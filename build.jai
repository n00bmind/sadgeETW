#import "Basic";
#import "Compiler";
#import "System";
#import "String";
#import "Process";

build :: ()
{
    set_build_options_dc( .{do_output=false} );  // No executable for this workspace.

    // The compiler will set the CWD to the directory containing the current file
    path := get_working_directory();
    print( "Working directory for 'build' metaprogram: '%'\n", path );

    global_options := get_build_options();
    global_options.output_path = "bin";
    global_options.intermediate_path = "bin";


    build_release := false;
    args := global_options.compile_time_command_line;

    // NOTE These arguments have to be specified last, after any arguments for the compiler itself, separated with a hyphen, e.g:
    // jai build.jai - release
    for arg: args
    {
        if arg ==
        {
            case "--release"; #through;
            case "-release"; #through;
            case "release";
                build_release = true;
                print( "Building release version.\n" );
        }
    }

    // Test routine
    // TODO Move all this stuff to src/tests/
    {
        result := run_command( "nasm", "-f", "win64",
                                "src/pmctrace_test_asm.asm", "-o", "src/pmctrace_test.obj" );

        result = run_command( "lib", "src/pmctrace_test.obj" );
    }

    // Test executable
    {
        w := compiler_create_workspace();

        options := global_options;
        options.output_type = .EXECUTABLE;
        options.output_executable_name = "test";
        if build_release
        {
            set_optimization( *options, .VERY_OPTIMIZED, true );
            options.backend =.LLVM;
        }
        else
        {
            set_optimization( *options, .DEBUG, true );
            options.backend =.X64;
        }
        set_build_options( options, w );

        add_build_file( "src/test.jai", w );
    }
}
#run build();


