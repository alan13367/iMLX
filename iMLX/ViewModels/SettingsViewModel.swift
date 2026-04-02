import Foundation

@Observable
final class SettingsViewModel {
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
        temperature = Double(Constants.Generation.defaultTemperature)
        topP = Double(Constants.Generation.defaultTopP)
        repetitionPenalty = Double(Constants.Generation.defaultRepetitionPenalty)
        systemPrompt = ""
        UserDefaults.standard.removeObject(forKey: "maxTokens")
        Haptics.impactMedium()
    }

    var totalStorageUsedGB: Double {
        let manifestService = ManifestService()
        let totalBytes = manifestService.getDownloadedModels().reduce(Int64(0)) { $0 + $1.sizeOnDiskBytes }
        return Double(totalBytes) / (1024 * 1024 * 1024)
    }

    var temperatureDescription: String {
        switch temperature {
        case ..<0.3:
            "More focused and predictable"
        case ..<0.9:
            "Balanced between stable and creative"
        case ..<1.4:
            "More varied and exploratory"
        default:
            "Very loose and unpredictable"
        }
    }

    var topPDescription: String {
        switch topP {
        case ..<0.5:
            "Keeps only the safest token choices"
        case ..<0.85:
            "Allows some variety without drifting too far"
        default:
            "Lets the model consider a broad set of options"
        }
    }

    var repetitionPenaltyDescription: String {
        switch repetitionPenalty {
        case ..<1.05:
            "Almost no repetition control"
        case ..<1.25:
            "Gently discourages loops and repeated phrases"
        default:
            "Strongly pushes the model away from repetition"
        }
    }
}
