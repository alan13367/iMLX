import Foundation

struct OCRImageTextToolExecutor: ToolExecutor {
    let toolName = "ocr_image_text"
    let imageOCRService: ImageOCRService

    func execute(arguments _: [String: String], context: ToolInputContext) async throws -> ToolExecutionResult {
        guard !context.attachedImages.isEmpty else {
            throw ToolExecutionFailure.invalidArguments("At least one attached image is required for OCR.")
        }

        let startTime = Date()
        let result: MessageGroundingResult
        do {
            result = try await imageOCRService.retrieveContext(from: context.attachedImages)
        } catch {
            throw ToolExecutionFailure.executionFailed("Image text extraction failed.")
        }

        guard !result.contextBlock.isEmpty else {
            throw ToolExecutionFailure.noContent("No readable text was found in the attached images.")
        }

        let duration = Date().timeIntervalSince(startTime)
        return ToolExecutionResult(
            toolName: toolName,
            status: .success,
            message: nil,
            contextBlock: result.contextBlock,
            sources: result.sources,
            durationSeconds: duration
        )
    }
}

struct DocumentSynthesizeToolExecutor: ToolExecutor {
    let toolName = "document_synthesize"
    let documentLibraryService: DocumentLibraryService

    func execute(arguments: [String: String], context: ToolInputContext) async throws -> ToolExecutionResult {
        guard !context.attachedDocuments.isEmpty else {
            throw ToolExecutionFailure.invalidArguments("At least one attached document is required.")
        }

        let query = (arguments["query"] ?? context.latestUserMessage)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw ToolExecutionFailure.invalidArguments("A document query is required.")
        }

        let startTime = Date()
        let result = await documentLibraryService.retrieveContext(
            for: query,
            documents: context.attachedDocuments
        )

        guard !result.contextBlock.isEmpty else {
            throw ToolExecutionFailure.noContent("No relevant document excerpts were found.")
        }

        return ToolExecutionResult(
            toolName: toolName,
            status: .success,
            message: nil,
            contextBlock: result.contextBlock,
            sources: result.sources,
            durationSeconds: Date().timeIntervalSince(startTime)
        )
    }
}

