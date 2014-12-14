# SuwaneeForth

by Kristopher Johnson


## Overview

SuwaneeForth is an implementation of a [Forth](http://en.wikipedia.org/wiki/Forth_(programming_language)) interpreter, written in [Swift](https://developer.apple.com/swift/) for OS X.  With a little more work, it could probably run on iOS as well.

SuwaneeForth is a translation/port of the system described in "A sometimes minimal FORTH compiler and tutorial for Linux / i386 systems" (a.k.a. "[JONESFORTH](http://rwmj.wordpress.com/2010/08/07/jonesforth-git-repository/)") by Richard W.M. Jones.  Refer to the JONESFORTH source code for details of the memory layouts and execution mechanisms used by SuwaneeForth.  Like JONESFORTH, SuwaneeForth is not compliant with the [ANS Forth standard](http://forth.sourceforge.net/std/dpans/).  Also like JONESFORTH, SuwaneeForth is released into the public domain.

SuwaneeForth is only intended to be useful as an educational toy.  If you want to use an open-source Forth for serious software development for OS X or iOS, it is recommended that you start with [pForth](http://www.softsynth.com/pforth/), [GForth](https://www.gnu.org/software/gforth/), or another mature Forth implementation.

_Suwanee_ is the name of the city where the author lives.

This Forth implementation is in no way related to [SwiftForth, SwiftX, SwiftOS](http://www.forth.com/swiftforth/) or any other FORTH, Inc. product.  (So if you landed here after doing a web search for "swift forth", take a minute to make sure you are looking at the right Forth.)


## Obtaining the Source Code

The SuwaneeForth repository contains the JONESFORTH source code as a git submodule, so the best way to get everything at once is to do this:

    git clone --recursive https://github.com/kristopherjohnson/suwaneeforth

Alternatively, you can run these commands:

    git clone https://github.com/kristopherjohnson/suwaneeforth
    cd suwaneeforth
    git submodule init
    git submodule update

Note that the JONESFORTH source code is not required for building and running SuwaneeForth, so you could ignore it, but it is very useful to have that code as a documentation reference and it is also useful to have the JONESFORTH unit test data to test SuwaneeForth.


## Description of Contents

- `README.md` - what you are reading now
- `jonesforth/` - the original JONESFORTH source code. You should read `jonesforth.S` and `jonesforth.f` to understand what's going on.
- `forth.xcodeproj` - Xcode project
- `forth.xcworkspace` - Xcode workspace
- `forth/` - the code that implements the SuwaneeForth kernel and system
- `forthTests/` - unit tests for `forth`
- `suwaneeforth/` - source for the `suwaneeforth` command-line tool executable

An additional subdirectory, `build/`, will be created when the `suwaneeforth` executable is built.


## Building SuwaneeForth

Building SuwaneeForth requires the Xcode command-line tools.

To build the application from the command line, execute this command in the top-level directory:

    xcodebuild -target suwaneeforth

If the build succeeds, the `suwaneeforth` executable and `system.forth` will be copied to the `build` subdirectory.

To build the application from within Xcode, do the following:

1. Open Xcode
2. Open `forth.xcworkspace`
3. Select the `suwaneeforth` scheme if it is not already selected
4. Choose the menu item *Product > Build For > Running*
5. If all goes well, the `suwaneeforth` executable and the file `system.forth` will be copied to the `build` directory in your workspace directory.

Note that the Xcode scheme builds the Debug configuration, which is very slow in comparison to the Release configuration.

## Running SuwaneeForth

Like JONESFORTH and many other Forths, the implementation is divided into a small "kernel" written in a low-level language (Swift, in this case) and then the rest of the system is written in Forth itself.  You launch the kernel and load the standard system words before loading your application code or using the interpreter interatively.

The kernel is the `suwaneeforth` executable and the additional Forth-defined words are in `system.forth`.  Running the kernel without `system.forth` is generally not useful, unless you are providing alternative definitions for its contents, so you will usually want to pipe `system.forth` into the kernel before doing anything else.

To run a Forth program, do something like this to load multiple source files into the kernel:

    cat system.forth myprogram.fth | ./suwaneeforth

To run the interpreter interactively, do something like this to pipe the system words and then your input into the kernel:

    cat system.forth - | ./suwaneeforth


## Using the forth Framework

The kernel code, in `forth/kernel.swift`, is in an OS X framework named `forth`. This framework is currently only used by the unit tests, but could be useful to create an application with an embedded Forth interpreter.

Note: The `suwaneeforth` executable currently does not use the framework, because Xcode currently does not provide the tooling needed to build a command-line tool written in Swift that uses a framework written in Swift.  So the `suwaneeforth` target simply compiles and links `kernel.swift` directly.

To build and test the framework, do the following:

1. Open Xcode
2. Open `forth.xcworkspace`
3. Select the `forth` scheme if it is not already selected
4. Choose the menu item *Product > Test*


## Diagnostics

Set the `isTraceEnabled` property in `ForthMachine` to true to enable debug trace message output during execution.

The `ForthMachine` has several safety checks that try to prevent bad Forth code from reading/writing memory outside of the virtual machine's reserved address space.  Run with assertions enabled to enable all these checks, and run in the debugger to break when they are triggered.  Setting a breakpoint in the `abortWithMessage()` method may be helpful too.


## Limitations

SuwaneeForth does not support these words that are included in JONESFORTH:

- Environment words: `ARGC`, `ARGV`, `ENVIRON`
- File-access words: `OPEN-FILE`, `CREATE-FILE`, `CLOSE-FILE`, `READ-FILE`, `PERROR`
- System call words: `GET-BRK`, `BRK`, `MORECORE`, `SYSCALL0`, `SYSCALL1`, `SYSCALL2`, `SYSCALL3`, and the related constants
- Assembler words


## Random Disorganized Thoughts from Kris

Implementing a low-level language in a high-level language is a strange thing to do.  It's not a very productive use of time, but it can be interesting and educational.

I've used Forth before, especially [Quartus Forth](http://www.quartus.net/products/forth/) (now defunct) for [Palm OS](http://en.wikipedia.org/wiki/Palm_OS) (also defunct), but have never implemented my own.  I can't take credit for this implementation, as Mr. Jones did all the hard work in JONESFORTH, but I have a much better understanding of how the internals of a Forth implementation work.

The implementation turned out to be more complicated than I expected. There are more lines of code in my kernel than in the JONESFORTH kernel, which seems strange for a high-level language implementation.  Some of this expansion may be due to my tendency toward over-abstraction, but a lot of it is due to the need to implement a virtual machine rather than just writing x86 code to be executed directly by the CPU.

It's disappointing that the `suwaneeforth` executable is over 4 megabytes in size.  In contrast, `jonesforth` is around 13 kilobytes.  But a "Hello, world!" application in Swift is 3.8 megabytes, so I don't think there is much I can do to reduce the size of the executable.

One struggle I had was figuring out how to implement control flow in the inner interpreter.  In JONESFORTH, this is implemented by having each primitive assembly-language operation end with a _jump-to-the-next-instruction_ macro, but we can't easily implement the same thing in Swift because there is no macro facility, no `goto`, and tail-call optimizations are not guaranteed.  In SuwaneeForth, control flow is implemented by INTERPRET, DOCOL, and EXIT, and it works, but it doesn't feel right.  I may revisit this.  Maybe I could implement a `goto`-like mechanism with `setjmp`/`longjmp`?

As of now, the interpreter uses C standard library calls like `getchar`, `putchar`, `exit`, and `abort` to handle I/O and process termination.  To make the `ForthMachine` useful as an embedded interpreter within an application, there should be some sort of delegate to handle the interface to the host process.  Maybe something like this:

    protocol ForthMachineHost {
        // Get next input character, or return EOF on end of input
        func readChar(forthMachine: ForthMachine) -> FChar

        // Send character to output
        func writeChar(forthMachine: ForthMachine, char: FChar)

        // Called on a normal termination condition (e.g., EOF or BYE)
        func onExit(forthMachine: ForthMachine)

        // Called on an abnormal termination condition
        func onAbort(forthMachine: ForthMachine, errorMessage: String)
    }

    class ForthMachine {
        // ...

        weak var host: ForthMachineHost

        // ...
    }

If I wanted to implement Forth or a Forth-like language in Swift from scratch, I would try to take advantage of Swift's abstraction capabilities and rely less on assembly-style byte-by-byte bit twiddling. For example, a dictionary entry could be defined something like this:

    class FDictionaryEntry {
        var link: FDictionaryEntry
        var name: String
        var isHidden: Bool
        var isImmediate: Bool
        var codeword: FCell
        var data: [FChar]

        // methods ...
    }

and then the dictionary would be a linked list of dictionary entries, rather than a big array of bytes.  This might make it impossible to make it compliant with ANS Forth, and may prohibit some common Forth idioms, but it would be easier to understand and there would be less code to write.

It would be nice to be able to define primitives with a syntax like this (instead of using the `enum` and `switch` and a lot of methods):

    defcode("SWAP") {
        let (x1, x2) = pop2()
        push(x2, x1)
    }

I considered doing this in SuwaneeForth, but making each primitive a full-fledged Swift method made debugging and testing easier.

To make Forth useful for OS X and iOS development, one would want some kind of generic bridge to Objective-C.  I have no idea how to do that, nor any interest in implementing it.
