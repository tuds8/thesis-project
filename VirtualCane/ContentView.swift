//
//  ContentView.swift
//  VirtualCane
//

import SwiftUI
import AVFoundation

// MARK: – Custom app colours
private extension Color {
    // Light‑mode background
    static let bgLight = Color(red: 0.9686, green: 0.9569, blue: 0.8627)
    // Dark‑mode background
    static let bgDark  = Color(red: 0.133, green: 0.133, blue: 0.133)
}

private struct OutlinedIconToggleStyle: ToggleStyle {
    var tint: Color = .blue

    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            configuration.label
                .font(.title2)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(configuration.isOn ? tint : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(tint, lineWidth: 2)
                )
                .foregroundColor(configuration.isOn ? .white : tint)
        }
        .buttonStyle(.plain)
    }
}

struct ContentView: View {
    // Detect current colour scheme so we can swap backgrounds
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var sessionHandler = ARSessionHandler()

    @State private var showBoxes   = true
    @State private var showDepth   = true
    @State private var showNearest = true   // toggle LiDAR dot visibility
    @State private var isSpeaking  = false  // current TTS state

    private let synthesizer = AVSpeechSynthesizer()
    private var ttsDelegate: TTSDelegate!

    init() {
        let flag = Binding<Bool>(get: { false }, set: { _ in })
        ttsDelegate = TTSDelegate(flag)
        synthesizer.delegate = ttsDelegate
    }

    var body: some View {
        ZStack {
            // Dynamic background that switches between light & dark mode
            (colorScheme == .dark ? Color.bgDark : Color.bgLight)
                .ignoresSafeArea()

            GeometryReader { geo in
                let paddedW = geo.size.width - 10
                let feedH   = paddedW * (4/3)

                ZStack {
                    // camera feed
                    ARViewContainer(sessionHandler: sessionHandler)
                        .frame(width: paddedW, height: feedH)
                        .clipped()

                    // depth overlay
                    if showDepth, let img = sessionHandler.depthImage {
                        Image(decorative: img, scale: 1, orientation: .up)
                            .resizable()
                            .rotationEffect(.degrees(90))
                            .aspectRatio(contentMode: .fill)
                            .frame(width: paddedW, height: feedH)
                            .opacity(0.40)
                            .clipped()
                    }

                    // overlays
                    if showBoxes { BoundingBoxesView(boxes: sessionHandler.detectionBoxes) }
                    if showNearest, let pt = sessionHandler.nearestPoint { NearestPointView(point: pt) }
                }
                .frame(width: paddedW, height: feedH)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(radius: 5)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .edgesIgnoringSafeArea(.all)

            // top toggles
            VStack {
                Spacer().frame(height: 80)
                HStack(spacing: 16) {
                    Toggle(isOn: $showBoxes) { Image(systemName: "rectangle.on.rectangle") }
                        .toggleStyle(OutlinedIconToggleStyle(tint: .blue))
                    Toggle(isOn: $showDepth) { Image(systemName: "map") }
                        .toggleStyle(OutlinedIconToggleStyle(tint: .blue))
                    Toggle(isOn: $showNearest) { Image(systemName: "dot.circle") }
                        .toggleStyle(OutlinedIconToggleStyle(tint: .blue))
                }
                .padding(.horizontal)
                .padding(.top, 10)
                Spacer()
            }
            .edgesIgnoringSafeArea(.top)

            // speak / stop button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        if isSpeaking {
                            synthesizer.stopSpeaking(at: .immediate)
                        } else {
                            speakSnapshot()
                        }
                    } label: {
                        Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.3.fill")
                            .font(.system(size: 24))
                            .padding()
                            .background(isSpeaking ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 120)
                }
            }
            .edgesIgnoringSafeArea(.all)

            // bottom banner
            VStack {
                Spacer()
                DetectionCard(text: sessionHandler.detectionText)
            }
            .edgesIgnoringSafeArea(.bottom)
        }
        .onAppear {
            ttsDelegate.bind($isSpeaking)
        }
    }

    // MARK: – Speak snapshot
    private func speakSnapshot() {
        let boxes = sessionHandler.detectionBoxes
        guard !boxes.isEmpty else { return }

        let phrases = boxes.compactMap { box -> String? in
            guard let d = box.distance else { return nil }
            let dir = direction(for: box.rect)
            let metres = String(format: "%.1f", d)
            return "\(box.label) \(dir) at \(metres) metres"
        }
        guard !phrases.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: phrases.joined(separator: ", "))
        if let naturalVoice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Joelle") {
            utterance.voice = naturalVoice
        }
//        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        synthesizer.speak(utterance)
    }

    private func direction(for rect: CGRect) -> String {
        let cx = rect.midX, cy = rect.midY
        let horiz = cx < 0.33 ? "left" : cx > 0.66 ? "right" : "centre"
        let front = cy > 0.6 ? "front " : ""
        return "\(front)\(horiz)"
    }
}

// MARK: – Delegate keeps @Binding<Bool> in sync with synthesizer state
private class TTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private var flag: Binding<Bool>
    init(_ f: Binding<Bool>) { flag = f }
    func bind(_ f: Binding<Bool>) { flag = f }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart _: AVSpeechUtterance) { flag.wrappedValue = true }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) { flag.wrappedValue = false }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) { flag.wrappedValue = false }
}

// MARK: – Bounding boxes overlay
private struct BoundingBoxesView: View {
    let boxes: [DetectionBox]
    var body: some View {
        GeometryReader { geo in
            ForEach(boxes) { box in
                let rect = CGRect(x: box.rect.minX * geo.size.width,
                                  y: box.rect.minY * geo.size.height,
                                  width:  box.rect.width  * geo.size.width,
                                  height: box.rect.height * geo.size.height)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6).stroke(Color.red, lineWidth: 2)
                    Text(label(for: box))
                        .font(.caption2).bold()
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.75))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
    private func label(for b: DetectionBox) -> String {
        if let d = b.distance { return "\(b.label) – \(String(format: "%.2f m", d))" }
        return b.label
    }
}

// MARK: – Green dot
private struct NearestPointView: View {
    let point: CGPoint
    var body: some View {
        GeometryReader { geo in
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)
                .position(x: point.x * geo.size.width,
                          y: point.y * geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

// MARK: – Detection text card
private struct DetectionCard: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.headline.bold())
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .shadow(radius: 4)
            .padding(.horizontal)
            .padding(.bottom, 60)
    }
}

#Preview {
    Group {
        ContentView().preferredColorScheme(.light)
        ContentView().preferredColorScheme(.dark)
    }
}
