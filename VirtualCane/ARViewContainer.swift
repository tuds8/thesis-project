//
//  ARViewContainer.swift
//  VirtualCane
//

import SwiftUI
import ARKit
import RealityKit
import MetalKit

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var sessionHandler: ARSessionHandler

    // Creates and configures the ARView
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Adjust MetalKit view properties for better aspect handling
        for subview in arView.subviews {
            if let mtkView = subview as? MTKView {
                mtkView.contentMode = .scaleAspectFit
                mtkView.layer.contentsGravity = .resizeAspect
            }
        }

        // Assign custom session handler as the AR session delegate
        arView.session.delegate = sessionHandler

        // Configure AR session with scene depth if supported
        let configuration = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        arView.session.run(configuration)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // No updates required after initial setup
    }
}
