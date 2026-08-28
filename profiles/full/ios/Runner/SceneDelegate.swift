import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if let response = connectionOptions.notificationResponse,
      let appDelegate = UIApplication.shared.delegate as? AppDelegate
    {
      appDelegate.handleNotificationResponse(response)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }
}
