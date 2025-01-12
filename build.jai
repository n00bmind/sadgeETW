#import "Basic";
#import "Compiler";
#import "System";
#import "String";
#import "Process";

BuildExecutable :: ( src_file: string, globalOptions: Build_Options, release: bool, tgt_name: string )
{
    w := compiler_create_workspace();

    options := globalOptions;
    options.output_type = .EXECUTABLE;
    options.output_executable_name = tgt_name;
    if release
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

    add_build_file( src_file, w );
}

build :: ()
{
    set_build_options_dc( .{do_output=false} );  // No executable for this workspace.

    // The compiler will set the CWD to the directory containing the current file
    path := get_working_directory();
    print( "Working directory for 'build' metaprogram: '%'\n", path );

    globalOptions := get_build_options();
    globalOptions.output_path = "bin";
    globalOptions.intermediate_path = "bin";


    buildRelease := false;
    args := globalOptions.compile_time_command_line;

    // NOTE These arguments have to be specified last, after any arguments for the compiler itself, separated with a hyphen, e.g:
    // jai build.jai - release
    for arg: args
    {
        if arg ==
        {
            case "--release"; #through;
            case "-release"; #through;
            case "release";
                buildRelease = true;
                print( "Building release version.\n" );
        }
    }

    // Test routine
    {
        result := run_command( "nasm", "-f", "win64",
                                "src/pmctrace_test_asm.asm", "-o", "src/pmctrace_test_asm.obj" );

        result = run_command( "lib", "src/pmctrace_test_asm.obj" );
    }

    // Test executables
    BuildExecutable( "src/test.jai", globalOptions, buildRelease, "test" );
    BuildExecutable( "src/test_branching.jai", globalOptions, buildRelease, "test_branching" );

    // Hogger utility
    BuildExecutable( "src/hog.jai", globalOptions, buildRelease, "hog" );
}
#run build();


