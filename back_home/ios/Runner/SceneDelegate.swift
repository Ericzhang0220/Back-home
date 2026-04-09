import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    window?.backgroundColor = UIColor(
      red: 252.0 / 255.0,
      green: 247.0 / 255.0,
      blue: 241.0 / 255.0,
      alpha: 1.0
    )
  }
}
