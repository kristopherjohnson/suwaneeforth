//
//  forthTests.swift
//  forthTests
//
//  Created by Kristopher Johnson on 12/2/14.
//  Copyright (c) 2014 Kristopher Johnson. All rights reserved.
//

import Cocoa
import XCTest
import forth


// Generic equality operators for tuples of Equatable types

func == <A : Equatable, B : Equatable>(lhs: (A, B), rhs: (A, B)) -> Bool
{
    return (lhs.0 == rhs.0) && (lhs.1 == rhs.1)
}

func == <A : Equatable, B : Equatable, C : Equatable>(lhs: (A, B, C), rhs: (A, B, C)) -> Bool
{
    return (lhs.0 == rhs.0) && (lhs.1 == rhs.1) && (lhs.2 == rhs.2)
}

func == <A : Equatable, B : Equatable, C : Equatable, D : Equatable>(lhs: (A, B, C, D), rhs: (A, B, C, D)) -> Bool
{
    return (lhs.0 == rhs.0) && (lhs.1 == rhs.1) && (lhs.2 == rhs.2) && (lhs.3 == rhs.3)
}


// Equality operators for tuples of Ints and Cells
// (so we don't need to cast every numeric literal to Cell in our unit tests)

func == (lhs: (Int, Int), rhs: (FCell, FCell)) -> Bool
{
    return (FCell(lhs.0), FCell(lhs.1)) == rhs
}

func == (lhs: (Int, Int, Int), rhs: (FCell, FCell, FCell)) -> Bool
{
    return (FCell(lhs.0), FCell(lhs.1), FCell(lhs.2)) == rhs
}

func == (lhs: (Int, Int, Int, Int), rhs: (FCell, FCell, FCell, FCell)) -> Bool
{
    return (FCell(lhs.0), FCell(lhs.1), FCell(lhs.2), FCell(lhs.3)) == rhs
}


class forthTests: XCTestCase {

    // Initialized with a fresh instance for each test case
    var fm: ForthMachine!

    override func setUp() {
        super.setUp()

        fm = ForthMachine()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testInitialSnapshot() {
        let s = fm.snapshot()

        XCTAssert(s.here > 0, "HERE should be initialized")
        XCTAssert(s.latest > 0, "LATEST should be initialized")
        XCTAssertEqual(0, Int(s.state), "STATE should be 0 (interpreting)")
        XCTAssertEqual(10, Int(s.base), "BASE should be decimal")
        XCTAssertEqual(s.options.dataSpaceCharCount, s.rsp, "rsp should be at top of data space")
        XCTAssertEqual(0, s.stack.count, "stack should be empty")
        XCTAssertEqual(0, s.returnStack.count, "return stack should be empty")
        XCTAssertEqual(s.here, s.dictionary.count, "snapshot should include region of dictionary up to HERE")
    }

    func test_DUP_DROP_SWAP_OVER() {
        XCTAssertEqual(0, fm.stackCellDepth, "should start with empty stack")

        fm.push(1, 2)
        XCTAssertEqual(2, fm.stackCellDepth)
        XCTAssert((1, 2) == fm.top2())

        fm.DUP()
        XCTAssertEqual(3, fm.stackCellDepth)
        XCTAssert((1, 2, 2) == fm.top3())

        fm.DROP()
        XCTAssertEqual(2, fm.stackCellDepth)
        XCTAssert((1, 2) == fm.top2())

        fm.SWAP()
        XCTAssertEqual(2, fm.stackCellDepth)
        XCTAssert((2, 1) == fm.top2())

        fm.OVER()
        XCTAssertEqual(3, fm.stackCellDepth)
        XCTAssert((2, 1, 2) == fm.top3())
    }

    func test_ROT_NROT() {
        fm.push(1, 2, 3)
        fm.ROT()
        XCTAssertEqual(3, fm.stackCellDepth)
        XCTAssert((2, 3, 1) == fm.top3())

        fm.NROT()
        XCTAssertEqual(3, fm.stackCellDepth)
        XCTAssert((1, 2, 3) == fm.top3())
    }

    func test_TWODROP_TWODUP() {
        fm.push(1, 2, 3)
        fm.TWODROP()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssert(1 == fm.top())

        fm.push(2)
        fm.TWODUP()
        XCTAssertEqual(4, fm.stackCellDepth)
        XCTAssert((1, 2, 1, 2) == fm.top4())
    }

    func test_TWOSWAP() {
        fm.push(1, 2, 3, 4)
        fm.TWOSWAP()
        XCTAssertEqual(4, fm.stackCellDepth)
        XCTAssert((3, 4, 1, 2) == fm.top4())
    }

    func test_QDUP() {
        fm.push(1)
        fm.QDUP()
        XCTAssertEqual(2, fm.stackCellDepth)
        XCTAssert((1, 1) == fm.top2())

        fm.push(-1)
        fm.QDUP()
        XCTAssertEqual(4, fm.stackCellDepth)
        XCTAssert((1, 1, -1, -1) == fm.top4())

        fm.push(0)
        fm.QDUP()
        XCTAssertEqual(5, fm.stackCellDepth)
        XCTAssert((1, -1, -1, 0) == fm.top4())
    }

    func test_INCR_DECR() {
        fm.push(10)

        fm.INCR()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertEqual(FCell(11), fm.top())

        fm.DECR()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertEqual(FCell(10), fm.top())
    }

    func test_INCR4_DECR4() {
        fm.push(10)

        fm.INCR4()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertEqual(FCell(14), fm.top())

        fm.DECR4()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertEqual(FCell(10), fm.top())
    }

    func test_ADD() {
        fm.push(20, 30)

        fm.ADD()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertEqual(FCell(50), fm.top())

        fm.push(-51)
        fm.ADD()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertEqual(FCell(-1), fm.top())

        // Adding -1 to Int32.min
        // should wrap around to Int32.max
        fm.push(Int32.min)
        fm.ADD()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertEqual(FCell(Int32.max), fm.top())

        // Adding 1 to Int32.max should wrap
        // around to Int32.min
        fm.push(1)
        fm.ADD()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertEqual(FCell(Int32.min), fm.top())
    }

    func test_SUB() {
        fm.push(10, 5)

        fm.SUB()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertEqual(FCell(5), fm.top())

        fm.push(7)
        fm.SUB()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertEqual(FCell(-2), fm.top())

        fm.push(-4)
        fm.SUB()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertEqual(FCell(2), fm.top())
    }

    func test_MUL() {
        fm.push(22, 33)

        fm.MUL()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertEqual(FCell(726), fm.top())

        fm.push(-2)
        fm.MUL()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertEqual(FCell(-1452), fm.top())
    }

    func test_DIVMOD() {
        fm.push(30, 7)

        fm.DIVMOD()
        XCTAssertEqual(2, fm.stackCellDepth)
        XCTAssert((2, 4) == fm.top2())
    }

    func test_FIND() {
        fm.setWord("NUMBER")
        fm.FIND()
        XCTAssertEqual(1, fm.stackCellDepth)
        let addressOfNUMBER = FAddress(fm.pop())
        XCTAssertNotEqual(0, addressOfNUMBER)

        fm.setWord("DROP")
        fm.FIND()
        XCTAssertEqual(1, fm.stackCellDepth)
        let addressOfDROP = FAddress(fm.pop())
        XCTAssertNotEqual(0, addressOfDROP)

        XCTAssertNotEqual(addressOfNUMBER, addressOfDROP, "NUMBER and DROP should have different addresses")

        fm.setWord("testFIND")
        fm.FIND()
        XCTAssertEqual(1, fm.stackCellDepth)
        let resultForNotFound = FAddress(fm.pop())
        XCTAssertEqual(0, resultForNotFound, "should get 0 for non-existent word")
    }

    func test_TCFA() {
        fm.setWord("DROP")
        fm.FIND()

        XCTAssertEqual(1, fm.stackCellDepth)
        let entryAddress = fm.top()

        // DROP is four characters long, so the code-field
        // address should be at
        //
        //   entryAddress
        //     + 4 (skip link field)
        //     + 1 (skip length field)
        //     + 4 (skip length of "DROP")
        //     + 3 (padding to align code on cell boundary)
        //
        //   = (entryAddress + 12)
        fm.TCFA()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertEqual(entryAddress + 12, fm.top())

        // We should find the primitive opcode for DROP
        // at that address
        let codeword = fm.cellAtAddress(FAddress(fm.top()))
        XCTAssertEqual(FCell(ForthMachine.Primitive.DROP.rawValue), codeword)
    }

    func test_CREATE() {
        fm.setWord("test_CREATE")
        fm.FIND()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertEqual(FCell(0), fm.pop(), "should not find word test_CREATE in initial state")

        fm.setWord("test_CREATE")
        fm.CREATE()

        fm.setWord("test_CREATE")
        fm.FIND()
        XCTAssertEqual(1, fm.stackCellDepth)
        XCTAssertNotEqual(FCell(0), fm.pop(), "should find word test_CREATE after CREATE")
    }
}
