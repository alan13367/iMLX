import Foundation

struct WebSearchToolExecutor: ToolExecutor {
    let toolName = "web_search"
    let webSearchService: WebSearchService

    func execute(arguments: [String: String], context _: ToolInputContext) async throws -> ToolExecutionResult {
        let query = (arguments["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw ToolExecutionFailure.invalidArguments("A search query is required.")
        }

        let startTime = Date()
        let result: MessageGroundingResult
        do {
            result = try await webSearchService.retrieveContext(for: query)
        } catch {
            if error.isNetworkAvailabilityFailure {
                throw ToolExecutionFailure.networkUnavailable("Web search was unavailable.")
            }
            throw ToolExecutionFailure.executionFailed("Web search failed.")
        }

        guard !result.contextBlock.isEmpty else {
            throw ToolExecutionFailure.noContent("Web search did not return usable results.")
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

struct ReadURLToolExecutor: ToolExecutor {
    let toolName = "read_url"
    let webSearchService: WebSearchService

    func execute(arguments: [String: String], context: ToolInputContext) async throws -> ToolExecutionResult {
        let startTime = Date()
        let urlString = (arguments["url"] ?? context.singleDetectedPublicURL?.absoluteString ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = normalizedPublicURL(urlString) else {
            throw ToolExecutionFailure.invalidArguments("A readable public http or https URL is required.")
        }

        let result: MessageGroundingResult
        do {
            result = try await webSearchService.retrieveContext(forDirectURL: url, userQuery: context.latestUserMessage)
        } catch {
            if error.isNetworkAvailabilityFailure {
                throw ToolExecutionFailure.networkUnavailable("That link could not be read because network access was unavailable.")
            }
            throw ToolExecutionFailure.executionFailed("That link could not be read.")
        }

        guard !result.contextBlock.isEmpty else {
            throw ToolExecutionFailure.noContent("That link did not contain readable content.")
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

    private func normalizedPublicURL(_ candidate: String) -> URL? {
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }

        // Upgrade http to https to comply with ATS policy
        if scheme == "http" {
            let httpsString = url.absoluteString.replacingOccurrences(of: "http://", with: "https://", options: .caseInsensitive)
            return URL(string: httpsString) ?? url
        }

        return url
    }
}

extension Error {
    var isNetworkAvailabilityFailure: Bool {
        let urlError: URLError?
        if let error = self as? URLError {
            urlError = error
        } else {
            let nsError = self as NSError
            if nsError.domain == NSURLErrorDomain {
                urlError = URLError(.init(rawValue: nsError.code))
            } else {
                urlError = nil
            }
        }

        guard let urlError else { return false }
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }
}

