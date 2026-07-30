import Foundation

actor SpeechAssetService {
    typealias StatusObserver = @Sendable (SpeechAssetStatus) async -> Void

    private struct PersistedState: Codable {
        var activatedLocales: [String]
    }

    private enum AssetValidationError: LocalizedError {
        case invalidResponse
        case invalidStatusCode(Int)
        case emptyDownload
        case invalidSafeTensorsHeader
        case invalidSafeTensorsJSON

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The speech asset download returned an invalid response."
            case .invalidStatusCode(let code):
                return "The speech asset download failed with HTTP \(code)."
            case .emptyDownload:
                return "The speech asset download was empty."
            case .invalidSafeTensorsHeader, .invalidSafeTensorsJSON:
                return "The downloaded Kokoro model file is corrupted."
            }
        }
    }

    private let fileManager = FileManager.default
    private let assetsDirectory: URL
    private let stateFileURL: URL
    private let session: URLSession

    private let modelURL = URL(string: "https://huggingface.co/mlx-community/Kokoro-82M-4bit/resolve/main/kokoro-v1_0.safetensors")!

    private var statusObserver: StatusObserver?
    private var activatedLocales: Set<VoiceLocale> = []
    private var activeDownload: SpeechAssetDownloadState?

    init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.init(assetsDirectory: appSupport.appendingPathComponent(Constants.Storage.speechAssetsDirectory, isDirectory: true))
    }

    init(assetsDirectory: URL, session: URLSession? = nil) {
        self.assetsDirectory = assetsDirectory
        stateFileURL = assetsDirectory.appendingPathComponent(Constants.Storage.speechAssetsStateFilename)

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 60 * 30
            configuration.timeoutIntervalForResource = 60 * 60
            self.session = URLSession(configuration: configuration)
        }

        try? fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        activatedLocales = Self.loadPersistedState(from: stateFileURL)
    }

    func setStatusObserver(_ observer: @escaping StatusObserver) async {
        statusObserver = observer
        await notifyObserver()
    }

    func status() -> SpeechAssetStatus {
        pruneInvalidActivatedLocales()
        return SpeechAssetStatus(
            hasCoreModel: isValidCoreModelPresent,
            hasVoiceAssets: !activatedLocales.isEmpty,
            activatedLocales: activatedLocales,
            activeDownload: activeDownload
        )
    }

    func fileLocations(for locale: VoiceLocale) -> SpeechAssetFileLocations? {
        guard isValidCoreModelPresent,
              isValidVoiceAssetPresent(for: locale) else {
            return nil
        }
        return SpeechAssetFileLocations(modelURL: coreModelFileURL, voiceURL: voiceFileURL(for: locale))
    }

    @discardableResult
    func prepareAssets(for locale: VoiceLocale) async throws -> SpeechAssetStatus {
        if !isValidCoreModelPresent {
            removeItemIfPresent(at: coreModelFileURL)
            activeDownload = SpeechAssetDownloadState(locale: locale, phase: "Downloading Kokoro model", progress: nil)
            await notifyObserver()
            try await download(from: modelURL, to: coreModelFileURL, validator: validateSafeTensorsFile)
        }

        if !isValidVoiceAssetPresent(for: locale) {
            removeItemIfPresent(at: voiceFileURL(for: locale))
            activeDownload = SpeechAssetDownloadState(locale: locale, phase: "Downloading Kokoro voice", progress: nil)
            await notifyObserver()
            try await download(from: remoteVoiceURL(for: locale), to: voiceFileURL(for: locale), validator: validateSafeTensorsFile)
        }

        activeDownload = SpeechAssetDownloadState(locale: locale, phase: "Preparing voice locale", progress: nil)
        await notifyObserver()
        activatedLocales.insert(locale)
        persistState()
        activeDownload = nil
        await notifyObserver()
        return status()
    }

    func clearAllAssets() async {
        try? fileManager.removeItem(at: assetsDirectory)
        try? fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        activatedLocales = []
        activeDownload = nil
        persistState()
        await notifyObserver()
    }

    private func download(
        from remoteURL: URL,
        to destinationURL: URL,
        validator: (URL) throws -> Void
    ) async throws {
        let temporaryURL = destinationURL.appendingPathExtension("download")
        try? fileManager.removeItem(at: temporaryURL)
        try? fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var request = URLRequest(url: remoteURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (downloadedURL, response) = try await session.download(for: request)
        try validate(response: response)
        try fileManager.moveItem(at: downloadedURL, to: temporaryURL)
        do {
            try validator(temporaryURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private var coreModelFileURL: URL {
        assetsDirectory.appendingPathComponent("kokoro-v1_0.safetensors")
    }

    private var isValidCoreModelPresent: Bool {
        guard fileManager.fileExists(atPath: coreModelFileURL.path) else {
            return false
        }
        return (try? validateSafeTensorsFile(coreModelFileURL)) != nil
    }

    private func isValidVoiceAssetPresent(for locale: VoiceLocale) -> Bool {
        let fileURL = voiceFileURL(for: locale)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return false
        }
        return (try? validateSafeTensorsFile(fileURL)) != nil
    }

    private static func loadPersistedState(from stateFileURL: URL) -> Set<VoiceLocale> {
        guard let data = try? Data(contentsOf: stateFileURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return []
        }
        return Set(state.activatedLocales.compactMap(VoiceLocale.init(rawValue:)))
    }

    private func persistState() {
        let state = PersistedState(activatedLocales: activatedLocales.map(\.rawValue).sorted())
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateFileURL, options: .atomic)
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AssetValidationError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AssetValidationError.invalidStatusCode(httpResponse.statusCode)
        }
    }

    private func validateSafeTensorsFile(_ url: URL) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count >= 16 else {
            throw AssetValidationError.emptyDownload
        }

        let headerLength = data.prefix(8).withUnsafeBytes { rawBuffer -> UInt64 in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return bytes.enumerated().reduce(0) { partialResult, element in
                partialResult | (UInt64(element.element) << (element.offset * 8))
            }
        }

        guard headerLength > 0,
              headerLength <= UInt64(data.count - 8) else {
            throw AssetValidationError.invalidSafeTensorsHeader
        }

        let headerStart = 8
        let headerEnd = headerStart + Int(headerLength)
        let headerData = data.subdata(in: headerStart..<headerEnd)
        guard (try? JSONSerialization.jsonObject(with: headerData)) != nil else {
            throw AssetValidationError.invalidSafeTensorsJSON
        }
    }

    private func removeItemIfPresent(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func voiceFileURL(for locale: VoiceLocale) -> URL {
        assetsDirectory.appendingPathComponent("\(locale.defaultVoiceName).safetensors")
    }

    private func remoteVoiceURL(for locale: VoiceLocale) -> URL {
        URL(string: "https://huggingface.co/mlx-community/Kokoro-82M-4bit/resolve/main/voices/\(locale.defaultVoiceName).safetensors")!
    }

    private func pruneInvalidActivatedLocales() {
        let validLocales = activatedLocales.filter(isValidVoiceAssetPresent(for:))
        if validLocales != activatedLocales {
            activatedLocales = validLocales
            persistState()
        }
    }

    private func notifyObserver() async {
        await statusObserver?(status())
    }
}
