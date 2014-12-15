/*
    A 32-bit FORTH implementation for OS X and iOS.

    Written by Kristopher Johnson <kris@kristopherjohnson.net>

    This is PUBLIC DOMAIN (see public domain release statement below).


    Based upon "A sometimes minimal FORTH compiler and tutorial for Linux / i386 systems."
    by Richard W.M. Jones <rich@annexia.org>

    See http://rwmj.wordpress.com/2010/08/07/jonesforth-git-repository/ for more
    information about the original JONESFORTH sources.

    The JONESFORTH source repository is mirrored at
    https://github.com/kristopherjohnson/jonesforth


    PUBLIC DOMAIN ----------------------------------------------------------------------

    I, the copyright holder of this work, hereby release it into the public domain. This applies worldwide.

    In case this is not legally possible, I grant any entity the right to use this work for any purpose,
    without any conditions, unless such conditions are required by law.
*/

import Foundation


// MARK: - Pipe-forward

/// Pipe-forward operator
///
/// See http://undefinedvalue.com/2014/07/13/fs-pipe-forward-operator-swift for more information.
///
/// This operator is especially appropriate for implementing FORTH, as it lets us
/// use FORTH-like postfix function application in Swift.

infix operator |> { associativity left }

public func |> <T,U>(lhs: T, rhs: (T) -> U) -> U {
    return rhs(lhs)
}


// MARK: - FORTH data types

/// Each FORTH "cell" is a 32-bit signed integer value
public typealias FCell = Int32

/// The FORTH dictionary is an array of 8-bit bytes
///
/// Bytes are called "characters" in FORTH jargon, so we'll use
/// that terminology, but don't confuse this with Swift
/// Character or with Unicode character encodings.
///
/// We choose an unsigned type because we generally don't need
/// signed 8-bit integer values in this implementation, and we
/// generally won't want sign extension when casting an FChar
/// value to FCell size.
public typealias FChar = UInt8

/// Number of characters in a cell (32 bits / 8 bits)
public let FCharsPerCell = 4

/// An "address" is an index into the dictionary
///
/// Defined as Int so we can avoid typecasts when we use this type
/// as a subscript index or comparison to an index.  Note that 64-bit
/// Int values will be squashed to Int32 when placed in a cell, but
/// that should be OK because all our addresses will fit in 32 bits.
public typealias FAddress = Int

// Converting values between types FCell, FAddress, and FChar is common,
// so define some conversion functions to avoid ugly typecasts.
func asCell(x: FAddress) -> FCell    { return FCell(x) }
func asCell(x: FChar) -> FCell       { return FCell(x) }
func asAddress(x: FCell) -> FAddress { return FAddress(x) }
func asAddress(x: FChar) -> FAddress { return FAddress(x) }
func asChar(x: FCell) -> FChar       { return FChar(x) }
func asChar(x: FAddress) -> FChar    { return FChar(x) }

// Given tuple of two cells, typecast to an (address, count) tuple
func asAddressAndCount(x1: FCell, x2: FCell) -> (FAddress, Int) {
    return (FAddress(x1), Int(x2))
}

/// Convert a boolean value to a FORTH true or false cell value
func asForthFlag(boolValue: Bool) -> FCell {
    return boolValue ? FTrue : FFalse
}


// MARK: - FORTH constants

/// Cell value for a FORTH "true" flag
///
/// Like JONESFORTH, this FORTH uses 1 to represent true, rather than
/// all-bits-set as specified by ANS FORTH.
let FTrue: FCell = 1

/// Cell value for a "false" flag
let FFalse: FCell = 0


/// ASCII code for space character
let Char_Blank = FCell(UnicodeScalar(" ").value)

/// ASCII code for linefeed character ("\n")
let Char_Newline = FCell(UnicodeScalar("\n").value)

/// ASCII code for backslash character ("\")
let Char_Backslash = FCell(UnicodeScalar("\\").value)

/// ASCII code for minus character ("-")
let Char_Minus = FCell(UnicodeScalar("-").value)

/// ASCII code for zero character ("0")
let Char_0 = FCell(UnicodeScalar("0").value)

/// ASCII code for nine character ("9")
let Char_9 = FCell(UnicodeScalar("9").value)

/// ASCII code for capital A ("A")
let Char_A = FCell(UnicodeScalar("A").value)


// MARK: - ForthMachine

/// Implementation of a 32-bit FORTH interpreter
///
/// This implementation is based upon JONESFORTH. See jonesforth.S
/// for details about memory layouts and code execution mechanisms.
///
/// This implementation differs from JONESFORTH in that it does not
/// define primitive operations in assembly language nor take advantage
/// of the native CPU registers to maintain state.  It is a virtual machine
/// with the following features:
///
/// - a large array of bytes for the dictionary and user data space
///
/// - a "data stack"  used for passing parameters between functions
///
/// - a "return stack" used for program nesting, control state, and other purposes
///
/// - a set of register-like properties that maintain indexes into the dictionary, data stack, and return stack
///
/// - a set of primitive operations similar to the assembly-language primitives defined in jonesforth.S
///
/// Aside from the above technical differences, this FORTH is incompatible with
/// JONESFORTH in that the Linux system calls used by JONESFORTH are replaced with
/// calls to C Standard Library functions, and the SYSCALLx words and related
/// constants are not available.  This FORTH also doesn't support the inline
/// assembler defined in jonesforth.f.
///
/// JONESFORTH is not compliant with the ANS FORTH standard, and neither is this FORTH.
///
/// In general, this implementation retains the symbol names used in JONESFORTH.
/// Any symbol with an all-caps name probably has a direct analogue in jonesforth.S
/// or jonesforth.f.

public class ForthMachine {

    // MARK: - Constants and type aliases

    /// Version number
    ///
    /// We use the same version number as the version of JONESFORTH
    /// on which this implementation is based.
    public let JONES_VERSION = 47

    /// Bitmask for Immediate flag in word definition
    let F_IMMED: FCell = 0x80

    /// Bitmask for Hidden flag in word definition
    let F_HIDDEN: FCell = 0x20

    /// Bitmask to get word's name length (bottom five bits)
    let F_LENMASK: FCell = 0x1f

    /// Due to use of bit flags in length field, maximum name length is 31 (0x1f)
    let MaxNameLength = 31

    /// Number of bytes for the buffer used by WORD
    let WordBufferLength = 32


    // MARK: - Nested types

    /// Options passed to ForthMachine constructor
    public struct Options {
        /// Number of bytes reserved for the FORTH dictionary and stack; defaults to 64 Kbytes
        ///
        /// The maximum valid value is Int32.max.
        public var dictionaryCharCount: Int = 64 * 1024

        /// Number of bytes reserved for the return stack; defaults to 4K
        ///
        /// The maximum valid value is Int32.max
        public var returnStackCharCount: Int = 4 * 1024

        /// If true, debug trace information is sent to standard output during execution
        public var isTraceEnabled = false

        /// Generate default options
        public static func defaultOptions() -> Options {
            return Options()
        }
    }

    /// A built-in FORTH variable
    ///
    /// A variable has a cell-aligned address in dictionary dataspace,
    /// and a cell value can be set or read.
    ///
    /// Most variables have a size equal to the size of a cell, but
    /// some are larger (for example, the WORD buffer is managed with
    /// a Variable).
    struct BuiltInVariable {
        /// Reference to the machine that owns this variable
        weak var machine: ForthMachine?

        /// Data-space address of variable's cell(s)
        let address: FAddress

        /// Size of variable's data, in bytes
        let size: Int

        /// Initializer
        init(machine: ForthMachine, address: FAddress, size: Int, initialValue: FCell = 0) {
            self.machine = machine
            self.address = address
            self.size = size
            self.value = initialValue
        }

        /// Get/set value of variable's cell
        ///
        /// Note that this is only legal if size >= FBytesPerCell.
        var value: FCell {
            get             { return machine!.cellAtAddress(address) }
            nonmutating set { machine!.storeToAddress(address, cellValue: newValue) }
        }

        /// Get/set the value of the variable as an Address
        ///
        /// Note that this is only legal if size >= FBytesPerCell.
        var valueAsAddress: FAddress {
            get             { return value |> asAddress }
            nonmutating set { self.value = newValue |> asCell }
        }

        /// Increment the value
        func incrementBy(n: Int) {
            self.value = self.value + n
        }
    }
    

    // MARK: - Virtual machine data regions and registers

    /// Memory for definitions and data space, and the stack
    ///
    /// A "data space address" is an index into this array.
    var dataSpace: [FChar]

    /// Data stack pointer (`%esp` in jonesforth.S)
    ///
    /// This is an index into `dataSpace`. The stack starts at the
    /// top of the data-space region and grows downward.
    /// The initial value is equal to `dataSpace.count`. To push a value
    /// onto the stack, the value of `sp` is decremented and the pushed
    /// value is stored at `dataSpace[sp]`.  To pop a value, `sp` is
    /// incremented.
    ///
    /// It is guaranteed that the value will always be in the range
    /// 0...dataSpace.count. Any attempt to set it outside this range
    /// will cause the program to abort.
    ///
    /// Note that `dataSpace.count` is considered to be a valid value
    /// for `sp`, indicating an empty stack, but attempting to access
    /// `stack[stack.count]` is not a valid operation.
    var sp: FAddress {
        willSet {
            if newValue < 0 {
                onStackOverflow()
            }
            else if newValue > dataSpace.count {
                onStackUnderflow()
            }
        }
    }

    /// The number of cells currently on the data stack
    public var stackCellDepth: Int {
        return (dataSpace.count - sp) / FCharsPerCell
    }

    /// Return stack
    var returnStack: [FChar]

    /// Return stack pointer (`%ebp` in jonesforth.S)
    ///
    /// This is an index into `returnStack`. The stack grows downward.
    /// The initial value is equal to `returnStack.count`. To push a value
    /// onto the stack, the value of `rsp` is decremented and the pushed
    /// value is stored at `returnStack[rsp]`.  To pop a value, `rsp` is
    /// incremented.
    ///
    /// It is guaranteed that the value will always be in the range
    /// 0...returnStack.count. Any attempt to set it outside this range
    /// will cause the program to abort.
    ///
    /// Note that `returnStack.count` is considered to be a valid value
    /// for `rsp`, indicating an empty stack, but attempting to access
    /// `returnStack.count[returnStack.count]` is not a valid operation.
    var rsp: FAddress {
        willSet {
            if newValue < 0 {
                onReturnStackOverflow()
            }
            else if newValue > returnStack.count {
                onReturnStackUnderflow()
            }
        }
    }

    /// The number of cells currently on the return stack
    public var returnStackCellDepth: Int {
        return (returnStack.count - rsp) / FCharsPerCell
    }

    /// Instruction pointer (`%esi` in jonesforth.S)
    ///
    /// This is an index into `dictionary`. It is the index of the first byte of
    /// the next instruction to be executed.
    ///
    /// It is guaranteed that the value will always be in the range
    /// 0...dictionary.count. Any attempt to set it outside this range
    /// will cause the program to abort.
    var ip: FAddress {
        willSet {
            if newValue < 0 {
                onInstructionPointerUnderflow()
            }
            else if newValue > dataSpace.count {
                onInstructionPointerOverflow()
            }
            else if !isCellAlignedAddress(newValue) {
                abortWithMessage("attempt to set instruction pointer to unaligned address")
            }
        }
    }

    /// Code-field-address for the LIT primitive (used when compiling numeric literals)
    var LIT_codeFieldAddress: FAddress = 0

    /// Options passed to init()
    let options: Options


    // MARK: - Built-in FORTH variables

    // Important: Ensure each variable has a unique cell-aligned address,
    // and that the initial value of HERE is beyond any variables.
    //
    // We start reserving space at address 8, so that the cell at address 0 is unused
    // and any attempt to interpret address 0 as a dictionary entry address will fail.
    //
    // These properties are lazily initialized rather than initialized in init()
    // because they each require a reference to an initialized ForthMachine.

    /// FORTH variable "S0" storing the address of the initial value of the data stack pointer
    lazy var s0: BuiltInVariable = BuiltInVariable(
        machine: self,
        address: 8,
        size: FCharsPerCell,
        initialValue: self.dataSpace.count |> asCell)

    /// FORTH variable "STATE" indicating whether interpreter is executing (false) or compiling (true)
    lazy var state: BuiltInVariable = BuiltInVariable(
        machine: self,
        address: self.s0.address + self.s0.size,
        size: FCharsPerCell)

    /// FORTH variable "BASE" containing current base for printing and reading numbers
    lazy var base: BuiltInVariable = BuiltInVariable(
        machine: self,
        address: self.state.address + self.state.size,
        size: FCharsPerCell,
        initialValue: 10)

    /// FORTH variable "LATEST" containing address of most-recently-defined word
    lazy var latest: BuiltInVariable = BuiltInVariable(
        machine: self,
        address: self.base.address + self.base.size,
        size: FCharsPerCell)

    /// Region used by the FORTH word WORD to store its parsed string
    ///
    /// TODO: Instead of using this buffer, consider letting WORD store
    /// a temporary value at HERE like other FORTH implementations do.
    lazy var wordBuffer: BuiltInVariable = BuiltInVariable(
        machine: self,
        address: self.latest.address + self.latest.size,
        size: self.WordBufferLength)

    /// FORTH variable "HERE" indicating current size of dictionary
    lazy var here: BuiltInVariable = BuiltInVariable(
        machine: self,
        address: self.wordBuffer.address + self.WordBufferLength,
        size: FCharsPerCell,
        initialValue: self.wordBuffer.address + self.wordBuffer.size + 4)


    // MARK: - Initialization

    /// Initializer
    public init(options: Options = Options.defaultOptions()) {
        self.options = options

        self.isTraceEnabled = options.isTraceEnabled

        self.dataSpace = Array(
            count:         options.dictionaryCharCount,
            repeatedValue: 0)

        self.sp = self.dataSpace.count

        self.returnStack = Array(
            count:         options.returnStackCharCount,
            repeatedValue: 0)
        self.rsp = self.returnStack.count

        self.ip = 0

        defineBuiltInWords()

        // Cache the code field address for the LIT primitive for use by the compiler
        LIT_codeFieldAddress = codeFieldAddressForEntryWithName("LIT")
        if LIT_codeFieldAddress == 0 {
            abortWithMessage("unable to find LIT in dictionary")
        }
    }

    public func run() {
        // Execute QUIT
        codeFieldAddressForEntryWithName("QUIT") |> executeCodeFieldAddress
    }

    // MARK: - Stack manipulation

    /// Push a cell value onto the data stack
    public final func push(x: FCell) {
        assert(sp % FCharsPerCell == 0, "stack pointer must be cell-aligned for push")

        sp -= FCharsPerCell
        let pointer = UnsafeMutablePointer<FCell>(mutablePointerForDataAddress(sp))
        pointer.memory = x
    }

    /// Return the value of the cell at the given depth in the data stack.
    ///
    /// The value at depth 0 is the top-of-stack value; the
    /// value at depth 1 is the value just beneath the top-of-stack,
    /// and so on.
    ///
    /// Results are indeterminate if the value of `depth` is not in the
    /// range `0..<stackCellDepth`.
    public final func pick(depth: Int) -> FCell {
        assert(sp % FCharsPerCell == 0, "stack pointer must be cell-aligned for pick")

        let address = sp + (depth * FCharsPerCell)
        let pointer = UnsafePointer<FCell>(immutablePointerForDataAddress(address))
        return pointer.memory
    }

    /// Drop the specified number of values from the data stack
    public final func dropCells(count: Int) {
        sp += count * FCharsPerCell
    }

    /// Pop a value from the data stack
    public final func pop() -> FCell {
        let result = pick(0)
        dropCells(1)
        return result
    }
    
    /// Push two values onto the stack
    public final func push(x1: FCell, _ x2: FCell) {
        push(x1); push(x2)
    }

    /// Push three values onto the stack
    public final func push(x1: FCell, _ x2: FCell, _ x3: FCell) {
        push(x1); push(x2); push(x3)
    }

    /// Push four values onto the stack
    public final func push(x1: FCell, _ x2: FCell, _ x3: FCell, _ x4: FCell) {
        push(x1); push(x2); push(x3); push(x4)
    }

    /// Return the value that is at the top of the data stack
    public final func top() -> FCell {
        return pick(0)
    }

    /// Return top two values from the parameter stack
    public final func top2() -> (FCell, FCell) {
        return (pick(1), pick(0))
    }

    /// Return top two values from the parameter stack
    public final func top3() -> (FCell, FCell, FCell) {
        return (pick(2), pick(1), pick(0))
    }

    /// Return top two values from the parameter stack
    public final func top4() -> (FCell, FCell, FCell, FCell) {
        return (pick(3), pick(2), pick(1), pick(0))
    }

    /// Pop two values from the parameter stack
    public final func pop2() -> (FCell, FCell) {
        let (x1, x2) = top2()
        dropCells(2)
        return (x1, x2)
    }

    /// Pop three values from the parameter stack
    public final func pop3() -> (FCell, FCell, FCell) {
        let (x1, x2, x3) = top3()
        dropCells(3)
        return (x1, x2, x3)
    }

    /// Pop four values from the parameter stack
    public final func pop4() -> (FCell, FCell, FCell, FCell) {
        let (x1, x2, x3, x4) = top4()
        dropCells(4)
        return (x1, x2, x3, x4)
    }

    /// Called on any attempt to set `sp` to a value less than zero
    public func onStackOverflow() {
        assert(false, "stack overflow")
        abortWithMessage("stack overflow")
    }

    /// Called on any attempt to set `sp` to a value greater than `stack.count`
    public func onStackUnderflow() {
        assert(false, "stack underflow")
        abortWithMessage("stack underflow")
    }


    // MARK: - Return stack manipulation

    /// Return a pointer to the byte at a specified return stack address
    final func immutablePointerForReturnStackAddress(address: FAddress) -> UnsafePointer<FChar> {
        return UnsafePointer<FChar>(returnStack) + address
    }

    /// Return a pointer to the byte at a specified return stack address
    final func mutablePointerForReturnStackAddress(address: FAddress) -> UnsafeMutablePointer<FChar> {
        return UnsafeMutablePointer<FChar>(returnStack) + address
    }

    /// Push a cell value onto the return stack
    public final func pushReturn(x: FCell) {
        assert(rsp % FCharsPerCell == 0, "return stack pointer must be cell-aligned for pushReturn")

        rsp -= FCharsPerCell
        let pointer = UnsafeMutablePointer<FCell>(mutablePointerForReturnStackAddress(rsp))
        pointer.memory = x
    }

    /// Return the value of the cell at the given depth in the return stack.
    ///
    /// The value at depth 0 is the top-of-stack value; the
    /// value at depth 1 is the value just beneath the top-of-stack,
    /// and so on.
    ///
    /// Results are indeterminate if the value of `depth` is not in the
    /// range `0..<returnStackCellDepth`.
    public final func pickReturn(depth: Int) -> FCell {
        assert(rsp % FCharsPerCell == 0, "return stack pointer must be cell-aligned for pickReturn")

        let address = rsp + (depth * FCharsPerCell)
        let pointer = UnsafePointer<FCell>(immutablePointerForReturnStackAddress(address))
        return pointer.memory
    }

    /// Drop the specified number of values from the return stack
    public final func dropReturnCells(count: Int) {
        rsp += count * FCharsPerCell
    }

    /// Pop a value from the return stack
    public final func popReturn() -> FCell {
        let result = pickReturn(0)
        dropReturnCells(1)
        return result
    }
    
    /// Called on an attempt to set `rsp` to a value less than zero
    public func onReturnStackOverflow() {
        assert(false, "return stack overflow")
        abortWithMessage("return stack overflow")
    }

    /// Called on an attempt to set `rsp` to a value greater than `returnStack.count`
    public func onReturnStackUnderflow() {
        assert(false, "return stack underflow")
        abortWithMessage("return stack underflow")
    }

    /// Drop all items from the return stack
    final func resetReturnStack() {
        rsp = returnStack.count
    }

    
    // MARK: - Data-space operations

    /// Return a pointer to the byte at a specified data-space address
    final func immutablePointerForDataAddress(address: FAddress) -> UnsafePointer<FChar> {
        return UnsafePointer<FChar>(dataSpace) + address
    }

    /// Return a pointer to the byte at a specified data-space address
    final func mutablePointerForDataAddress(address: FAddress) -> UnsafeMutablePointer<FChar> {
        return UnsafeMutablePointer<FChar>(dataSpace) + address
    }

    /// Called on attempt to read from an invalid data-space address
    final func onIllegalAddressFetch() {
        assert(false, "attempt to read outside of data space")
        abortWithMessage("attempt to read outside of data space")
    }

    /// Called on attempt to write to an invalid data-space address
    final func onIllegalAddressStore() {
        assert(false, "attempt to write outside of data space")
        abortWithMessage("attempt to write outside of data space")
    }

    /// Return the 32-bit integer value at the specified data-space address
    ///
    /// This is public so that unit tests and debuggers can read the data
    /// space.  Applications should use the standard FORTH memory access
    /// words.
    public final func cellAtAddress(address: FAddress) -> FCell {
        if (0 <= address) && (address <= dataSpace.count - FCharsPerCell) {
            // Reading a cell from an unaligned address will actually work fine,
            // but it is a violation of the rules and probably indicates a
            // bug somewhere.
            if !isCellAlignedAddress(address) {
                assert(false, "cell accesses must use aligned addresses")
                abortWithMessage("unaligned cell access")
            }

            let pointer = UnsafePointer<FCell>(immutablePointerForDataAddress(address))
            let cell = pointer.memory
            return cell
        }
        else {
            onIllegalAddressFetch()
            return 0
        }
    }

    /// Return the byte value at the specified data-space address
    ///
    /// This is public so that unit tests and debuggers can read the data
    /// space.  Applications should use the standard FORTH memory access
    /// words.
    final func charAtAddress(address: FAddress) -> FChar {
        if 0 <= address && address < dataSpace.count {
            let pointer = UnsafePointer<FChar>(immutablePointerForDataAddress(address))
            let cell = pointer.memory
            return cell
        }
        else {
            onIllegalAddressFetch()
            return 0
        }
    }

    /// Create a null-terminated array of CChar using the specified bytes
    final func CStringAtAddress(address: FAddress, length: Int) -> [CChar] {
        var result = Array<CChar>(count: length + 1, repeatedValue: 0)
        for i in 0..<length {
            result[i] = CChar(charAtAddress(address + i))
        }
        return result
    }

    /// Convert a FORTH string to a Swift String
    final func stringAtAddress(address: FAddress, length: Int) -> String? {
        return String.fromCString(CStringAtAddress(address, length: length))
    }

    final func storeToAddress(address: FAddress, cellValue: FCell) {
        if 0 <= address && address <= (dataSpace.count - 4) {
            let pointer = UnsafeMutablePointer<FCell>(mutablePointerForDataAddress(address))
            pointer.memory = cellValue
        }
        else {
            onIllegalAddressStore()
        }
    }

    final func storeToAddress(address: FAddress, charValue: FChar) {
        if 0 <= address && address < dataSpace.count {
            let pointer = UnsafeMutablePointer<FChar>(mutablePointerForDataAddress(address))
            pointer.memory = charValue
        }
        else {
            onIllegalAddressStore()
        }
    }

    // Curried form of storeToAddress(, charValue:)
    final func storeCharToAddress(address: FAddress)(char: FChar) {
        storeToAddress(address, charValue: char)
    }

    // Curried form of storeToAddress(, cellValue:)
    final func storeCellToAddress(address: FAddress)(cell: FCell) {
        storeToAddress(address, cellValue: cell)
    }

    /// Store a cell to HERE, and increment HERE by the size of a cell
    final func addCellHere(cellValue: FCell) {
        storeToAddress(here.valueAsAddress, cellValue: cellValue)
        here.incrementBy(FCharsPerCell)
    }

    /// Store a cell to HERE, and increment HERE by the size of a cell
    final func addCellHere(intValue: Int) {
        assert(intValue >= Int(FCell.min))
        assert(intValue <= Int(FCell.max))
        addCellHere(FCell(intValue))
    }

    /// Store a byte to HERE, and increment HERE by 1
    final func addCharHere(charValue: FChar) {
        storeToAddress(here.valueAsAddress, charValue: charValue)
        here.incrementBy(1)
    }

    /// Add name to dictionary at HERE
    ///
    /// First puts the name's length into the dictionary, followed
    /// by the characters of the name.
    ///
    /// If length is greater than 31, it will be truncated to 31
    final func addLengthAndNameHere(nameAddress: FAddress, length: Int) {
        let validLength = min(length, MaxNameLength)
        addCharHere(FChar(validLength))
        for i in 0..<validLength {
            addCharHere(charAtAddress(nameAddress + i))
        }
    }

    /// Add String name to dictionary
    ///
    /// First puts the string's length into the dictionary, followed
    /// by the characters of the string's UTF8 encoding.
    ///
    /// If the name's length is greater than 31, it will be truncated
    /// to 31 bytes.
    final func addLengthAndNameHere(name: String, flags: FCell) {
        let characters = Array(name.utf8)
        let validLength = min(characters.count, MaxNameLength)
        addCharHere(FChar(validLength) | FChar(flags))
        for i in 0..<validLength {
            addCharHere(characters[i])
        }
    }

    /// Given an address, return address on a cell boundary
    final func alignedCellAddress(address: FAddress) -> FAddress {
        return (address + 3) & ~0x03
    }

    /// Determine whether a given address is aligned on a cell boundary
    final func isCellAlignedAddress(address: FAddress) -> Bool {
        return (address % FCharsPerCell) == 0
    }

    /// Cell-align the address contained in the HERE variable
    final func alignHere() {
        here.valueAsAddress = alignedCellAddress(here.valueAsAddress)
    }

    // As with JONESFORTH, a dictionary entry has this variable-length structure:
    //
    // - link field         (1 cell/4 chars)
    // - length/flags field (1 char)
    // - name               (1 char per character in name)
    // - padding            (if necessary, pad to cell-aligned address)
    // - codeword           (1 cell/4 chars)
    // - data               (additional cells as needed)
    // 
    // All dictionary entries start on a cell-aligned address.

    /// Create a new dictionary entry header for the specified name
    ///
    /// When this method completes, HERE will point to the codeword field.
    func createEntryForNameAtAddress(address: FAddress, length: Int) {
        alignHere()

        // Link
        let start = here.valueAsAddress
        addCellHere(latest.value)
        latest.valueAsAddress = start

        // Length and name
        addLengthAndNameHere(address, length: length)

        alignHere()
    }

    /// Add definition of specified primitive operation to the dictionary
    func defcode(name: String, _ primitive: Primitive, flags: FCell = 0) {
        // Register name for tracing purposes
        let opcode = primitive.rawValue
        if opcode != Primitive.DOCOL.rawValue {
            _nameForOpcode[opcode] = name
        }

        alignHere()

        // Link
        let start = here.valueAsAddress
        addCellHere(latest.value)
        latest.valueAsAddress = start

        // Length and name
        addLengthAndNameHere(name, flags: flags)

        // code field
        alignHere()
        trace("\(name)\t\(opcode)\t\(start)\t\(here.valueAsAddress)") // NAME OPCODE LINK CFA
        FCell(primitive.rawValue) |> addCellHere
    }

    /// Add a word definition consisting of calls to other words to the dictionary
    ///
    /// Creates a dictionary header with DOCOL as the codeword, then
    /// appends the code field addresses of the specified words.
    ///
    /// In general, the final word in the definition should be "EXIT".
    func defword(name: String, _ words: [String], flags: FCell = 0) {
        defcode(name, .DOCOL, flags: flags)
        defwordContinue(words)
    }

    /// Continue a word definition started by defword()
    func defwordContinue(words: [String]) {
        for word in words {
            let cfa = codeFieldAddressForEntryWithName(word)
            if cfa == 0 {
                abortWithMessage("unable to find predefined word with name \"\(word)\"")
            }
            addCellHere(cfa)
        }
    }

    /// Move the instruction pointer to the next cell
    final func advanceInstructionPointer() {
        //trace("advanceInstructionPointer from \(ip) to \(ip+FCharsPerCell)")
        ip += FCharsPerCell
    }

    /// Called on any attempt to set `ip` to a value less than zero
    public func onInstructionPointerUnderflow() {
        assert(false, "instruction pointer underflow")
        abortWithMessage("instruction pointer underflow")
    }

    /// Called on any attempt to set `ip` to a value greater than `dictionary.count`
    public func onInstructionPointerOverflow() {
        assert(false, "instruction pointer overflow")
        abortWithMessage("instruction pointer overflow")
    }


    // MARK: - Input/output and other system-level operations

    /// Low-level I/O function that reads a byte from the input stream.
    final func readChar() -> FCell {
        return getchar()
    }

    /// Low-level I/O function that puts a byte back on the input stream
    ///
    /// The character will be returned by the next call to readChar().
    final func unreadChar(c: FCell) {
        ungetc(c, stdin)
    }

    /// Low-level I/O function that writes a byte to output stream
    final func writeChar(c: FCell) {
        putchar(c)
        fflush(stdout)
    }

    /// Low-level I/O function that writes a byte to output stream
    final func writeChar(c: FChar) {
        writeChar(FCell(c))
    }

    /// Called if KEY encounters an end-of-file or error condition.
    func onKeyEOF() {
        trace("KEY: end of input")
        exit(EXIT_SUCCESS)
    }

    /// Called if WORD encounters an end-of-file or error condition.
    func onWordEOF() {
        trace("WORD: end of input")
        exit(EXIT_SUCCESS)
    }

    /// Send the specified message to the error stream and exit the program
    public func abortWithMessage(message: String) {
        fputs("abort: \(message)\n", stderr)
        abort()
    }

    /// Read next blank-delimited word from input, returning address and length.
    ///
    /// "Blanks" are any characters with ASCII code of space or lower.  This
    /// includes linefeeds, tabs, and other control characters.
    ///
    /// A backslash (\) character starts a comment that extends to the end of the line.
    final func readWord() -> (FCell, FCell) {

        func skipBlanksAndComments() {

            func skipToEndOfLine() {
                var ch = self.readChar()
                while ch != EOF && ch != FCell(Char_Newline) {
                    ch = self.readChar()
                }

                if ch == EOF {
                    onWordEOF()
                }
            }

            var done = false
            var ch = readChar()
            while !done {
                if ch == FCell(Char_Backslash) {
                    // start of comment
                    skipToEndOfLine()
                    ch = readChar()
                }
                else if ch <= FCell(Char_Blank) {
                    // next character
                    ch = readChar()
                }
                else {
                    done = true
                }
            }
            unreadChar(ch)
        }

        skipBlanksAndComments()

        let buffer = wordBuffer.address
        var count = 0
        var ch = readChar()
        if ch == EOF {
            onWordEOF()
            return (0, 0)
        }
        while ch != EOF && ch > FCell(Char_Blank) {
            if count == WordBufferLength {
                abortWithMessage("WORD buffer overflow")
            }

            FChar(ch) |> storeCharToAddress(buffer + count)
            ++count
            ch = readChar()
        }

        trace("WORD: \"\(stringAtAddress(buffer, length: count)!)\"")
        return (FCell(buffer), FCell(count))
    }

    /// Place a string in the WORD buffer, and push its address and length to the stack
    ///
    /// This method is used by unit tests to simulate reading of a word.
    public final func setWord(s: String) {
        let chars: [FChar] = Array(s.utf8)
        assert(chars.count <= WordBufferLength)
        for i in 0..<chars.count {
            chars[i] |> storeCharToAddress(wordBuffer.address + i)
        }
        push(FCell(wordBuffer.address), FCell(chars.count))
    }


    /// Try to parse the given string as a number.
    ///
    /// Returns the parsed number and count of unparsed characters.
    /// A count other than zero indicates failure.
    final func numberAtAddress(address: FAddress, length: Int) -> (Int, Int) {
        // Empty string
        if length == 0 {
            return (0, 0)
        }

        let numericBase = Int(base.value)

        var isNegative = false
        var number = 0
        var i = 0

        // If it starts with "-", it's negative
        let firstChar = charAtAddress(address) |> asCell
        if firstChar == Char_Minus {
            isNegative = true
            ++i
            if i >= length {
                // string is only "-"
                return (0, 1)
            }
        }

        // Parse digits
        var unparseable = false
        while !unparseable && i < length {
            number = number * numericBase
            let c = charAtAddress(address + i) |> asCell
            ++i
            if Char_0 <= c && c <= Char_9 {
                let val = Int(c - Char_0)
                if val < numericBase {
                    number = number &+ val
                }
                else {
                    unparseable = true
                }
            }
            else if Char_A <= c {
                let val = Int(c - Char_A + 10)
                if val < numericBase {
                    number = number &+ val
                }
                else {
                    unparseable = true
                }
            }
            else {
                unparseable = true
            }
        }

        return (number, length - i)
    }
    

    // MARK: - Interpreter

    /// Primitive machine operations
    ///
    /// In JONESFORTH, the codeword field of each primitive word is the address
    /// of an assembly-language subroutine.  In Swift, there is no practical way
    /// to get the address of a method and represent it in a 32-bit cell, so instead
    /// each of our primitive words will be a numeric "opcode" that identifies
    /// the method to be called to perform the primitive operation.
    ///
    /// The general pattern for defining a primitive operation is to do the following:
    ///
    /// 1. Add a case to this enum.
    /// 2. Add a case to the switch in `execute()`.
    /// 3. If the primitive is user-callable, add something appropriate to `addBuiltinsToDictionary()`.

    public enum Primitive: Int {
        case UNDEFINED_PRIMITIVE    // = 0

        case DOCOL
        case EXIT

        case DROP
        case SWAP
        case DUP
        case OVER
        case ROT
        case NROT
        case TWODROP
        case TWODUP
        case TWOSWAP
        case QDUP

        case INCR
        case DECR
        case INCR4
        case DECR4
        case ADD
        case SUB
        case MUL
        case DIVMOD

        case EQU
        case NEQU
        case LT
        case GT
        case LE
        case GE
        case ZEQU
        case ZNEQU
        case ZLT
        case ZGT
        case ZLE
        case ZGE

        case AND
        case OR
        case XOR
        case INVERT

        case LIT

        case STORE
        case FETCH
        case ADDSTORE
        case SUBSTORE
        case STOREBYTE
        case FETCHBYTE
        case CCOPY
        case CMOVE

        case STATE
        case LATEST
        case HERE
        case SZ
        case BASE

        case VERSION
        case RZ
        case __DOCOL
        case __F_IMMED
        case __F_HIDDEN
        case __F_LENMASK

        case TOR
        case FROMR
        case RSPFETCH
        case RSPSTORE
        case RDROP

        case DSPFETCH
        case DSPSTORE

        case KEY
        case EMIT
        case WORD
        case NUMBER

        case FIND
        case TCFA
        case CREATE
        case COMMA
        case LBRAC
        case RBRAC
        case IMMEDIATE
        case HIDDEN
        case TICK
        case BRANCH
        case ZBRANCH
        case LITSTRING
        case TELL
        case INTERPRET
        case CHAR
        case EXECUTE

        case BYE
        case UNUSED
    }

    /// Run the code at the specified code field address
    public func executeCodeFieldAddress(codeFieldAddress: FAddress) {
        let codeword = cellAtAddress(codeFieldAddress)
        executeCodeWord(codeword, codeFieldAddress: codeFieldAddress)
    }

    /// Run the primitive code associated with a codeword
    public func executeCodeWord(codeword: FCell, codeFieldAddress: FAddress) {
        
        trace("execute(\(nameForOpcode(Int(codeword))) @ \(codeFieldAddress))")

        if let primitive = Primitive(rawValue: Int(codeword)) {

            switch primitive {

            case .UNDEFINED_PRIMITIVE:
                // If we hit this, we're trying to interpret 0 as an opcode,
                // so we're probably executing code from uninitialized
                // memory.
                assert(false, "uninitialized opcode")
                abortWithMessage("uninitialized opcode")
                break

            case .DOCOL:        DOCOL(codeFieldAddress)
            case .EXIT:         EXIT()
            case .DROP:         DROP()
            case .SWAP:         SWAP()
            case .DUP:          DUP()
            case .OVER:         OVER()
            case .ROT:          ROT()
            case .NROT:         NROT()
            case .TWODROP:      TWODROP()
            case .TWODUP:       TWODUP()
            case .TWOSWAP:      TWOSWAP()
            case .QDUP:         QDUP()

            case .INCR:         INCR()
            case .DECR:         DECR()
            case .INCR4:        INCR4()
            case .DECR4:        DECR4()
            case .ADD:          ADD()
            case .SUB:          SUB()
            case .MUL:          MUL()
            case .DIVMOD:       DIVMOD()

            case .EQU:          EQU()
            case .NEQU:         NEQU()
            case .LT:           LT()
            case .GT:           GT()
            case .LE:           LE()
            case .GE:           GE()
            case .ZEQU:         ZEQU()
            case .ZNEQU:        ZNEQU()
            case .ZLT:          ZLT()
            case .ZGT:          ZGT()
            case .ZLE:          ZLE()
            case .ZGE:          ZGE()

            case .AND:          AND()
            case .OR:           OR()
            case .XOR:          XOR()
            case .INVERT:       INVERT()

            case .LIT:          LIT()

            case .STORE:        STORE()
            case .FETCH:        FETCH()
            case .ADDSTORE:     ADDSTORE()
            case .SUBSTORE:     SUBSTORE()
            case .STOREBYTE:    STOREBYTE()
            case .FETCHBYTE:    FETCHBYTE()
            case .CCOPY:        CCOPY()
            case .CMOVE:        CMOVE()

            case .STATE:        STATE()
            case .LATEST:       LATEST()
            case .HERE:         HERE()
            case .SZ:           SZ()
            case .BASE:         BASE()

            case .VERSION:      VERSION()
            case .RZ:           RZ()
            case .__DOCOL:      __DOCOL()
            case .__F_IMMED:    __F_IMMED()
            case .__F_HIDDEN:   __F_HIDDEN()
            case .__F_LENMASK:  __F_LENMASK()

            case .TOR:          TOR()
            case .FROMR:        FROMR()
            case .RSPFETCH:     RSPFETCH()
            case .RSPSTORE:     RSPSTORE()
            case .RDROP:        RDROP()

            case .DSPFETCH:     DSPFETCH()
            case .DSPSTORE:     DSPSTORE()

            case .KEY:          KEY()
            case .EMIT:         EMIT()
            case .WORD:         WORD()
            case .NUMBER:       NUMBER()

            case .FIND:         FIND()
            case .TCFA:         TCFA()
            case .CREATE:       CREATE()
            case .COMMA:        COMMA()
            case .LBRAC:        LBRAC()
            case .RBRAC:        RBRAC()
            case .IMMEDIATE:    IMMEDIATE()
            case .HIDDEN:       HIDDEN()
            case .TICK:         TICK()
            case .BRANCH:       BRANCH()
            case .ZBRANCH:      ZBRANCH()
            case .LITSTRING:    LITSTRING()
            case .TELL:         TELL()
            case .INTERPRET:    INTERPRET()
            case .CHAR:         CHAR()
            case .EXECUTE:      EXECUTE()

            case .BYE:          BYE()
            case .UNUSED:       UNUSED()
            }
        }
        else {
            executeUndefinedCodeword(codeword)
        }
    }

    /// Create predefined word definitions
    ///
    /// This includes primitive operations and words built from primitives
    func defineBuiltInWords() {
        defcode("EXIT",       .EXIT)

        defcode("DROP",       .DROP)
        defcode("SWAP",       .SWAP)
        defcode("DUP",        .DUP)
        defcode("OVER",       .OVER)
        defcode("ROT",        .ROT)
        defcode("-ROT",       .NROT)
        defcode("2DROP",      .TWODROP)
        defcode("2DUP",       .TWODUP)
        defcode("2SWAP",      .TWOSWAP)
        defcode("?DUP",       .QDUP)

        defcode("1+",         .INCR)
        defcode("1-",         .DECR)
        defcode("4+",         .INCR4)
        defcode("4-",         .DECR4)
        defcode("+",          .ADD)
        defcode("-",          .SUB)
        defcode("*",          .MUL)
        defcode("/MOD",       .DIVMOD)

        defcode("=",          .EQU)
        defcode("<>",         .NEQU)
        defcode("<",          .LT)
        defcode(">",          .GT)
        defcode("<=",         .LE)
        defcode(">=",         .GE)
        defcode("0=",         .ZEQU)
        defcode("0<>",        .ZNEQU)
        defcode("0<",         .ZLT)
        defcode("0>",         .ZGT)
        defcode("0<=",        .ZLE)
        defcode("0>=",        .ZGE)

        defcode("AND",        .AND)
        defcode("OR",         .OR)
        defcode("XOR",        .XOR)
        defcode("INVERT",     .INVERT)

        defcode("LIT",        .LIT)

        defcode("!",          .STORE)
        defcode("@",          .FETCH)
        defcode("+!",         .ADDSTORE)
        defcode("-!",         .SUBSTORE)
        defcode("C!",         .STOREBYTE)
        defcode("C@",         .FETCHBYTE)
        defcode("CMOVE",      .CMOVE)

        defcode("STATE",      .STATE)
        defcode("HERE",       .HERE)
        defcode("LATEST",     .LATEST)
        defcode("S0",         .SZ)
        defcode("BASE",       .BASE)

        defcode("VERSION",    .VERSION)
        defcode("R0",         .RZ)
        defcode("DOCOL",      .__DOCOL)
        defcode("F_IMMED",    .__F_IMMED)
        defcode("F_HIDDEN",   .__F_HIDDEN)
        defcode("F_LENMASK",  .__F_LENMASK)

        defcode(">R",         .TOR)
        defcode("R>",         .FROMR)
        defcode("RSP@",       .RSPFETCH)
        defcode("RSP!",       .RSPSTORE)
        defcode("RDROP",      .RDROP)

        defcode("DSP@",       .DSPFETCH)
        defcode("DSP!",       .DSPSTORE)

        defcode("KEY",        .KEY)
        defcode("EMIT",       .EMIT)
        defcode("WORD",       .WORD)
        defcode("NUMBER",     .NUMBER)

        defcode("FIND",       .FIND)
        defcode(">CFA",       .TCFA)

        defcode("CREATE",     .CREATE)
        defcode(",",          .COMMA)
        defcode("[",          .LBRAC, flags: F_IMMED)
        defcode("]",          .RBRAC)
        defcode("IMMEDIATE",  .IMMEDIATE, flags: F_IMMED)
        defcode("HIDDEN",     .HIDDEN)
        defcode("'",          .TICK)
        defcode("BRANCH",     .BRANCH)
        defcode("0BRANCH",    .ZBRANCH)
        defcode("LITSTRING",  .LITSTRING)
        defcode("TELL",       .TELL)
        defcode("INTERPRET",  .INTERPRET)
        defcode("CHAR",       .CHAR)
        defcode("EXECUTE",    .EXECUTE)

        defcode("BYE",        .BYE)
        defcode("UNUSED",     .UNUSED)

        // Start a definition
        defword(":", [
            "WORD",
            "CREATE",
            "LIT"
        ])
        Primitive.DOCOL.rawValue |> addCellHere
        defwordContinue([
            ",",
            "LATEST", "@", "HIDDEN",
            "]",
            "EXIT"
        ])

        // End a definition
        defword(";", [
            "LIT", "EXIT", ",",
            "LATEST", "@", "HIDDEN",
            "[",
            "EXIT"
        ], flags: F_IMMED)

        // Given address of dictionary entry, give address of data field
        //
        // >DFA ( a-addr1 -- a-addr2 )
        defword(">DFA", [
            ">CFA", "4+",
            "EXIT"
        ])

        // Toggle the F_HIDDEN bit of specified word
        //
        // HIDE ( "<spaces>name" -- )
        defword("HIDE", [
            "WORD", "FIND", "HIDDEN",
            "EXIT"
        ])

        // Clear the return stack and enter interpretation loop
        //
        // QUIT ( -- )
        defword("QUIT", [
            "R0", "RSP!",
            "INTERPRET",
            "BRANCH"
        ])
        (-8) |> addCellHere  // BRANCH argument, jumps back to INTERPRET
    }

    /// Called by `execute()` for an undefined codeword value.
    final func executeUndefinedCodeword(codeword: FCell) {
        assert(false, "\(codeword) is not a valid codeword")
    }

    /// Execute a non-primitive definition
    ///
    /// Pushes the current instruction pointer value to the return stack,
    /// then sets the instruction pointer to point to the cell following the
    /// one that refers to the DOCOL codeword.
    ///
    /// Execute instructions until EXIT
    func DOCOL(codeFieldAddress: FAddress) {
        trace("DOCOL: \(nameForCodeFieldAddress(codeFieldAddress)); return=\(ip)")

        pushReturn(FCell(ip))

        ip = codeFieldAddress + FCharsPerCell

        var exit = false
        while !exit {
            let addressAtIP = cellAtAddress(ip) |> asAddress
            let codeword = cellAtAddress(addressAtIP)

            advanceInstructionPointer()
            executeCodeWord(codeword, codeFieldAddress: addressAtIP)

            if codeword == FCell(Primitive.EXIT.rawValue) {
                exit = true
            }
        }
    }

    /// Return control to the calling definition
    ///
    /// EXIT ( -- ) ( R: nest-sys -- )
    public func EXIT() {
        ip = popReturn() |> asAddress
    }

    /// Find dictionary word entry matching string at (address, length)
    ///
    /// Returns 0 if not found, or nonzero data-space address if found.
    func find(address: FAddress, _ length: Int) -> FAddress {
        var link = latest.valueAsAddress

        while link != 0 {
            // The length field could include bitflags F_HIDDEN and F_IMMEDIATE.
            // We only match if the length portion is equal and F_HIDDEN is not set.
            let lengthFieldAddress = link + FCharsPerCell
            let nameFieldAddress = link + FCharsPerCell + 1
            let lengthFieldValue = charAtAddress(lengthFieldAddress) |> asCell
            if lengthFieldValue & (F_HIDDEN | F_LENMASK) == FCell(length) {
                if areEqualStringsOfLength(length, address, nameFieldAddress) {
                    return link
                }
            }

            // Go to next link
            link = cellAtAddress(link) |> asAddress
        }

        return 0
    }

    /// Find dictionary word entry
    ///
    /// This performs the same operation as `find()`, but lets us specify
    /// a Swift String rather than requiring the name to be in the
    /// FORTH data space.
    ///
    /// Returns 0 if not found, or nonzero data-space address if found.
    func findEntryWithName(name: String) -> FAddress {
        // Convert name to array of FChar
        let chars: [FChar] = Array(name.utf8)
        let length = chars.count

        var link = latest.valueAsAddress

        while link != 0 {
            // The length field could include bitflags F_HIDDEN and F_IMMEDIATE.
            // We only match if the length portion is equal and F_HIDDEN is not set.
            let lengthFieldAddress = link + FCharsPerCell
            let nameFieldAddress = link + FCharsPerCell + 1
            let lengthFieldValue = charAtAddress(lengthFieldAddress) |> asCell
            if lengthFieldValue & (F_HIDDEN | F_LENMASK) == FCell(length) {
                let namePointer = immutablePointerForDataAddress(nameFieldAddress)
                if memcmp(chars, namePointer, UInt(length)) == 0 {
                    return link
                }
            }

            // Go to next link
            link = FAddress(cellAtAddress(link))
        }
        
        return 0
    }

    /// Determine whether strings at specified address have identical contents
    func areEqualStringsOfLength(length: Int, _ s1: FAddress, _ s2: FAddress) -> Bool {
        for i in 0..<length {
            if charAtAddress(s1 + i) != charAtAddress(s2 + i) {
                return false
            }
        }
        return true
    }

    /// Get the address of the code field (CFA) for the dictionary entry that starts at the specified address
    public final func lengthAndFlagsFieldAddressForEntryAtAddress(entryAddress: FAddress) -> FAddress {
        return entryAddress + FCharsPerCell
    }

    /// Get the address of the code field (CFA) for the dictionary entry that starts at the specified address
    public final func nameFieldAddressForEntryAtAddress(entryAddress: FAddress) -> FAddress {
        return lengthAndFlagsFieldAddressForEntryAtAddress(entryAddress) + 1
    }

    /// Get the address of the code field (CFA) for the dictionary entry that starts at the specified address
    public final func codeFieldAddressForEntryAtAddress(entryAddress: FAddress) -> FAddress {
        let lengthAddress = lengthAndFlagsFieldAddressForEntryAtAddress(entryAddress)
        let nameAddress = lengthAddress + 1

        let length = FCell(charAtAddress(lengthAddress)) & F_LENMASK
        let endOfNameAddress = FAddress(nameAddress + length)
        let codeFieldAddress = alignedCellAddress(endOfNameAddress)

        return codeFieldAddress
    }

    public final func codeFieldAddressForEntryWithName(name: String) -> FAddress {
        let entryAddress = findEntryWithName(name)
        return entryAddress == 0 ? 0 : codeFieldAddressForEntryAtAddress(entryAddress)
    }

    // MARK: - Implementations of primitive operations

    /// Remove top cell from the stack
    /// 
    /// DROP ( x -- )
    public final func DROP() {
        pop()
    }

    /// Exchange the top two cell pairs
    /// 
    /// SWAP ( x1 x2 -- x2 x1 )
    public final func SWAP() {
        let (x1, x2) = pop2()
        push(x2, x1)
    }

    /// Duplicate the cell on the top of the stack
    /// 
    /// DUP ( x -- x x )
    public final func DUP() {
        top() |> push
    }

    /// Place a copy of `x1` on top of the stack
    ///
    /// OVER ( x1 x2 -- x1 x2 x1 )
    public final func OVER() {
        pick(1) |> push
    }

    /// Rotate the top three stack entries
    ///
    /// ROT ( x1 x2 x3 -- x2 x3 x1 )
    public final func ROT() {
        let (x1, x2, x3) = pop3()
        push(x2, x3, x1)
    }

    /// Rotate the top three stack entries in the opposite direction of ROT
    ///
    /// -ROT ( x1 x2 x3 -- x3 x1 x2 )
    public final func NROT() {
        let (x1, x2, x3) = pop3()
        push(x3, x1, x2)
    }

    /// Remove the top two cells from the stack
    ///
    /// 2DROP ( x1 x2 -- )
    public final func TWODROP() {
        dropCells(2)
    }

    /// Duplicate the cell pair on top of the stack
    ///
    /// 2DUP ( x1 x2 -- x1 x2 x1 x2 )
    public final func TWODUP() {
        (pick(1), pick(0)) |> push
    }

    /// Exchange the top two cell pairs
    ///
    /// 2SWAP ( x1 x2 x3 x4 -- x3 x4 x1 x2 )
    public final func TWOSWAP() {
        let (x1, x2, x3, x4) = pop4()
        push(x3, x4, x1, x2)
    }

    /// Duplicate the top-of-stack cell if it is non-zero
    ///
    /// ?DUP ( x -- 0 | x x )
    public final func QDUP() {
        let x = top()
        if x != 0 {
            push(x)
        }
    }

    /// Add one to the top-of-stack value
    ///
    /// 1+ ( n1|u1 -- n2|u2 )
    public final func INCR() {
        let pointer = UnsafeMutablePointer<FCell>(mutablePointerForDataAddress(sp))
        pointer.memory = pointer.memory &+ 1
    }

    /// Subtract one from the top-of-stack value
    ///
    /// 1- ( n1|u1 -- n2|u2 )
    public final func DECR() {
        let pointer = UnsafeMutablePointer<FCell>(mutablePointerForDataAddress(sp))
        pointer.memory = pointer.memory &- 1
    }

    /// Add four to the top-of-stack value
    ///
    /// 4+ ( n1|u1 -- n2|u2 )
    public final func INCR4() {
        let pointer = UnsafeMutablePointer<FCell>(mutablePointerForDataAddress(sp))
        pointer.memory = pointer.memory &+ 4
    }

    /// Subtract four from the top-of-stack value
    ///
    /// 4- ( n1|u1 -- n2|u2 )
    public final func DECR4() {
        let pointer = UnsafeMutablePointer<FCell>(mutablePointerForDataAddress(sp))
        pointer.memory = pointer.memory &- 4
    }

    /// Add the two values at the top of the stack, giving the sum
    ///
    /// + ( n1|u1 n2|u2 -- n3|u3 )
    public final func ADD() {
        let (n1, n2) = pop2()
        (n1 &+ n2) |> push
    }

    /// Subtract the top-of-stack value from the next stack value, giving the difference
    ///
    /// - ( n1|u1 n2|u2 -- n3|u3 )
    public final func SUB() {
        let (n1, n2) = pop2()
        (n1 &- n2) |> push
    }

    /// Multiply the two values at the top of the stack, giving the product
    ///
    /// * ( n1|u1 n2|u2 -- n3|u3 )
    public final func MUL() {
        let (n1, n2) = pop2()
        (n1 &* n2) |> push
    }

    /// Divide dividend by divisor, giving the remainder and quotent
    ///
    /// /MOD ( n1 n2 -- n3 n4 )
    public final func DIVMOD() {
        let (n1, n2) = pop2()
        let result = div(n1, n2)
        (result.rem, result.quot) |> push
    }

    /// Compare two cells at top of stack, giving true if and only if they are equal, or false otherwise
    ///
    /// = ( x1 x2 -- flag )
    public final func EQU() {
        let (x1, x2) = pop2()
        (x1 == x2) |> asForthFlag |> push
    }

    /// Compare two cells at top of stack, giving true if and only if they are not equal, or false otherwise
    ///
    /// <> ( x1 x2 -- flag )
    public final func NEQU() {
        let (x1, x2) = pop2()
        (x1 != x2) |> asForthFlag |> push
    }

    /// Compare two cells at top of stack, giving true if and only if x1 < x2, or false otherwise
    ///
    /// < ( x1 x2 -- flag )
    public final func LT() {
        let (x1, x2) = pop2()
        (x1 < x2) |> asForthFlag |> push
    }

    /// Compare two cells at top of stack, giving true if and only if x1 > x2, or false otherwise
    ///
    /// > ( x1 x2 -- flag )
    public final func GT() {
        let (x1, x2) = pop2()
        (x1 > x2) |> asForthFlag |> push
    }

    /// Compare two cells at top of stack, giving true if and only if x1 <= x2, or false otherwise
    ///
    /// <= ( x1 x2 -- flag )
    public final func LE() {
        let (x1, x2) = pop2()
        (x1 <= x2) |> asForthFlag |> push
    }

    /// Compare two cells at top of stack, giving true if and only if x1 <= x2, or false otherwise
    ///
    /// >= ( x1 x2 -- flag )
    public final func GE() {
        let (x1, x2) = pop2()
        (x1 >= x2) |> asForthFlag |> push
    }

    /// Give true if and only if the top-of-stack is zero, or false otherwise
    ///
    /// 0= ( x -- flag )
    public final func ZEQU() {
        (pop() == 0) |> asForthFlag |> push
    }

    /// Give true if and only if the top-of-stack is non-zero, or false otherwise
    ///
    /// 0<> ( x -- flag )
    public final func ZNEQU() {
        (pop() != 0) |> asForthFlag |> push
    }

    /// Give true if and only if the top-of-stack is less than zero, or false otherwise
    ///
    /// 0< ( x -- flag )
    public final func ZLT() {
        (pop() < 0) |> asForthFlag |> push
    }

    /// Give true if and only if the top-of-stack is greater than zero, or false otherwise
    ///
    /// 0> ( x -- flag )
    public final func ZGT() {
        (pop() > 0) |> asForthFlag |> push
    }

    /// Give true if and only if the top-of-stack is less than or equal to zero, or false otherwise
    ///
    /// 0<= ( x -- flag )
    public final func ZLE() {
        (pop() <= 0) |> asForthFlag |> push
    }

    /// Give true if and only if the top-of-stack is greater than or equal to zero, or false otherwise
    ///
    /// 0>= ( x -- flag )
    public final func ZGE() {
        (pop() >= 0) |> asForthFlag |> push
    }

    /// Bitwise logical AND of the two cells on top of the stack
    ///
    /// AND ( x1 x2 -- x3 )
    public final func AND() {
        let (x1, x2) = pop2()
        (x1 & x2) |> push
    }

    /// Bitwise logical OR of the two cells on top of the stack
    ///
    /// OR ( x1 x2 -- x3 )
    public final func OR() {
        let (x1, x2) = pop2()
        (x1 | x2) |> push
    }

    /// Bitwise logical exclusive-OR of the two cells on top of the stack
    ///
    /// XOR ( x1 x2 -- x3 )
    public final func XOR() {
        let (x1, x2) = pop2()
        (x1 ^ x2) |> push
    }

    /// Invert all bits of the top-of-stack cell
    ///
    /// INVERT ( x1 -- x2 )
    public final func INVERT() {
        (~pop()) |> push
    }

    /// Get the literal value that follows this instruction
    ///
    /// LIT ( -- x )
    public final func LIT() {
        cellAtAddress(ip) |> push
        advanceInstructionPointer()
    }

    /// Store value at address
    ///
    /// ! ( x a-addr -- )
    public final func STORE() {
        let (x, a) = pop2()
        x |> storeCellToAddress(FAddress(a))
    }

    /// Fetch value from address
    ///
    /// @ ( a-addr -- x )
    public final func FETCH() {
        pop() |> asAddress |> cellAtAddress |> push
    }

    /// Add value to value at address
    ///
    /// +! ( n|u a-addr -- )
    public final func ADDSTORE() {
        let (n, a) = pop2()
        let addr = a |> asAddress
        addr |> cellAtAddress |> { $0 &+ n } |> storeCellToAddress(addr)
    }

    /// Subtract value from value at address
    ///
    /// -! ( n|u a-addr -- )
    public final func SUBSTORE() {
        let (n, a) = pop2()
        let addr = a |> asAddress
        addr |> cellAtAddress |> { $0 &- n } |> storeCellToAddress(addr)
    }

    /// Store char at address
    ///
    /// C! ( char c-addr -- )
    public final func STOREBYTE() {
        let (c, a) = pop2()
        c |> asChar |> storeCharToAddress(FAddress(a))
    }

    /// Fetch char from address
    ///
    /// C@ ( c-addr -- char )
    public final func FETCHBYTE() {
        pop() |> asAddress |> charAtAddress |> asCell |> push
    }

    /// Copy character from source address to destination address and increment addresses
    //
    /// C@C! ( c-addr1 c-addr2 -- c-addr3 c-addr4 )
    public final func CCOPY() {
        let (source, dest) = pop2()
        charAtAddress(FAddress(source)) |> storeCharToAddress(FAddress(dest))
        push(source + 1, dest + 1)
    }

    /// Copy chars from one address to another
    ///
    /// CMOVE ( c-addr1 c-addr2 u -- )
    public final func CMOVE() {
        let (source, dest, count) = pop3()

        // We're supposed to treat the count as an unsigned value, but
        // rather than mess with that, let's just assume the value
        // works as a positive signed integer.
        // (We should never have a data-space big enough to allow
        // a CMOVE count that overflows an Int.)
        assert(count >= 0, "count must not be negative")

        let sourceAddr = FAddress(source)
        let destAddr = FAddress(dest)
        let n = Int(count)

        for i in 0..<n {
            charAtAddress(sourceAddr + i) |> storeCharToAddress(destAddr + i)
        }
    }

    /// Give address of cell containing compilation state (false = interpreting; true = compiling)
    ///
    /// STATE ( -- a-addr)
    public final func STATE() {
        state.address |> asCell |> push
    }

    /// Give address of cell containing the data-space pointer
    ///
    /// Note: This differs from ANS FORTH, where HERE returns the data-space pointer value.
    ///
    /// HERE ( -- a-addr )
    public final func HERE() {
        here.address |> asCell |> push
    }

    /// Give address of cell containing the address of the most recently defined dictionary word
    ///
    /// LATEST ( -- a-addr )
    public final func LATEST() {
        latest.address |> asCell |> push
    }

    /// Give address of cell containing the address of the initial value of the parameter stack pointer
    ///
    /// S0 ( -- a-addr )
    public final func SZ() {
        s0.address |> asCell |> push
    }

    /// Give address of cell containing the current numeric base
    ///
    /// BASE ( -- a-addr )
    public final func BASE() {
        base.address |> asCell |> push
    }

    /// Give current version of this FORTH
    ///
    /// VERSION ( -- n )
    public final func VERSION() {
        JONES_VERSION |> asCell |> push
    }

    /// Give the address of the top of the return stack area
    ///
    /// The expression "R0 RSPSTORE" can be executed to clear the return stack.
    /// Otherwise, this value is not useful.
    ///
    /// R0 ( -- addr )
    public final func RZ() {
        returnStack.count |> asCell |> push
    }

    /// Give the codeword for DOCOL
    ///
    /// DOCOL ( -- x )
    public final func __DOCOL() {
        Primitive.DOCOL.rawValue |> asCell |> push
    }

    /// Give the bitmask for the IMMEDIATE flag of the flags/len field
    ///
    /// F_IMMED ( -- x )
    public final func __F_IMMED() {
        push(F_IMMED)
    }

    /// Give the bitmask for the HIDDEN flag of the flags/len field
    ///
    /// F_HIDDEN ( -- x )
    public final func __F_HIDDEN() {
        push(F_HIDDEN)
    }

    /// Give the bitmask for the length portion of the flags/len field
    ///
    /// F_LENMASK ( -- x )
    public final func __F_LENMASK() {
        push(F_LENMASK)
    }

    /// Move value from parameter stack to return stack
    ///
    /// >R ( x -- ) ( R: -- x )
    public final func TOR() {
        pop() |> pushReturn
    }

    /// Move value from return stack to parameter stack
    ///
    /// R> ( R: x -- ) ( -- x )
    public final func FROMR() {
        popReturn() |> push
    }

    /// Get the value of the return stack pointer
    ///
    /// RSP@ ( -- addr )
    public final func RSPFETCH() {
        rsp |> asCell |> push
    }

    /// Set the value of the return stack pointer
    ///
    /// RSP! ( addr -- )
    public final func RSPSTORE() {
        rsp = pop() |> asAddress
    }

    /// Drop value from the return stack
    ///
    /// RDROP ( R: x -- )
    public final func RDROP() {
        rsp--
    }

    /// Get value of parameter stack pointer
    /// 
    /// DSPFETCH ( -- addr )
    public final func DSPFETCH() {
        sp |> asCell |> push
    }

    /// Set value of parameter stack pointer
    ///
    /// DSPSTORE ( addr -- )
    public final func DSPSTORE() {
        sp = pop() |> asAddress
    }

    /// Receive one character from input stream
    ///
    /// KEY ( -- char )
    public final func KEY() {
        let c = readChar()
        if c == EOF {
            onKeyEOF()
        }
        else {
            push(c)
        }
    }

    /// Send character to output stream
    ///
    /// EMIT ( x -- )
    public final func EMIT() {
        pop() |> writeChar
    }

    /// Read the next full word of input, giving address and length
    /// of buffer containing parsed word.
    ///
    /// Skips any blanks and comments starting with '\'.
    /// Then reads non-blank characters until a blank is found.
    /// 
    /// Note that this is not compliant with the ANS FORTH
    /// definition of WORD.
    ///
    /// WORD ( -- c-addr u )
    public final func WORD() {
        readWord() |> push
    }

    /// Parse a numeric string, giving the number and count of unparsed characters
    ///
    /// ( c-addr u -- n u )
    public final func NUMBER() {
        let (addr, length) = pop2() |> asAddressAndCount

        let (number, unparsedCount) = numberAtAddress(addr, length: length)

        (FCell(number), FCell(unparsedCount)) |> push
    }

    /// Look up a word in the dictionary, giving address of its dictionary entry or 0 if not found
    ///
    /// FIND ( c-addr u -- a-addr|0 )
    public final func FIND() {
        pop2() |> asAddressAndCount |> find |> asCell |> push
    }

    /// Given pointer to dictionary entry, give the address of the code field
    ///
    /// >CFA ( a-addr -- a-addr )
    public final func TCFA() {
        pop() |> asAddress |> codeFieldAddressForEntryAtAddress |> asCell |> push
    }

    /// Given a name, create a new dictionary entry header
    ///
    /// CREATE ( c-addr u -- )
    public final func CREATE() {
        let (addr, length) = pop2() |> asAddressAndCount
        trace("CREATE: \(stringAtAddress(addr, length: length)!)")
        createEntryForNameAtAddress(addr, length: length)
    }

    /// Append cell to dictionary
    ///
    /// , ( x -- )
    public final func COMMA() {
        pop() |> addCellHere
    }

    /// Set interpreter state to "interpreting"
    ///
    /// [ ( -- )
    public final func LBRAC() {
        state.value = FFalse
    }

    /// Set interpreter state to "compiling"
    ///
    /// ] ( -- )
    public final func RBRAC() {
        state.value = FTrue
    }

    /// Make the most recent definition an immediate word
    public final func IMMEDIATE() {
        let entryAddress = latest.valueAsAddress
        let lengthFlagsAddress = entryAddress + FCharsPerCell

        (charAtAddress(lengthFlagsAddress) | FChar(F_IMMED))
            |> storeCharToAddress(lengthFlagsAddress)
    }

    /// Toggle the hidden flag of a dictionary entry
    ///
    /// HIDDEN ( a-addr -- )
    public final func HIDDEN() {
        let entryAddress = FAddress(pop())
        let lengthFlagsAddress = entryAddress + FCharsPerCell

        (charAtAddress(lengthFlagsAddress) ^ FChar(F_HIDDEN))
            |> storeCharToAddress(lengthFlagsAddress)
    }

    /// Find name and return its execution token
    ///
    /// ' ( "<spaces>name" -- xt )
    public final func TICK() {
        // See the description of TICK in jonesforth.S for an description
        // of the trick that lets us implement it like this, rather
        // than defining an IMMEDIATE word that uses WORD FIND >CFA.
        //
        // Note that this trick only works in compiled code.  It doesn't
        // work in IMMEDIATE mode.
        assert(state.value == 1, "can only use ' (TICK) in compiled code")
        LIT()
    }

    /// Add offset to instruction pointer
    ///
    /// BRANCH ( -- )
    public final func BRANCH() {
        let offset = cellAtAddress(ip) |> asAddress
        ip += offset
    }

    /// Branch if top of stack is zero
    ///
    /// 0BRANCH ( x -- )
    public final func ZBRANCH() {
        if pop() == 0 {
            BRANCH()
        }
        else {
            // skip the offset
            advanceInstructionPointer()
        }
    }

    /// Primitive word used to implement ." and S"
    ///
    /// LITSTRING ( -- c-addr u )
    public final func LITSTRING() {
        let length = cellAtAddress(ip)
        advanceInstructionPointer()

        ip |> asCell |> push
        length |> push

        ip = alignedCellAddress(ip + Int(length))
    }

    /// Write characters to the output stream
    ///
    /// Note that this word is named "TYPE" in ANS Forth
    ///
    /// TELL ( c-addr u -- )
    public final func TELL() {
        let (addr, length) = pop2() |> asAddressAndCount
        for i in 0..<length {
            charAtAddress(addr + i) |> writeChar
        }
    }

    /// Read word from input stream and execute it
    ///
    /// INTERPRET ( i**x -- j**x )
    public final func INTERPRET() {
        WORD()

        // Grab these values before FIND() consumes them
        let (wordAddress, wordLength) = (pick(1), pick(0)) |> asAddressAndCount

        FIND()

        let entryAddress = pop() |> asAddress

        if entryAddress != 0 {
            // In the dictionary. Is it an IMMEDIATE codeword?
            let lengthAndFlagsAddress = lengthAndFlagsFieldAddressForEntryAtAddress(entryAddress)
            let lengthAndFlags = charAtAddress(lengthAndFlagsAddress) |> asCell
            let cfa = codeFieldAddressForEntryAtAddress(entryAddress)
            if (lengthAndFlags & F_IMMED != 0) || (state.value == 0) {
                // Execute
                executeCodeFieldAddress(cfa)
            }
            else {
                // Compiling - just append the code's address to the current dictionary definition
                //trace("INTERPRET: compile \(cfa) into definition")
                cfa |> addCellHere
            }
        }
        else {
            // Not in the dictionary (not a word) so it must be a numeric literal
            let (number, unparsed) = numberAtAddress(FAddress(wordAddress), length: Int(wordLength))
            if unparsed == 0 {
                if state.value == 0 {
                    // Execute
                    trace("INTERPRET: push \(number) onto stack")
                    number |> asCell |> push
                }
                else {
                    // Compiling
                    //trace("INTERPRET: compile numeric literal \(number)")
                    FCell(LIT_codeFieldAddress) |> addCellHere
                    number |> addCellHere
                }
            }
            else {
                if wordLength > 0 {
                    if let wordAsString = stringAtAddress(FAddress(wordAddress), length: Int(wordLength)) {
                        abortWithMessage("INTERPRET: parse error for word \"\(wordAsString)\"")
                    }
                    else {
                        abortWithMessage("INTERPRET: parse error: WORD address: \(wordAddress), length: \(wordLength)")
                    }
                }
                else {
                    abortWithMessage("INTERPRET: parse error: WORD address: \(wordAddress), length: \(wordLength)")
                }
            }
        }
    }

    /// Parse name delimited by a space. Put the value of its first character onto the stack.
    ///
    /// CHAR ( "<spaces>name" -- char )
    public func CHAR() {
        let (wordAddress, wordLength) = readWord() |> asAddressAndCount
        wordAddress |> charAtAddress |> asCell |> push
    }

    /// EXECUTE ( xt -- )
    public func EXECUTE() {
        pop() |> asAddress |> executeCodeFieldAddress
    }

    /// Exit the process
    /// 
    /// BYE ( -- )
    public func BYE() {
        exit(EXIT_SUCCESS)
    }

    /// Give number of unused cells.
    /// 
    /// UNUSED ( -- n )
    public func UNUSED() {
        ((dataSpace.count - here.valueAsAddress) / FCharsPerCell) |> asCell |> push
    }

    // MARK: - Diagnostics

    /// Set this true to enable trace() functionality
    let isTraceEnabled = false

    /// Write a debug trace message if trace messages are enabled
    ///
    /// This is controlled by the `isTraceEnabled` property
    final func trace(message: @autoclosure () -> String) {
        if isTraceEnabled {
            fputs("[\(message())]\n", stderr)
            fflush(stderr)
        }
    }

    /// Mapping of opcode to name
    ///
    /// This is only used for trace messages and other diagnostic purposes.
    /// It is not used by the Forth interpreter.
    var _nameForOpcode: [Int : String] = Dictionary()

    /// Return human-readable name for opcode
    final func nameForOpcode(opcode: Int) -> String {
        if opcode == Primitive.DOCOL.rawValue {
            return "DOCOL"
        }
        else {
            return _nameForOpcode[opcode] ?? "\(opcode)"
        }
    }

    /// Return name of the dictionary entry with specified code field address
    final func nameForCodeFieldAddress(codeFieldAddress: FAddress) -> String {
        // Walk back through linked list, returning the address of the first
        // entry whose address is less than the code field address
        var link = latest.valueAsAddress
        while link > codeFieldAddress {
            link = cellAtAddress(link) |> asAddress
        }
        let lengthFieldAddress = lengthAndFlagsFieldAddressForEntryAtAddress(link)
        let length = FCell(charAtAddress(lengthFieldAddress)) & F_LENMASK
        let nameFieldAddress = nameFieldAddressForEntryAtAddress(link)
        return stringAtAddress(nameFieldAddress, length: Int(length))!
    }

    /// Return a snapshot of the internal state of the FORTH machine.
    ///
    /// This is intended for unit testing and debugging.
    /// It should not be used to circumvent the public API.
    public final func snapshot() -> Snapshot {
        return Snapshot(
            options:      options,
            here:         here.valueAsAddress,
            latest:       latest.valueAsAddress,
            state:        state.value,
            base:         base.value,
            ip:           ip,
            sp:           sp,
            rsp:          rsp,
            stack:        Array(dataSpace[sp..<dataSpace.count]),
            returnStack:  Array(returnStack[rsp..<returnStack.count]),
            dictionary:   Array(dataSpace[0..<here.valueAsAddress]))
    }

    /// Structure returned by the `snapshot()` method
    public struct Snapshot {
        public let options:      Options
        public let here:         Int
        public let latest:       Int
        public let state:        FCell
        public let base:         FCell
        public let ip:           Int
        public let sp:           Int
        public let rsp:          Int
        public let stack:        [FChar]
        public let returnStack:  [FChar]
        public let dictionary:   [FChar]
    }
}
