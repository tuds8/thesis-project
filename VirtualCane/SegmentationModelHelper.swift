//
//  SegmentationModelHelper.swift
//  VirtualCane
//

import CoreML

extension MLModel {
    // Reads the 'labels' array from the model's metadata (com.apple.coreml.model.preview.params).
    var segmentationLabels: [String] {
        if let metadata = modelDescription.metadata[.creatorDefinedKey] as? [String: Any],
           let params = metadata["com.apple.coreml.model.preview.params"] as? String,
           let data = params.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let labels = parsed["labels"] as? [String] {
            return labels
        }
        return []
    }
}

extension MLShapedArray where Scalar: Hashable & Comparable {
    // Returns all unique values in the shaped array, sorted.
    var uniqueValues: [Scalar] {
        Set(scalars).sorted()
    }
}
