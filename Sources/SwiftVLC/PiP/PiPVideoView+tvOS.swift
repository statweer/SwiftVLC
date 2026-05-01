#if os(tvOS)
import AVFoundation
import SwiftUI
import UIKit

/// A SwiftUI view that renders video via `AVSampleBufferDisplayLayer`
/// and exposes Picture in Picture controls on tvOS.
public struct PiPVideoView: UIViewRepresentable {
  private let player: Player
  private let controllerBinding: Binding<PiPController?>?
  private let startsAutomaticallyFromInline: Bool
  private let managesAudioSession: Bool

  public init(
    _ player: Player,
    controller: Binding<PiPController?>? = nil,
    startsAutomaticallyFromInline: Bool = true,
    managesAudioSession: Bool = true
  ) {
    self.player = player
    controllerBinding = controller
    self.startsAutomaticallyFromInline = startsAutomaticallyFromInline
    self.managesAudioSession = managesAudioSession
  }

  public func makeUIView(context: Context) -> UIView {
    let controller = makeController(for: player)
    let container = TVOSSampleBufferVideoView(displayLayer: controller.layer)
    container.setAuxiliaryLayer(controller.auxiliaryLayer)

    context.coordinator.pipController = controller
    context.coordinator.player = player
    pushControllerBinding(controller, via: context.coordinator)

    return container
  }

  public func updateUIView(_ uiView: UIView, context: Context) {
    guard let container = uiView as? TVOSSampleBufferVideoView else { return }
    if context.coordinator.player !== player {
      let controller = makeController(for: player)
      container.setDisplayLayer(controller.layer)
      container.setAuxiliaryLayer(controller.auxiliaryLayer)
      context.coordinator.player = player
      context.coordinator.pipController = controller
    }

    container.setAuxiliaryLayer(context.coordinator.pipController?.auxiliaryLayer)
    pushControllerBinding(context.coordinator.pipController, via: context.coordinator)
  }

  public static func dismantleUIView(_: UIView, coordinator: Coordinator) {
    coordinator.pipController?.stop()
    coordinator.pipController = nil
    if let binding = coordinator.controllerBinding {
      Task { @MainActor in binding.wrappedValue = nil }
      coordinator.controllerBinding = nil
    }
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  @MainActor
  public final class Coordinator {
    weak var player: Player?
    var pipController: PiPController?
    var controllerBinding: Binding<PiPController?>?
  }

  @MainActor
  private func pushControllerBinding(_ controller: PiPController?, via coordinator: Coordinator) {
    let binding = controllerBinding
    coordinator.controllerBinding = binding
    Task { @MainActor in
      binding?.wrappedValue = controller
    }
  }

  private func makeController(for player: Player) -> PiPController {
    PiPController(
      player: player,
      playbackDriver: .live(player: player),
      pauseDebounce: .milliseconds(250),
      startsAutomaticallyFromInline: startsAutomaticallyFromInline,
      managesAudioSession: managesAudioSession
    )
  }
}

private final class TVOSSampleBufferVideoView: UIView {
  private var displayLayer: AVSampleBufferDisplayLayer?
  private var auxiliaryLayer: CALayer?

  init(displayLayer: AVSampleBufferDisplayLayer) {
    super.init(frame: .zero)
    backgroundColor = .black
    clipsToBounds = true
    setDisplayLayer(displayLayer)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }

  func setDisplayLayer(_ displayLayer: AVSampleBufferDisplayLayer) {
    guard self.displayLayer !== displayLayer else { return }
    self.displayLayer?.removeFromSuperlayer()
    self.displayLayer = displayLayer
    layer.addSublayer(displayLayer)
    if let auxiliaryLayer {
      layer.insertSublayer(auxiliaryLayer, below: displayLayer)
    }
    setNeedsLayout()
  }

  func setAuxiliaryLayer(_ auxiliaryLayer: CALayer?) {
    guard self.auxiliaryLayer !== auxiliaryLayer else { return }
    self.auxiliaryLayer?.removeFromSuperlayer()
    self.auxiliaryLayer = auxiliaryLayer
    guard let auxiliaryLayer else { return }
    if let displayLayer {
      layer.insertSublayer(auxiliaryLayer, below: displayLayer)
    } else {
      layer.addSublayer(auxiliaryLayer)
    }
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    auxiliaryLayer?.frame = bounds
    displayLayer?.frame = bounds
    CATransaction.commit()
  }
}
#endif
