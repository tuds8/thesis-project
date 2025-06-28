//
//  CoreImageExtensions.swift
//  VirtualCane
//

import CoreImage
import ImageIO
import UniformTypeIdentifiers

extension CIImage {
    /// Resizes the image to the specified size.
    func resized(to size: CGSize) -> CIImage {
        let scaleX = size.width / extent.width
        let scaleY = size.height / extent.height
        var output = self.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        output = output.transformed(by: CGAffineTransform(translationX: -output.extent.origin.x,
                                                           y: -output.extent.origin.y))
        return output
    }
}

extension CIContext {
    /// Renders a CIImage into a new CVPixelBuffer with the given pixel format.
    func render(_ image: CIImage, pixelFormat: OSType) -> CVPixelBuffer? {
        var output: CVPixelBuffer!
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(image.extent.width),
                                         Int(image.extent.height),
                                         pixelFormat,
                                         nil,
                                         &output)
        guard status == kCVReturnSuccess else { return nil }
        render(image, to: output)
        return output
    }
}
