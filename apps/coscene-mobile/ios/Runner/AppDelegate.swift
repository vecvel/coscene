import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let synth = SynthPlayer()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "coscene/audio",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      self?.synth.handle(call, result: result)
    }
  }
}

/// Plays the short sounds that the Dart side synthesises. The app ships no
/// audio files: Dart sends raw 16-bit samples once, and this keeps them in
/// memory and plays them on demand with low latency.
final class SynthPlayer {
  private let engine = AVAudioEngine()
  private var nodes: [AVAudioPlayerNode] = []
  private var buffers: [Int: AVAudioPCMBuffer] = [:]
  private var format: AVAudioFormat?
  private var next = 0

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let id = args["id"] as? Int else {
      result(FlutterError(code: "bad_args", message: "Missing sound id", details: nil))
      return
    }
    switch call.method {
    case "load":
      guard let rate = args["rate"] as? Int, let pcm = args["pcm"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "bad_args", message: "Missing samples", details: nil))
        return
      }
      load(id: id, rate: Double(rate), data: pcm.data)
      result(nil)
    case "play":
      play(id: id, volume: Float(args["volume"] as? Double ?? 1))
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func prepare(rate: Double) -> AVAudioFormat? {
    if let format = format { return format }
    guard
      let made = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)
    else { return nil }
    // Ambient: mixes with the player's music and obeys the silent switch.
    try? AVAudioSession.sharedInstance().setCategory(.ambient)
    for _ in 0..<4 {
      let node = AVAudioPlayerNode()
      engine.attach(node)
      engine.connect(node, to: engine.mainMixerNode, format: made)
      nodes.append(node)
    }
    format = made
    return made
  }

  private func load(id: Int, rate: Double, data: Data) {
    let frames = data.count / 2
    guard frames > 0, let format = prepare(rate: rate),
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
      let channel = buffer.floatChannelData?[0]
    else { return }
    data.withUnsafeBytes { raw in
      let samples = raw.bindMemory(to: Int16.self)
      for i in 0..<frames {
        channel[i] = Float(Int16(littleEndian: samples[i])) / 32768.0
      }
    }
    buffer.frameLength = AVAudioFrameCount(frames)
    buffers[id] = buffer
  }

  private func play(id: Int, volume: Float) {
    guard let buffer = buffers[id], !nodes.isEmpty else { return }
    if !engine.isRunning {
      try? AVAudioSession.sharedInstance().setActive(true)
      do { try engine.start() } catch { return }
    }
    let node = nodes[next]
    next = (next + 1) % nodes.count
    node.stop()
    node.volume = volume
    node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    node.play()
  }
}
