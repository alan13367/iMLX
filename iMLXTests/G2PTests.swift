import XCTest
@testable import iMLX

final class G2PTests: XCTestCase {
    func testEnglishG2P() throws {
        throw XCTSkip("English Misaki smoke coverage depends on bundled neural resources and is outside multilingual Kokoro tokenization coverage.")
    }

    func testSpanishG2P() throws {
        _ = KokoroConfig.loadConfig()
        let processor = try G2PFactory.createG2PProcessor(engine: .multilingual)
        try processor.setLanguage(.spanish)
        let (phonemes, tokens) = try processor.process(input: "Hola, ¿cómo estás?")
        XCTAssertFalse(phonemes.isEmpty)
        XCTAssertNil(tokens)
        XCTAssertTokenizesFully(phonemes)
    }

    func testSpanishG2PStripsDigitsAndSymbols() throws {
        _ = KokoroConfig.loadConfig()
        let processor = try G2PFactory.createG2PProcessor(engine: .multilingual)
        try processor.setLanguage(.spanish)
        let (phonemes, tokens) = try processor.process(input: "Tengo 2 gatos — nota: #1")
        XCTAssertFalse(phonemes.isEmpty)
        XCTAssertNil(tokens)
        XCTAssertTokenizesFully(phonemes)
    }

    func testSpanishG2PFailsWhenInputHasNoSpeakableContent() throws {
        _ = KokoroConfig.loadConfig()
        let processor = try G2PFactory.createG2PProcessor(engine: .multilingual)
        try processor.setLanguage(.spanish)

        XCTAssertThrowsError(try processor.process(input: "123 @@@")) { error in
            XCTAssertEqual(error as? G2PProcessorError, .invalidPhonemeOutput)
        }
    }

    func testChineseG2P() throws {
        _ = KokoroConfig.loadConfig()
        let processor = try G2PFactory.createG2PProcessor(engine: .multilingual)
        try processor.setLanguage(.mandarinChinese)
        let (phonemes, tokens) = try processor.process(input: "你好，今天怎么样？")
        XCTAssertFalse(phonemes.isEmpty)
        XCTAssertNil(tokens)
        XCTAssertFalse(phonemes.contains("，"))
        XCTAssertFalse(phonemes.contains("？"))
        XCTAssertTokenizesFully(phonemes)
    }

    func testChineseG2PStripsDigitsInMixedText() throws {
        _ = KokoroConfig.loadConfig()
        let processor = try G2PFactory.createG2PProcessor(engine: .multilingual)
        try processor.setLanguage(.mandarinChinese)
        let (phonemes, tokens) = try processor.process(input: "今天 2 点见")
        XCTAssertFalse(phonemes.isEmpty)
        XCTAssertNil(tokens)
        XCTAssertTokenizesFully(phonemes)
    }

    func testChineseG2PFailsWhenInputHasNoSpeakableContent() throws {
        _ = KokoroConfig.loadConfig()
        let processor = try G2PFactory.createG2PProcessor(engine: .multilingual)
        try processor.setLanguage(.mandarinChinese)

        XCTAssertThrowsError(try processor.process(input: "123 @@@")) { error in
            XCTAssertEqual(error as? G2PProcessorError, .invalidPhonemeOutput)
        }
    }

    func testMultilingualG2PFailsClosedForEmptyOutput() throws {
        _ = KokoroConfig.loadConfig()
        let processor = try G2PFactory.createG2PProcessor(engine: .multilingual)
        try processor.setLanguage(.spanish)

        XCTAssertThrowsError(try processor.process(input: "¿¡")) { error in
            XCTAssertEqual(error as? G2PProcessorError, .invalidPhonemeOutput)
        }
    }

    private func XCTAssertTokenizesFully(
        _ phonemes: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tokenIDs = Tokenizer.tokenize(phonemizedText: phonemes)
        XCTAssertFalse(tokenIDs.isEmpty, file: file, line: line)
        XCTAssertEqual(tokenIDs.count, phonemes.count, file: file, line: line)
    }
}
