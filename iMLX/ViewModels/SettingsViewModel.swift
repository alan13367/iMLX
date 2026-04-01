import Foundation

@Observable
final class SettingsViewModel {
    var maxTokens: Int {
        didSet { UserDefaults.standard.set(maxTokens, forKey: "maxTokens") }
    }
    var temperature: Double {
        didSet { UserDefaults.standard.set(temperature, forKey: "temperature") }
    }
    var topP: Double {
        didSet { UserDefaults.standard.set(topP, forKey: "topP") }
    }
    var repetitionPenalty: Double {
        didSet { UserDefaults.standard.set(repetitionPenalty, forKey: "repetitionPenalty") }
    }
    var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "systemPrompt") }
    }

    let deviceCapability = DeviceCapabilityService()

    init() {
        let defaults = UserDefaults.standard
        self.maxTokens = defaults.object(forKey: "maxTokens") != nil
            ? defaults.integer(forKey: "maxTokens")
            : Constants.Generation.defaultMaxTokens
        self.temperature = defaults.object(forKey: "temperature") != nil
            ? defaults.double(forKey: "temperature")
            : Double(Constants.Generation.defaultTemperature)
        self.topP = defaults.object(forKey: "topP") != nil
            ? defaults.double(forKey: "topP")
            : Double(Constants.Generation.defaultTopP)
        self.repetitionPenalty = defaults.object(forKey: "repetitionPenalty") != nil
            ? defaults.double(forKey: "repetitionPenalty")
            : Double(Constants.Generation.defaultRepetitionPenalty)
        self.systemPrompt = defaults.string(forKey: "systemPrompt") ?? ""
    }

    func resetToDefaults() {
        maxTokens = Constants.Generation.defaultMaxTokens
        temperature = Double(Constants.Generation.defaultTemperature)
        topP = Double(Constants.Generation.defaultTopP)
        repetitionPenalty = Double(Constants.Generation.defaultRepetitionPenalty)
        systemPrompt = ""
        Haptics.impactMedium()
    }

    var totalStorageUsedGB: Double {
        let manifestService = ManifestService()
        let totalBytes = manifestService.getDownloadedModels().reduce(Int64(0)) { $0 + $1.sizeOnDiskBytes }
        return Double(totalBytes) / (1024 * 1024 * 1024)
    }
}
