//
//  Kokoro-tts-lib
//
import Foundation
import MLX
import MLXNN

private func inferredQuantization(
  packedWeight: MLXArray,
  scales: MLXArray,
  logicalInputDimensions: Int
) -> (groupSize: Int, bits: Int)? {
  guard packedWeight.shape.count == 2,
        scales.shape.count == 2,
        logicalInputDimensions > 0 else {
    return nil
  }

  let outputDimensions = packedWeight.shape[0]
  let packedInputDimensions = packedWeight.shape[1]
  let groupCount = scales.shape[1]
  let packedBits = packedInputDimensions * 32

  guard scales.shape[0] == outputDimensions,
        groupCount > 0,
        logicalInputDimensions % groupCount == 0,
        packedBits % logicalInputDimensions == 0 else {
    return nil
  }

  let groupSize = logicalInputDimensions / groupCount
  let bits = packedBits / logicalInputDimensions

  guard [2, 3, 4, 5, 6, 8].contains(bits) else {
    return nil
  }

  return (groupSize, bits)
}

func makeKokoroLinear(
  inputDimensions: Int,
  weight: MLXArray,
  bias: MLXArray?,
  scales: MLXArray?,
  quantizedBiases: MLXArray?
) -> Linear {
  guard let scales,
        let (groupSize, bits) = inferredQuantization(
          packedWeight: weight,
          scales: scales,
          logicalInputDimensions: inputDimensions
        ) else {
    return Linear(weight: weight, bias: bias)
  }

  return QuantizedLinear(
    weight: weight,
    bias: bias,
    scales: scales,
    biases: quantizedBiases,
    groupSize: groupSize,
    bits: bits,
    mode: .affine
  )
}

func makeKokoroEmbedding(
  dimensions: Int,
  weight: MLXArray,
  scales: MLXArray?,
  quantizedBiases: MLXArray?
) -> Embedding {
  guard let scales,
        let (groupSize, bits) = inferredQuantization(
          packedWeight: weight,
          scales: scales,
          logicalInputDimensions: dimensions
        ) else {
    return Embedding(weight: weight)
  }

  let dequantizedWeight = MLX.dequantized(
    weight,
    scales: scales,
    biases: quantizedBiases,
    groupSize: groupSize,
    bits: bits,
    mode: .affine
  )

  return Embedding(weight: dequantizedWeight)
}
