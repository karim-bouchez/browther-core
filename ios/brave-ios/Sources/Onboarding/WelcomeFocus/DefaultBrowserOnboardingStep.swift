// Copyright (c) 2025 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import AVFoundation
import AVKit
import BrowtherAnalytics
import DesignSystem
import SwiftUI

// Browther: les .lottie d'origine (browser-default-{light,dark}.lottie) montraient
// le logo Brave. Remplacés par un AVPlayer qui boucle le même MP4 que la PiP
// (set-default-pip-*.mp4) → un seul enregistrement à recréer pour Lottie + PiP.
struct DefaultBrowserGraphicView: View {
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    LoopingMutedVideoPlayer(
      videoName: colorScheme == .dark ? "set-default-pip-dark" : "set-default-pip-light"
    )
    .id(colorScheme)
  }
}

@MainActor
private struct LoopingMutedVideoPlayer: UIViewControllerRepresentable {
  let videoName: String

  func makeUIViewController(context: Context) -> AVPlayerViewController {
    let controller = AVPlayerViewController()
    controller.showsPlaybackControls = false
    controller.videoGravity = .resizeAspect
    controller.view.backgroundColor = .clear

    guard let url = Bundle.module.url(
      forResource: videoName,
      withExtension: "mp4",
      subdirectory: "Videos"
    ) else { return controller }

    let item = AVPlayerItem(url: url)
    let player = AVQueuePlayer()
    let looper = AVPlayerLooper(player: player, templateItem: item)
    context.coordinator.looper = looper
    player.isMuted = true
    player.actionAtItemEnd = .none
    controller.player = player
    player.play()

    return controller
  }

  func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator() }

  @MainActor
  final class Coordinator {
    var looper: AVPlayerLooper?
  }
}

@MainActor
private final class DefaultBrowserPictureInPictureController: NSObject,
  AVPictureInPictureControllerDelegate
{
  private let player: AVPlayer
  private let playerLayer: AVPlayerLayer
  private let controller: AVPictureInPictureController?
  private let windowScene: UIWindowScene
  private let containerView: UIView = .init()
  private let onStop: () -> Void
  private var didPlayToEndTime: NSObjectProtocol?
  private var didBecomeActive: NSObjectProtocol?

  init(
    videoURL: URL,
    windowScene: UIWindowScene,
    onStop: @escaping () -> Void
  ) {
    #if DEBUG
    assert(videoURL.isFileURL, "Video must be local")
    assert(FileManager.default.fileExists(atPath: videoURL.path))
    #endif
    self.windowScene = windowScene
    self.player = AVPlayer(playerItem: .init(asset: AVURLAsset(url: videoURL)))
    self.playerLayer = AVPlayerLayer(player: self.player)
    self.controller = AVPictureInPictureController(playerLayer: self.playerLayer)
    self.onStop = onStop
  }

  deinit {
    // On iOS 18 there is a bug where the AVPictureInPictureController crashes on dealloc
    // due to a some internal KVO executing off main. This is a blind fix hoping that keeping
    // the controller around for an extra second will ensure it deallocs off main
    if #available(iOS 18, *) {
      let controller = self.controller as AnyObject
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        _ = controller
      }
    }
  }

  func start() async {
    guard let item = player.currentItem, let controller else { return }

    Task.detached {
      try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try? AVAudioSession.sharedInstance().setActive(true)
    }

    player.actionAtItemEnd = .none
    player.automaticallyWaitsToMinimizeStalling = false
    playerLayer.videoGravity = .resizeAspect
    playerLayer.frame = .init(width: 1, height: 1)  // Must have a non-zero size
    containerView.alpha = 0
    controller.requiresLinearPlayback = true
    controller.delegate = self

    // Repeat animation
    didPlayToEndTime = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.didPlayToEndTimeNotification,
      object: item,
      queue: .main
    ) { [player] _ in
      MainActor.assumeIsolated {
        player.seek(to: .zero)
        player.play()
      }
    }

    // Stop the PiP when the app comes back into focus
    didBecomeActive = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.stop()
      }
    }

    // Add it to the view hierarchy which is required to start a PiP session
    windowScene.keyWindow?.addSubview(containerView)
    containerView.layer.addSublayer(playerLayer)

    // Start playing
    player.play()

    // Wait until PiP is possible
    if !controller.isPictureInPicturePossible {
      await withCheckedContinuation { continuation in
        var observer: NSKeyValueObservation?
        Task.detached {
          try await Task.sleep(for: .milliseconds(500))
          if observer != nil {
            observer = nil
            continuation.resume()
          }
        }
        observer = controller.observe(\.isPictureInPicturePossible, options: [.new]) { _, change in
          if observer != nil, let isPossible = change.newValue, isPossible {
            continuation.resume()
            observer = nil
          }
        }
      }
    }

    if !controller.isPictureInPicturePossible {
      // PiP still not available, likely timed out, so just cleanup
      stop()
      return
    }

    // Start PiP
    controller.startPictureInPicture()
  }

  func stop() {
    if let controller, controller.isPictureInPictureActive {
      controller.stopPictureInPicture()
    }
    player.replaceCurrentItem(with: nil)
    containerView.removeFromSuperview()

    didPlayToEndTime = nil
    didBecomeActive = nil
    onStop()

    Task.detached {
      try? AVAudioSession.sharedInstance().setActive(false)
    }
  }

  nonisolated func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: any Error
  ) {
    Task { @MainActor in
      stop()
    }
  }

  nonisolated func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    Task { @MainActor in
      stop()
    }
  }
}

struct DefaultBrowserActions: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.windowScene) private var windowScene

  private func presentPictureInPictureVideo() async {
    let colorScheme = colorScheme == .dark ? "dark" : "light"
    if AVPictureInPictureController.isPictureInPictureSupported(),
      let videoFileURL = Bundle.module.url(
        forResource: "set-default-pip-\(colorScheme)",
        withExtension: "mp4",
        subdirectory: "Videos"
      ),
      let windowScene
    {
      var controller: DefaultBrowserPictureInPictureController?
      controller = DefaultBrowserPictureInPictureController(
        videoURL: videoFileURL,
        windowScene: windowScene,
        onStop: {
          // Hold onto the controller until pip is stopped either by the user or when foregrounding
          _ = controller
          controller = nil
        }
      )
      await controller?.start()
    }
  }

  var continueHandler: () -> Void
  var body: some View {
    HStack {
      Button {
        continueHandler()
      } label: {
        Text(Strings.FocusOnboarding.notNowActionButtonTitle)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .buttonStyle(BraveOutlineButtonStyle(size: .large))
      Button {
        Task {
          if let openSettingsURL = URL(string: UIApplication.openSettingsURLString) {
            // Browther: analytics
            BrowtherAnalyticsService.shared.track(event: "default_browser_set")
            await presentPictureInPictureVideo()
            await UIApplication.shared.open(openSettingsURL)
          }
          continueHandler()
        }
      } label: {
        Text(Strings.FocusOnboarding.systemSettingsButtonTitle)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .primaryContinueAction()
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

public struct DefaultBrowserOnboardingStep: OnboardingStep {
  public var id: String = "default-browsing"
  public func makeTitle() -> some View {
    OnboardingTitleView(
      title: Strings.FocusOnboarding.defaultBrowserScreenTitle,
      subtitle: Strings.FocusOnboarding.defaultBrowserScreenDescription
    )
  }
  public func makeGraphic() -> some View {
    DefaultBrowserGraphicView()
  }
  public func makeActions(continueHandler: @escaping () -> Void) -> some View {
    DefaultBrowserActions(continueHandler: continueHandler)
      .prepareWindowSceneEnvironment()
  }
}

extension OnboardingStep where Self == DefaultBrowserOnboardingStep {
  public static var defaultBrowsing: Self { .init() }
}

#if DEBUG
#Preview {
  OnboardingStepView(step: .defaultBrowsing)
}
#endif
