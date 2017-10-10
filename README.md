# TerminalExtensions

[![Build Status](https://travis-ci.org/Keno/TerminalExtensions.jl.svg?branch=master)](https://travis-ci.org/Keno/TerminalExtensions.jl)

Adds support for various advanced terminal emulator features. Currently only supports iTerm (since that's what I use),
but if you are using a terminal emulator with a cool advanced feature, let me know of file a pull request.

# Usage

Simply put `atreplinit((_)->Base.require(:TerminalExtensions))` in your `.juliarc.jl` and everything should be detected and configured automatically.
