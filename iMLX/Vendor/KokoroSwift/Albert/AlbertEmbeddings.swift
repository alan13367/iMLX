//
//  Kokoro-tts-lib
//
import Foundation
import MLX
import MLXNN

nonisolated class AlbertEmbeddings {
  let wordEmbeddings: Embedding
  let positionEmbeddings: Embedding
  let tokenTypeEmbeddings: Embedding
  let layerNorm: LayerNorm

  init(weights: [String: MLXArray], config: AlbertModelArgs) {
    wordEmbeddings = makeKokoroEmbedding(
      dimensions: config.embeddingSize,
      weight: weights["bert.embeddings.word_embeddings.weight"]!,
      scales: weights["bert.embeddings.word_embeddings.scales"],
      quantizedBiases: weights["bert.embeddings.word_embeddings.biases"]
    )
    positionEmbeddings = makeKokoroEmbedding(
      dimensions: config.embeddingSize,
      weight: weights["bert.embeddings.position_embeddings.weight"]!,
      scales: weights["bert.embeddings.position_embeddings.scales"],
      quantizedBiases: weights["bert.embeddings.position_embeddings.biases"]
    )
    tokenTypeEmbeddings = makeKokoroEmbedding(
      dimensions: config.embeddingSize,
      weight: weights["bert.embeddings.token_type_embeddings.weight"]!,
      scales: weights["bert.embeddings.token_type_embeddings.scales"],
      quantizedBiases: weights["bert.embeddings.token_type_embeddings.biases"]
    )
    layerNorm = LayerNorm(dimensions: config.embeddingSize, eps: config.layerNormEps)
    let layerNormWeights = weights["bert.embeddings.LayerNorm.weight"]!
    let layerNormBiases = weights["bert.embeddings.LayerNorm.bias"]!

    guard layerNormBiases.count == config.embeddingSize, layerNormWeights.count == config.embeddingSize else {
      fatalError("Wrong shape for AlbertEmbeddings LayerNorm bias or weights!")
    }

    for i in 0 ..< layerNormBiases.shape[0] {
      layerNorm.bias![i] = layerNormBiases[i]
      layerNorm.weight![i] = layerNormWeights[i]
    }
  }

  func callAsFunction(
    _ inputIds: MLXArray,
    tokenTypeIds: MLXArray? = nil,
    positionIds: MLXArray? = nil
  ) -> MLXArray {
    let seqLength = inputIds.shape[1]

    let positionIdsUsed: MLXArray
    if let positionIds = positionIds {
      positionIdsUsed = positionIds
    } else {
      positionIdsUsed = MLX.expandedDimensions(MLXArray(0 ..< seqLength), axes: [0])
    }

    let tokenTypeIdsUsed: MLXArray
    if let tokenTypeIds = tokenTypeIds {
      tokenTypeIdsUsed = tokenTypeIds
    } else {
      tokenTypeIdsUsed = MLXArray.zeros(like: inputIds)
    }

    let wordsEmbeddings = wordEmbeddings(inputIds)
    let positionEmbeddingsResult = positionEmbeddings(positionIdsUsed)
    let tokenTypeEmbeddingsResult = tokenTypeEmbeddings(tokenTypeIdsUsed)
    var embeddings = wordsEmbeddings + positionEmbeddingsResult + tokenTypeEmbeddingsResult
    embeddings = layerNorm(embeddings)
    return embeddings
  }
}
