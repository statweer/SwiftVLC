#if os(tvOS)
import AVFoundation
import AVKit

@MainActor
final class TVOSPiPBridge: NSObject {
  weak var owner: PiPController?

  let playerLayer: AVPlayerLayer

  private let playerItem: AVPlayerItem
  private let avPlayer: AVPlayer
  private var shouldResumeVLCWhenPiPStops = false
  private var possibleObservation: NSKeyValueObservation?
  private var activeObservation: NSKeyValueObservation?
  private var readyObservation: NSKeyValueObservation?

  private var pipController: AVPictureInPictureController?

  var isPossible: Bool {
    pipController?.isPictureInPicturePossible ?? false
  }

  var isActive: Bool {
    pipController?.isPictureInPictureActive ?? false
  }

  init(owner: PiPController, url: URL) {
    self.owner = owner

    playerItem = AVPlayerItem(url: url)
    playerItem.preferredForwardBufferDuration = 0
    avPlayer = AVPlayer(playerItem: playerItem)
    avPlayer.automaticallyWaitsToMinimizeStalling = true
    avPlayer.isMuted = true

    playerLayer = AVPlayerLayer(player: avPlayer)
    playerLayer.videoGravity = .resizeAspect

    super.init()

    configurePictureInPictureController()
    observePlayerReadiness()
    startMutedEligibilityPlayback()
  }

  deinit {
    possibleObservation?.invalidate()
    activeObservation?.invalidate()
    readyObservation?.invalidate()
    avPlayer.pause()
    avPlayer.replaceCurrentItem(with: nil)
  }

  func start(from currentTime: Duration, vlcWasPlaying: Bool) {
    shouldResumeVLCWhenPiPStops = vlcWasPlaying
    syncToVLCPlaybackPosition(currentTime)

    avPlayer.isMuted = false
    avPlayer.play()

    pipController?.startPictureInPicture()
  }

  func stop() {
    pipController?.stopPictureInPicture()
  }

  private func configurePictureInPictureController() {
    guard AVPictureInPictureController.isPictureInPictureSupported() else {
      return
    }

    guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
      return
    }

    controller.delegate = self
    pipController = controller

    possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) {
      [weak self] _, _
      in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.owner?.handleTVOSBridgeStateChanged()
      }
    }

    activeObservation = controller.observe(\.isPictureInPictureActive, options: [.initial, .new]) {
      [weak self] _, _
      in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.owner?.handleTVOSBridgeStateChanged()
      }
    }
  }

  private func observePlayerReadiness() {
    readyObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if item.status == .readyToPlay {
          self.owner?.handleTVOSBridgeStateChanged()
        }
      }
    }
  }

  private func startMutedEligibilityPlayback() {
    avPlayer.isMuted = true
    avPlayer.play()
  }

  private func syncToVLCPlaybackPosition(_ currentTime: Duration) {
    let seconds = durationSeconds(currentTime)
    guard seconds.isFinite, seconds > 0 else { return }

    let target = CMTime(seconds: seconds, preferredTimescale: 600)
    avPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
  }

  private func durationSeconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }

}

extension TVOSPiPBridge: AVPictureInPictureControllerDelegate {
  nonisolated func pictureInPictureControllerWillStartPictureInPicture(
    _: AVPictureInPictureController
  ) {}

  nonisolated func pictureInPictureControllerDidStartPictureInPicture(
    _: AVPictureInPictureController
  ) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.owner?.handleTVOSBridgeDidStart()
    }
  }

  nonisolated func pictureInPictureControllerDidStopPictureInPicture(
    _: AVPictureInPictureController
  ) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      let currentTime = self.avPlayer.currentTime()
      let seconds = currentTime.isNumeric && currentTime.seconds.isFinite ? currentTime.seconds : nil

      self.avPlayer.isMuted = true
      self.avPlayer.pause()
      self.owner?.handleTVOSBridgeDidStop(
        at: seconds,
        shouldResumeVLC: self.shouldResumeVLCWhenPiPStops
      )
    }
  }

  nonisolated func pictureInPictureController(
    _: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    let completion = TVOSPiPRestoreCompletion(handler: completionHandler)

    Task { @MainActor [weak self] in
      guard let owner = self?.owner else {
        completion(false)
        return
      }

      owner.handleTVOSBridgeRestoreRequested { result in
        completion(result)
      }
    }
  }

  nonisolated func pictureInPictureController(
    _: AVPictureInPictureController,
    failedToStartPictureInPictureWithError _: Error
  ) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.avPlayer.isMuted = true
      self.owner?.handleTVOSBridgeDidStop(at: nil, shouldResumeVLC: self.shouldResumeVLCWhenPiPStops)
    }
  }
}

private struct TVOSPiPRestoreCompletion: @unchecked Sendable {
  let handler: (Bool) -> Void

  func callAsFunction(_ result: Bool) {
    handler(result)
  }
}
#endif
