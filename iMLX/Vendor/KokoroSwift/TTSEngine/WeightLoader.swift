//
//  Kokoro-tts-lib
//
import Foundation
import MLX
import MLXNN

/// Utility class for loading and preprocessing neural network weights.
///
/// WeightLoader handles the loading of model weights from disk and applies necessary
/// transformations to ensure compatibility with the model architecture. This includes:
/// - Filtering out unnecessary weights (e.g., position_ids)
/// - Transposing weight tensors for specific layers
/// - Validating and processing weight shapes
///
/// The class processes weights for different model components:
/// - BERT encoder weights
/// - Predictor (duration and prosody) weights
/// - Text encoder weights
/// - Decoder weights
nonisolated final class WeightLoader {
  /// WeightLoader is a utility class with only static methods.
  private init() {}

  /// Loads and sanitizes model weights from the specified path.
  /// This method reads the raw model weights and applies component-specific transformations:
  /// - **BERT weights**: Filters out position_ids (not needed for inference)
  /// - **Predictor weights**: Transposes F0 and N projection weights, handles weight_v conditionally
  /// - **Text encoder weights**: Handles weight_v with conditional transposition
  /// - **Decoder weights**: Transposes noise convolution weights and handles weight_v conditionally
  /// - Parameter modelPath: URL to the directory containing model weight files
  /// - Returns: Dictionary mapping weight names to their processed MLXArray tensors
  /// - Note: Uses forced try (try!) as weight loading is critical and should fail fast if unsuccessful
  static func loadWeights(modelPath: URL) -> [String: MLXArray] {
    // Load raw weights from disk
    let weights = try! MLX.loadArrays(url: modelPath)
    var sanitizedWeights: [String: MLXArray] = [:]

    // Process each weight based on its component prefix
    for (key, value) in weights {
      // Process BERT encoder weights
      if key.hasPrefix("bert") {
        // Skip position_ids as they're not needed for inference
        if key.contains("position_ids") {
          continue
        }
        sanitizedWeights[key] = value
        
      // Process predictor (duration and prosody) weights
      } else if key.hasPrefix("predictor") {
        // Current Kokoro checkpoints already store conv1d weights as [out, kernel, in].
        if key.contains("F0_proj.weight") {
          sanitizedWeights[key] = value
          
        // Current Kokoro checkpoints already store conv1d weights as [out, kernel, in].
        } else if key.contains("N_proj.weight") {
          sanitizedWeights[key] = value
          
        // Current Kokoro checkpoints already store conv1d weight_v as [out, kernel, in].
        // Transposing these tensors turns the kernel axis into a channel axis and
        // later crashes MLX conv with weights like [3, 512, 512].
        } else if key.contains("weight_v") {
          sanitizedWeights[key] = value
        } else {
          sanitizedWeights[key] = value
        }
        
      // Process text encoder weights
      } else if key.hasPrefix("text_encoder") {
        // Current Kokoro checkpoints already store conv1d weight_v as [out, kernel, in].
        if key.contains("weight_v") {
          sanitizedWeights[key] = value
        } else {
          sanitizedWeights[key] = value
        }
        
      // Process decoder weights
      } else if key.hasPrefix("decoder") {
        // Current Kokoro checkpoints already store conv1d weights as [out, kernel, in].
        if key.contains("noise_convs"), key.hasSuffix(".weight") {
          sanitizedWeights[key] = value
          
        // Current Kokoro checkpoints already store conv1d/transposed-conv weight_v as
        // [out, kernel, in] or [out, kernel, groups]. Keep them in place.
        } else if key.contains("weight_v") {
          sanitizedWeights[key] = value
        } else {
          sanitizedWeights[key] = value
        }
      }
    }

    addCompatibilityAliases(to: &sanitizedWeights)

    return sanitizedWeights
  }
  private static func addCompatibilityAliases(to weights: inout [String: MLXArray]) {
    let lstmSuffixAliases = [
      ".Wx_forward": ".weight_ih_l0",
      ".Wh_forward": ".weight_hh_l0",
      ".bias_ih_forward": ".bias_ih_l0",
      ".bias_hh_forward": ".bias_hh_l0",
      ".Wx_backward": ".weight_ih_l0_reverse",
      ".Wh_backward": ".weight_hh_l0_reverse",
      ".bias_ih_backward": ".bias_ih_l0_reverse",
      ".bias_hh_backward": ".bias_hh_l0_reverse",
    ]

    for (sourceSuffix, aliasSuffix) in lstmSuffixAliases {
      let matchingKeys = weights.keys.filter { $0.hasSuffix(sourceSuffix) }
      for key in matchingKeys {
        let aliasKey = String(key.dropLast(sourceSuffix.count)) + aliasSuffix
        if weights[aliasKey] == nil, let value = weights[key] {
          weights[aliasKey] = value
        }
      }
    }

    let layerNormAliases = [
      ".weight": ".gamma",
      ".bias": ".beta",
    ]

    let layerNormKeys = weights.keys.filter { key in
      key.contains(".cnn.") && key.contains(".1.")
    }
    for key in layerNormKeys {
      for (sourceSuffix, aliasSuffix) in layerNormAliases where key.hasSuffix(sourceSuffix) {
        let aliasKey = String(key.dropLast(sourceSuffix.count)) + aliasSuffix
        if weights[aliasKey] == nil, let value = weights[key] {
          weights[aliasKey] = value
        }
      }
    }
  }
}
