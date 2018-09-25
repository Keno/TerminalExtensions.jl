module TerminalExtensions

#
# None of these functions are operating system specific because they
# might be connect via e.g. SSH to a different client operating system
#

import REPL

const DCS = "\eP"
const ST  = "\e\\"

function readDCS(io::IO)
    while bytesavailable(stdin) >= 2
        c1 = read(io,UInt8)
        c1 == 0x90 && return true
        if c1 == UInt8('\e')
            read(io,UInt8) == UInt8('P') && return true
        end
    end
    return false
end


function readST(io::IO)
    c1 = read(io,UInt8)
    c1 == 0x90 && return true
    c1 != UInt8('\e') && return false
    read(io,UInt8) != UInt8('\\') && return false
    return true
end

module iTerm2

    import REPL: display
    import Base64

    struct InlineDisplay <: AbstractDisplay
        io::IO
    end
    InlineDisplay() = InlineDisplay(stdout)

    function set_mark()
        "\033]50;SetMark\007"
    end

    # Runs after interactively edited command but before execution
    function preexec()
        "\033]133;C\007"
    end

    function remotehost_and_currentdir()
        return string("\033]1337;RemoteHost=", ENV["USER"], "@",
                      read(`hostname -f`, String), "\007",
                      "\033]1337;CurrentDir=", pwd(), "\007")
    end

    function prompt_prefix(last_success = true)
        return string("\033]133;D;$(convert(Int, last_success))\007",remotehost_and_currentdir(),"\033]133;A\007")
    end

    function prompt_suffix()
        return "\033]133;B\007"
    end

    function shell_version_number()
        return "\033]1337;ShellIntegrationVersion=1;shell=julia\007"
    end


    function prepare_display_file(io::IO=stdout;filename="Unnamed file", size=nothing, width=nothing, height=nothing, preserveAspectRatio::Bool=true, inline::Bool=false)
        q = "\e]1337;File="
        options = String[]
        filename != "Unnamed file" && push!(options,"name=" * Base64.base64encode(filename))
        size !== nothing && push!(options,"size=" * dec(size))
        height !== nothing && push!(options,"height=" * height)
        width !== nothing && push!(options,"width=" * width)
        preserveAspectRatio !== true && push!(options,"preserveAspectRatio=0")
        inline !== false && push!(options,"inline=1")
        q *= join(options,';')
        q *= ":"
        write(io,q)
    end

    function display_file(data::Vector{UInt8}; io::IO=stdout, kwargs...)
        prepare_display_file(io;kwargs...)
        write(io, Base64.base64encode(data))
        write(io,'\a')
    end

    # Incomplete list. Will be extended as necessity comes up
    const iterm2_mimes = ["image/png", "image/gif", "image/jpeg", "application/pdf", "application/eps"]

    for mime in iterm2_mimes
        @eval begin
            function display(d::InlineDisplay, m::MIME{Symbol($mime)}, x)
                buf = IOBuffer()
                show(Base64.Base64EncodePipe(buf),m,x)
                prepare_display_file(d.io;filename="image",inline=true)
                write(d.io, take!(buf))
                write(d.io,'\a')
            end
        end
    end

    function display(d::InlineDisplay,x)
        for m in iterm2_mimes
            if showable(m,x)
                return display(d,m,x)
            end
        end
        throw(MethodError(display, (d,x)))
    end

end

function __init__()
    if !(isinteractive() && isdefined(Base, :active_repl))
        return
    end
    begin
        term = REPL.Terminals.TTYTerminal("xterm",stdin,stdout,stderr)
        REPL.Terminals.raw!(term,true)
        Base.start_reading(stdin)

        # Detect iTerm support
        print(stdout, "\e[1337n\e[5n")
        readuntil(stdin, "\e")
        itermname = ""
        c = read(stdin, Char)
        c1 = read(stdin, Char)
        if c == '[' && c1 != '0'
            itermname = string(c1, readuntil(stdin, "\e")[1:end-2])
            read(stdin, Char); read(stdin, Char)
        end
        # Read the rest of the \e[5n query
        read(stdin, Char)


        if startswith(itermname, "ITERM2")
            # Inform iTerm of the shell integration version and that we're julia
            write(stdout, iTerm2.shell_version_number())

            pushdisplay(iTerm2.InlineDisplay())
            repl = Base.active_repl

            if !isdefined(repl,:interface)
                repl.interface = REPL.setup_interface(repl)
            end

            let waserror = false
                prefix = repl.interface.modes[1].prompt_prefix
                repl.interface.modes[1].prompt_prefix = function ()
                    (TerminalExtensions.iTerm2.prompt_prefix(waserror) * (isa(prefix,Function) ? prefix() : prefix))
                end
                suffix = repl.interface.modes[1].prompt_suffix
                repl.interface.modes[1].prompt_suffix = function ()
                    ((isa(suffix,Function) ? suffix() : suffix) * TerminalExtensions.iTerm2.prompt_suffix())
                end
                for mode in repl.interface.modes
                    if isdefined(mode,:on_done)
                        of = mode.on_done
                        mode.on_done = function (args...)
                            print(stdout,TerminalExtensions.iTerm2.preexec())
                            of(args...)
                            waserror = repl.waserror
                        end
                    end
                end
            end
        end
    end
end

export iTerm2

end # module
