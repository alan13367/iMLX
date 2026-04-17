//
//  Kokoro-tts-lib
//
import Foundation
import MLX
import MLXNN

nonisolated class AlbertLayer {
  let attention: AlbertSelfAttention
  let fullLayerLayerNorm: LayerNorm
  let ffn: Linear
  let ffnOutput: Linear

  init(weights: [String: MLXArray], config: AlbertModelArgs, layerNum: Int, innerGroupNum: Int) {
    attention = AlbertSelfAttention(weights: weights, config: config, layerNum: layerNum, innerGroupNum: innerGroupNum)
    let layerPrefix = "bert.encoder.albert_layer_groups.\(layerNum).albert_layers.\(innerGroupNum)"
    ffn = makeKokoroLinear(
      inputDimensions: config.hiddenSize,
      weight: weights["\(layerPrefix).ffn.weight"]!,
      bias: weights["\(layerPrefix).ffn.bias"]!,
      scales: weights["\(layerPrefix).ffn.scales"],
      quantizedBiases: weights["\(layerPrefix).ffn.biases"]
    )
    ffnOutput = makeKokoroLinear(
      inputDimensions: config.intermediateSize,
      weight: weights["\(layerPrefix).ffn_output.weight"]!,
      bias: weights["\(layerPrefix).ffn_output.bias"]!,
      scales: weights["\(layerPrefix).ffn_output.scales"],
      quantizedBiases: weights["\(layerPrefix).ffn_output.biases"]
    )
    fullLayerLayerNorm = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)

    let fullLayerLayerNormWeights = weights["bert.encoder.albert_layer_groups.\(layerNum).albert_layers.\(innerGroupNum).full_layer_layer_norm.weight"]!
    let fullLayerLayerNormBiases = weights["bert.encoder.albert_layer_groups.\(layerNum).albert_layers.\(innerGroupNum).full_layer_layer_norm.bias"]!

    guard fullLayerLayerNormWeights.count == config.hiddenSize, fullLayerLayerNormBiases.count == config.hiddenSize else {
      fatalError("Wrong shape for AlbertLayer FullLayerLayerNorm bias or weights!")
    }

    for i in 0 ..< config.hiddenSize {
      fullLayerLayerNorm.weight![i] = fullLayerLayerNormWeights[i]
      fullLayerLayerNorm.bias![i] = fullLayerLayerNormBiases[i]
    }
  }

  func ffChunk(_ attentionOutput: MLXArray) -> MLXArray {
    var ffnOutputArray = ffn(attentionOutput)
    ffnOutputArray = MLXNN.gelu(ffnOutputArray)
    ffnOutputArray = ffnOutput(ffnOutputArray)
    return ffnOutputArray
  }

  func callAsFunction(
    _ hiddenStates: MLXArray,
    attentionMask: MLXArray? = nil
  ) -> MLXArray {
    let attentionOutput = attention(hiddenStates, attentionMask: attentionMask)
    let ffnOutput = ffChunk(attentionOutput)
    let output = fullLayerLayerNorm(ffnOutput + attentionOutput)
    return output
  }
}
