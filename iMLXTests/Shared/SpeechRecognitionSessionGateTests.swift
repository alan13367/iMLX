import XCTest
@testable import iMLX

final class SpeechRecognitionSessionGateTests: XCTestCase {
    func testFinishedSessionRejectsLateCallbacksAndDuplicateFinalization() {
        var gate = SpeechRecognitionSessionGate()
        let sessionID = gate.begin()

        XCTAssertTrue(gate.accepts(sessionID))
        XCTAssertTrue(gate.finish(sessionID))
        XCTAssertFalse(gate.accepts(sessionID))
        XCTAssertFalse(gate.finish(sessionID))
    }

    func testNewSessionRejectsCallbacksFromPreviousSession() {
        var gate = SpeechRecognitionSessionGate()
        let previousSessionID = gate.begin()
        let currentSessionID = gate.begin()

        XCTAssertFalse(gate.accepts(previousSessionID))
        XCTAssertFalse(gate.finish(previousSessionID))
        XCTAssertTrue(gate.accepts(currentSessionID))
        XCTAssertTrue(gate.finish(currentSessionID))
    }
}
