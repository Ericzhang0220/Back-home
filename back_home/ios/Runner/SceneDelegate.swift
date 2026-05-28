import Flutter
import MusicKit
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var appleMusicChannel: FlutterMethodChannel?

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
    registerAppleMusicChannel()
  }

  private func registerAppleMusicChannel() {
    guard appleMusicChannel == nil,
      let flutterViewController = window?.rootViewController as? FlutterViewController
    else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "back_home/apple_music",
      binaryMessenger: flutterViewController.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "prepareFavoritesQueue":
        let arguments = call.arguments as? [String: Any]
        let limit = arguments?["limit"] as? Int ?? 30
        self.prepareFavoritesQueue(limit: limit, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    appleMusicChannel = channel
  }

  private func prepareFavoritesQueue(limit: Int, result: @escaping FlutterResult) {
    guard #available(iOS 16.0, *) else {
      result(
        FlutterError(
          code: "unavailable",
          message: "Apple Music library playback requires iOS 16 or newer.",
          details: nil
        )
      )
      return
    }

    Task {
      do {
        let queueInfo = try await buildFavoritesQueue(limit: max(1, min(limit, 50)))
        await MainActor.run {
          result(queueInfo)
        }
      } catch {
        await MainActor.run {
          result(
            FlutterError(
              code: "queue_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  @available(iOS 16.0, *)
  private func buildFavoritesQueue(limit: Int) async throws -> [String: Any] {
    if let favoritePlaylist = try await favoriteSongsPlaylist() {
      ApplicationMusicPlayer.shared.queue = [favoritePlaylist]
      return [
        "title": favoritePlaylist.name,
        "subtitle": "Apple Music favorites",
      ]
    }

    var songRequest = MusicLibraryRequest<Song>()
    songRequest.limit = limit
    songRequest.sort(by: \.playCount, ascending: false)

    let response = try await songRequest.response()
    let songs = Array(response.items.prefix(limit))

    guard !songs.isEmpty else {
      throw AppleMusicQueueError.emptyLibrary
    }

    ApplicationMusicPlayer.shared.queue = ApplicationMusicPlayer.Queue(
      for: MusicItemCollection(songs),
      startingAt: songs.randomElement()
    )

    let firstSong = songs.first
    return [
      "title": firstSong?.title ?? "Apple Music",
      "subtitle": firstSong?.artistName ?? "Your library songs",
    ]
  }

  @available(iOS 16.0, *)
  private func favoriteSongsPlaylist() async throws -> Playlist? {
    var playlistRequest = MusicLibraryRequest<Playlist>()
    playlistRequest.limit = 50

    let response = try await playlistRequest.response()
    return response.items.first { playlist in
      let normalizedName = playlist.name
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      return normalizedName == "favorite songs"
        || normalizedName == "favourite songs"
        || normalizedName == "favorites"
        || normalizedName == "favourites"
    }
  }
}

private enum AppleMusicQueueError: LocalizedError {
  case emptyLibrary

  var errorDescription: String? {
    switch self {
    case .emptyLibrary:
      return "No Apple Music library songs were found."
    }
  }
}
