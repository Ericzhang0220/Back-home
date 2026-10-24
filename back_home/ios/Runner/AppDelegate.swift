import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

/// Reserve three-finger drags for the room camera while a room scene is active.
/// Text fields continue to use UIKit's normal editing gestures.
@objc class RoomFlutterViewController: FlutterViewController {
  private var roomGesturesActive = false
  private var roomGestureChannel: FlutterMethodChannel?

  override func viewDidLoad() {
    super.viewDidLoad()
    let channel = FlutterMethodChannel(
      name: "back_home/room_gestures",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setRoomGesturesActive" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
        let active = arguments["active"] as? Bool
      else {
        result(FlutterError(code: "invalid_arguments", message: "Missing active flag.", details: nil))
        return
      }
      self?.roomGesturesActive = active
      result(nil)
    }
    roomGestureChannel = channel
  }

  override var editingInteractionConfiguration: UIEditingInteractionConfiguration {
    if roomGesturesActive && (!isViewLoaded || !hasFocusedTextInput(in: view)) {
      return .none
    }
    return super.editingInteractionConfiguration
  }

  private func hasFocusedTextInput(in candidate: UIView) -> Bool {
    if candidate.isFirstResponder && candidate is UITextInput {
      return true
    }
    return candidate.subviews.contains { hasFocusedTextInput(in: $0) }
  }
}
