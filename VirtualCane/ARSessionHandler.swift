//
//  ARSessionHandler.swift
//  VirtualCane
//
//  Distance-aware boxes, DETR fallback, depth heat-map overlay.
//

import Foundation
import ARKit
import Vision
import CoreML
import UIKit
import AudioToolbox

// ───────────────────────── Detection overlay
struct DetectionBox: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let distance: Float?        // in metres
    let rect: CGRect            // portrait-normalised
}

// ───────────────────────── Custom class that includes the depth map
class DepthAwareVNCoreMLRequest: VNCoreMLRequest { var capturedDepthMap: CVPixelBuffer? }

// ───────────────────────── Session handler
final class ARSessionHandler: NSObject, ARSessionDelegate, ObservableObject {

    // Battery monitoring
    private var batteryLogTimer: Timer?
    private var initialBatteryLevel: Float?
    private var batteryLog: [(time: String, level: Float)] = []

    // UI
    @Published var detectionText  = ""
    @Published var detectionBoxes = [DetectionBox]()
    @Published var nearestPoint: CGPoint? = nil
    @Published var depthImage:   CGImage? = nil

    // Vision
    private var yoloRequest: DepthAwareVNCoreMLRequest?
    private var detrRequest: DepthAwareVNCoreMLRequest?
    private let visionQueue = DispatchQueue(label: "com.example.visionQueue")

    // Runtime
    private var isProcessingFrame = false
    private var latestDistance: Float?
    private var latestMinPoint: CGPoint?
    private var latestSegMask: MLMultiArray?
    
    // Benchmark
    private var lastFrameTimestamps: [CFTimeInterval] = []
    private let fpsSampleSize = 30
    @Published var currentFPS: Double = 0
    @Published var yoloLatency: Double = 0
    private var yoloStartTime: CFTimeInterval?

    // Copied buffers
    private var rgbCopy:   CVPixelBuffer?
    private var depthCopy: CVPixelBuffer?

    // Misc
    private var lastHaptic: Date = .distantPast
    private var contHapticTimer: Timer?
    private let yoloT: Float = 0.51
    private let segLabels: [String]

    // MARK: – Init
    override init() {
        let detrWrap = try? DETRResnet50SemanticSegmentationF16P8()
        segLabels    = detrWrap?.model.segmentationLabels ?? []
        super.init()
        UIDevice.current.isBatteryMonitoringEnabled = true
        startBatteryLogging()
        setupVision(with: detrWrap)
    }
    
    private func startBatteryLogging() {
        initialBatteryLevel = UIDevice.current.batteryLevel
        guard let initial = initialBatteryLevel, initial > 0 else {
            print("Battery monitoring not available.")
            return
        }

        batteryLogTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            let current = UIDevice.current.batteryLevel
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)

            self.batteryLog.append((timestamp, current))
            print("Battery log at \(timestamp): \(current * 100)%")

            if current <= initial - 0.5 {
                print("Battery dropped 50% — stopping log.")
                self.batteryLogTimer?.invalidate()
                self.batteryLogTimer = nil
                self.exportBatteryLogToCSV()
            }
        }
    }
    
    private func exportBatteryLogToCSV() {
        let fileManager = FileManager.default
        let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let logFile = docDir.appendingPathComponent("battery_log.csv")

        var csvText = "Timestamp,Battery Level (%)\n"
        for entry in batteryLog {
            csvText += "\(entry.time),\(entry.level * 100)\n"
        }

        do {
            try csvText.write(to: logFile, atomically: true, encoding: .utf8)
            print("Battery log saved to \(logFile.path)")
        } catch {
            print("Failed to write battery log: \(error)")
        }
    }

    // MARK: – Vision
    private func setupVision(with detrWrap: DETRResnet50SemanticSegmentationF16P8?) {
        guard let yolo = try? VNCoreMLModel(for: yolo11n().model) else { fatalError("YOLO?") }
        yoloRequest = DepthAwareVNCoreMLRequest(model: yolo, completionHandler: yoloDone)
        yoloRequest?.imageCropAndScaleOption = .scaleFill

        guard let detrWrap,
              let detr = try? VNCoreMLModel(for: detrWrap.model) else { fatalError("DETR?") }
        detrRequest = DepthAwareVNCoreMLRequest(model: detr, completionHandler: detrDone)
        detrRequest?.imageCropAndScaleOption = .scaleFill
    }

    // MARK: – AR delegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = CACurrentMediaTime()
        lastFrameTimestamps.append(now)

        if lastFrameTimestamps.count > fpsSampleSize {
            lastFrameTimestamps.removeFirst()
            let duration = lastFrameTimestamps.last! - lastFrameTimestamps.first!
            let fps = Double(fpsSampleSize - 1) / duration

            DispatchQueue.main.async {
                self.currentFPS = fps
            }
        }
        yoloStartTime = CACurrentMediaTime()
        
        guard !isProcessingFrame else { return }
        isProcessingFrame = true

        rgbCopy   = copyPixelBuffer(frame.capturedImage)
        depthCopy = frame.sceneDepth.flatMap { copyPixelBuffer($0.depthMap) }

        yoloRequest?.capturedDepthMap = depthCopy
        detrRequest?.capturedDepthMap = depthCopy

        guard let rgb = rgbCopy else { cleanUp(); return }
        let h = VNImageRequestHandler(cvPixelBuffer: rgb, orientation: .right)
        visionQueue.async { [weak self] in
            guard let self else { return }
            do { try h.perform([self.yoloRequest!]) } catch { self.cleanUp() }
        }
    }

    // MARK: – YOLO completion
    private func yoloDone(request: VNRequest, error: Error?) {
        let obs = (request.results as? [VNRecognizedObjectObservation] ?? [])
                    .filter { $0.confidence >= yoloT }

        var boxes = [DetectionBox]()
        for o in obs {
            let rect  = portrait(o.boundingBox)
            let label = o.labels.first?.identifier ?? "object"
            let dist  = depthCopy.flatMap { self.avgNearestDepth(in: rect, topN: 20, buf: $0) }
            boxes.append(.init(label: label, confidence: o.confidence,
                               distance: dist, rect: rect))
        }
        if let start = yoloStartTime {
            let end = CACurrentMediaTime()
            let latency = (end - start) * 1000

            DispatchQueue.main.async {
                self.yoloLatency = latency
            }
        }
        DispatchQueue.main.async { self.detectionBoxes = boxes }

        obs.isEmpty ? runDETR() : finishFrame()
    }

    // MARK: – DETR completion
    private func detrDone(request: VNRequest, error: Error?) {
        latestSegMask = request.results?
            .compactMap { $0 as? VNCoreMLFeatureValueObservation }
            .first?.featureValue.multiArrayValue
        finishFrame()
    }

    // MARK: – Frame end
    private func finishFrame() {
        defer { cleanUp() }

        // update heat-map
        if let depth = depthCopy, let img = makeHeatMap(from: depth) {
            DispatchQueue.main.async { self.depthImage = img }
        } else { DispatchQueue.main.async { self.depthImage = nil } }

        // nearest cluster
        guard let dBuf = depthCopy,
              let (d, p) = nearestCluster(in: dBuf) else {
            latestDistance = nil; latestMinPoint = nil
            DispatchQueue.main.async { self.nearestPoint = nil; self.updateBanner() }
            return
        }

        latestDistance = d
        latestMinPoint = p
        triggerHaptics(for: d)

        DispatchQueue.main.async {
            self.nearestPoint = p
            self.updateBanner()
        }
    }

    private func runDETR() {
        guard let rgb = rgbCopy else { finishFrame(); return }
        let h = VNImageRequestHandler(cvPixelBuffer: rgb, orientation: .right)
        visionQueue.async { [weak self] in
            guard let self else { return }
            do { try h.perform([self.detrRequest!]) } catch { self.finishFrame() }
        }
    }

    // MARK: – Depth math --------------------------------------------------

    // Average of the N shallowest depths inside a portrait-normalised rect.
    private func avgNearestDepth(in rect: CGRect, topN: Int, buf: CVPixelBuffer) -> Float? {

        let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf)

        // portrait rect → landscape window
        let x0 = Int(rect.minY * CGFloat(w))
        let x1 = Int(rect.maxY * CGFloat(w))
        let y0 = Int((1 - rect.maxX) * CGFloat(h))
        let y1 = Int((1 - rect.minX) * CGFloat(h))

        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return nil }
        let fp = base.bindMemory(to: Float32.self, capacity: w * h)

        var vals = [Float]()
        for y in max(0,y0)..<min(h,y1) {
            let row = fp + y * w
            for x in max(0,x0)..<min(w,x1) {
                let z = row[x]; if z > 0 { vals.append(z) }
            }
        }
        guard !vals.isEmpty else { return nil }

        vals.sort()
        let k = min(topN, vals.count)
        return vals.prefix(k).reduce(0,+) / Float(k)
    }

    // Nearest-surface cluster (≤ min+3 cm) → (median depth, portrait centroid)
    private func nearestCluster(in buf: CVPixelBuffer) -> (Float, CGPoint)? {

        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buf) else { return nil }
        let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf)
        let fp = base.bindMemory(to: Float32.self, capacity: w * h)

        // global minimum
        var minZ = Float.greatestFiniteMagnitude
        for i in 0..<(w*h) { let z = fp[i]; if z > 0 && z < minZ { minZ = z } }
        guard minZ < .greatestFiniteMagnitude else { return nil }

        // collect pixels ≤ min+3 cm
        let thr = minZ + 0.03
        var xs = [Int](), ys = [Int](), zs = [Float]()
        for y in 0..<h {
            for x in 0..<w {
                let z = fp[y*w+x]
                if z > 0 && z <= thr { xs.append(x); ys.append(y); zs.append(z) }
            }
        }
        guard !zs.isEmpty else { return nil }

        // median depth & centroid (landscape coords)
        let medZ = zs.sorted()[zs.count/2]
        let cx = xs.reduce(0,+) / xs.count
        let cy = ys.reduce(0,+) / ys.count

        // landscape → portrait mapping
        let px = 1 - CGFloat(cy) / CGFloat(h)   // portrait X
        let py =      CGFloat(cx) / CGFloat(w)  // portrait Y
        return (medZ, CGPoint(x: px, y: py))
    }

    // MARK: – Heat-map render
    private func makeHeatMap(from buf: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }

        let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf)
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return nil }
        let fp = base.bindMemory(to: Float32.self, capacity: w*h)

        // RGBA 8888 out
        var rgba = [UInt8](repeating: 0, count: w*h*4)
        for i in 0..<(w*h) {
            let d = fp[i]
            // Map 0-4 m → 1-0  (near=1)
            let n = max(0, min(1, (4 - (d.isFinite && d>0 ? d : 4)) / 4))
            let (r,g,b) = heatColor(norm: n)
            rgba[i*4] = r; rgba[i*4+1] = g; rgba[i*4+2] = b; rgba[i*4+3] = 180
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        return rgba.withUnsafeBufferPointer {
            CGDataProvider(data: Data(buffer: $0) as CFData)
                .flatMap { CGImage(width: w, height: h, bitsPerComponent: 8,
                                   bitsPerPixel: 32, bytesPerRow: w*4,
                                   space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent) }
        }
    }

    private func heatColor(norm n: Float) -> (UInt8,UInt8,UInt8) {
        // simple blue→cyan→green→yellow→red gradient
        let x = max(0,min(1,n))
        switch x {
        case ..<0.25: // blue→cyan
            let t = x/0.25
            return (0, UInt8(255*t), 255)
        case ..<0.5:  // cyan→green
            let t = (x-0.25)/0.25
            return (0, 255, UInt8(255*(1-t)))
        case ..<0.75: // green→yellow
            let t = (x-0.5)/0.25
            return (UInt8(255*t), 255, 0)
        default:      // yellow→red
            let t = (x-0.75)/0.25
            return (255, UInt8(255*(1-t)), 0)
        }
    }

    // MARK: – Banner etc.
    private func updateBanner() {
        var label: String?
        var source: String?

        if let p = latestMinPoint {
            // 1. Try YOLO boxes
            if let box = detectionBoxes.first(where: { $0.rect.contains(p) }) {
                label  = box.label
                source = "YOLO detected"
            }
            // 2. Try DETR mask
            if label == nil,
               let mask = latestSegMask,
               let segLab = segLabel(at: p, in: mask) {
                label  = segLab
                source = "DETR"
            }
        }

        if let dist = latestDistance {
            if let lbl = label, let src = source {
                detectionText = "\(src) \(lbl) – \(String(format: "%.2f m", dist))"
            } else {
                detectionText = "Obstacle – \(String(format: "%.2f m", dist))"
            }
        } else {
            if let lbl = label, let src = source {
                detectionText = "\(src) \(lbl)"
            } else {
                detectionText = "Obstacle"
            }
        }
    }

    private func segLabel(at pt: CGPoint, in m: MLMultiArray) -> String? {
        let dims = m.shape.map { $0.intValue }; guard dims.count==2||dims.count==3 else { return nil }
        let h = dims[dims.count-2], w = dims[dims.count-1]
        var ix = Int(pt.x*CGFloat(w)), iy = Int((1-pt.y)*CGFloat(h))
        ix = min(max(ix,0),w-1); iy = min(max(iy,0),h-1)
        let idx = iy*w+ix; guard idx<m.count else { return nil }
        let l = m[idx].intValue; return l<segLabels.count ? segLabels[l] : nil
    }

    // MARK: – Memory utils
    private func copyPixelBuffer(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(src, .readOnly); defer { CVPixelBufferUnlockBaseAddress(src, .readOnly) }

        let w = CVPixelBufferGetWidth(src), h = CVPixelBufferGetHeight(src)
        let fmt = CVPixelBufferGetPixelFormatType(src), planes = CVPixelBufferGetPlaneCount(src)
        var dst: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, fmt, nil, &dst) == kCVReturnSuccess,
              let copy = dst else { return nil }

        CVPixelBufferLockBaseAddress(copy, []); defer { CVPixelBufferUnlockBaseAddress(copy, []) }

        if planes == 0 {
            if let s = CVPixelBufferGetBaseAddress(src),
               let d = CVPixelBufferGetBaseAddress(copy) {
                memcpy(d, s, CVPixelBufferGetBytesPerRow(src)*h)
            }
        } else {
            for p in 0..<planes {
                if let s = CVPixelBufferGetBaseAddressOfPlane(src, p),
                   let d = CVPixelBufferGetBaseAddressOfPlane(copy, p) {
                    let br = CVPixelBufferGetBytesPerRowOfPlane(src, p)
                    memcpy(d, s, CVPixelBufferGetHeightOfPlane(src, p)*br)
                }
            }
        }
        return copy
    }

    private func cleanUp() {
        isProcessingFrame = false
        yoloRequest?.capturedDepthMap = nil
        detrRequest?.capturedDepthMap = nil
        rgbCopy = nil; depthCopy = nil
    }

    // MARK: – Haptics
    // Gives the user tactile feedback on 4 levels of intensity based on the nearest-surface distance
    // 1. < 0.20 m       →  repeating heavy impacts + alert sound
    // 2. 0.20 – 0.49 m  →  single heavy impact
    // 3. 0.50 – 0.99 m  →  single light impact
    // 4. ≥ 1.0 m        →  no haptics
    private func triggerHaptics(for distance: Float) {

        DispatchQueue.main.async {
            // throttle to at most once every 0.5 s
            let now = Date()
            guard now.timeIntervalSince(self.lastHaptic) >= 0.5 else { return }
            self.lastHaptic = now

            // stop any previous repeating pattern
            self.contHapticTimer?.invalidate()
            self.contHapticTimer = nil

            func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
                let g = UIImpactFeedbackGenerator(style: style)
                g.prepare(); g.impactOccurred()
            }

            switch distance {
            case ..<0.20:
                impact(.heavy)
                AudioServicesPlaySystemSound(1005)         // short “ding” sound
                // repeat heavy impacts every 0.5 s while the user is very close
                self.contHapticTimer = Timer.scheduledTimer(withTimeInterval: 0.5,
                                                            repeats: true) { _ in impact(.heavy) }

            case ..<0.50:
                impact(.heavy)

            case ..<1.0:
                impact(.light)

            default: break
            }
        }
    }

    private func portrait(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: 1-r.maxY, width: r.width, height: r.height) }

}
