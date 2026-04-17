//
//  Kokoro-tts-lib
//
import Foundation
import MLX
import MLXNN

nonisolated class AlbertSelfAttention {
  let numAttentionHeads: Int
  let attentionHeadSize: Int
  let allHeadSize: Int

  let query: Linear
  let key: Linear
  let value: Linear
  let dense: Linear
  let layerNorm: LayerNorm

  init(weights: [String: MLXArray], config: AlbertModelArgs, layerNum: Int, innerGroupNum: Int) {
    numAttentionHeads = config.numAttentionHeads
    attentionHeadSize = config.hiddenSize / config.numAttentionHeads
    allHeadSize = numAttentionHeads * attentionHeadSize

    let attentionPrefix = "bert.encoder.albert_layer_groups.\(layerNum).albert_layers.\(innerGroupNum).attention"
    query = makeKokoroLinear(
      inputDimensions: config.hiddenSize,
      weight: weights["\(attentionPrefix).query.weight"]!,
      bias: weights["\(attentionPrefix).query.bias"]!,
      scales: weights["\(attentionPrefix).query.scales"],
      quantizedBiases: weights["\(attentionPrefix).query.biases"]
    )
    key = makeKokoroLinear(
      inputDimensions: config.hiddenSize,
      weight: weights["\(attentionPrefix).key.weight"]!,
      bias: weights["\(attentionPrefix).key.bias"]!,
      scales: weights["\(attentionPrefix).key.scales"],
      quantizedBiases: weights["\(attentionPrefix).key.biases"]
    )
    value = makeKokoroLinear(
      inputDimensions: config.hiddenSize,
      weight: weights["\(attentionPrefix).value.weight"]!,
      bias: weights["\(attentionPrefix).value.bias"],
      scales: weights["\(attentionPrefix).value.scales"],
      quantizedBiases: weights["\(attentionPrefix).value.biases"]
    )
    dense = makeKokoroLinear(
      inputDimensions: config.hiddenSize,
      weight: weights["\(attentionPrefix).dense.weight"]!,
      bias: weights["\(attentionPrefix).dense.bias"]!,
      scales: weights["\(attentionPrefix).dense.scales"],
      quantizedBiases: weights["\(attentionPrefix).dense.biases"]
    )

    layerNorm = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)

    let layerNormWeights = weights["bert.encoder.albert_layer_groups.\(layerNum).albert_layers.\(innerGroupNum).attention.LayerNorm.weight"]!
    let layerNormBiases = weights["bert.encoder.albert_layer_groups.\(layerNum).albert_layers.\(innerGroupNum).attention.LayerNorm.bias"]!

    guard layerNormWeights.count == config.hiddenSize, layerNormBiases.count == config.hiddenSize else {
      fatalError("Wrong shape for AlbertSelfAttention LayerNorm bias or weights!")
    }

    for i in 0 ..< layerNormBiases.shape[0] {
      layerNorm.bias![i] = layerNormBiases[i]
      layerNorm.weight![i] = layerNormWeights[i]
    }
  }

  func transposeForScores(_ x: MLXArray) -> MLXArray {
    let shape = x.shape
    var newShape: [Int] = []

    for i in 0 ..< (shape.count - 1) {
      newShape.append(shape[i])
    }

    newShape.append(numAttentionHeads)
    newShape.append(attentionHeadSize)

    let reshaped = x.reshaped(newShape)
    return reshaped.transposed(0, 2, 1, 3)
  }

  func callAsFunction(
    _ hiddenStates: MLXArray,
    attentionMask: MLXArray? = nil
  ) -> MLXArray {
    let mixedQueryLayer = query(hiddenStates)
    let mixedKeyLayer = key(hiddenStates)
    let mixedValueLayer = value(hiddenStates)

    let queryLayer = transposeForScores(mixedQueryLayer)
    let keyLayer = transposeForScores(mixedKeyLayer)
    let valueLayer = transposeForScores(mixedValueLayer)

    let keyLayerTransposed = keyLayer.transposed(0, 1, 3, 2)
    var attentionScores = MLX.matmul(queryLayer, keyLayerTransposed)
    attentionScores = attentionScores / sqrt(Float(attentionHeadSize))

    if let attentionMask = attentionMask {
      attentionScores = attentionScores + attentionMask
    }

    let attentionProbs = MLX.softmax(attentionScores, axis: -1)

    var contextLayer = MLX.matmul(attentionProbs, valueLayer)
    contextLayer = contextLayer.transposed(0, 2, 1, 3)

    var newContextLayerShape: [Int] = []
    let shape = contextLayer.shape

    for i in 0 ..< (shape.count - 2) {
      newContextLayerShape.append(shape[i])
    }

    newContextLayerShape.append(allHeadSize)

    contextLayer = contextLayer.reshaped(newContextLayerShape)
    contextLayer = dense(contextLayer)
    contextLayer = layerNorm(contextLayer + hiddenStates)

    return contextLayer
  }
}
