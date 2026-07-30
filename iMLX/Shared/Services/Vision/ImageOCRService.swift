import Foundation
import ImageIO
import Vision

actor ImageOCRService {
    func retrieveContext(from images: [ChatAttachmentImage]) async throws -> MessageGroundingResult {
        guard !images.isEmpty else {
            return MessageGroundingResult(contextBlock: "", sources: [])
        }

        var sections: [String] = []
        var sources: [MessageSource] = []

        for (index, image) in images.enumerated() {
            guard let recognizedText = try recognizedText(in: image.data), !recognizedText.isEmpty else {
                continue
            }

            let title = "Attached Image \(index + 1)"
            let excerpt = compactExcerpt(from: recognizedText)
            sections.append("Source: \(title)\n\(recognizedText)")
            sources.append(
                MessageSource(
                    id: "\(image.id.uuidString)-ocr",
                    kind: .image,
                    title: title,
                    excerpt: excerpt,
                    location: nil,
                    url: nil,
                    score: nil
                )
            )
        }

        guard !sections.isEmpty else {
            return MessageGroundingResult(contextBlock: "", sources: [])
        }

        let contextBlock = """
        The assistant may use the following text extracted locally from the user's attached images.

        This OCR output is grounded in the current message's images. If any extracted text seems incomplete or unclear, say so plainly.

        \(sections.joined(separator: "\n\n---\n\n"))
        """

        return MessageGroundingResult(contextBlock: contextBlock, sources: sources)
    }

    private func recognizedText(in data: Data) throws -> String? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        var recognizedLines: [String] = []
        let request = VNRecognizeTextRequest { request, error in
            if error != nil {
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }

            recognizedLines = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let normalized = normalizeWhitespace(recognizedLines.joined(separator: "\n"))
        return normalized.isEmpty ? nil : normalized
    }

    private func compactExcerpt(from text: String) -> String {
        GroundingText.excerpt(from: text, maximumCharacters: 240, suffix: "…")
    }

    private func normalizeWhitespace(_ text: String) -> String {
        GroundingText.normalizeWhitespace(text)
    }
}
