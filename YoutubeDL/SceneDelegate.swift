//
//  SceneDelegate.swift
//  YoutubeDL
//

import SwiftUI
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene,
              let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(
            rootView: MainView().environmentObject(appDelegate.model)
        )
        self.window = window
        window.makeKeyAndVisible()
        openURLs(connectionOptions.urlContexts)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        openURLs(URLContexts)
    }

    private func openURLs(_ contexts: Set<UIOpenURLContext>) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return
        }

        for context in contexts {
            guard var components = URLComponents(url: context.url, resolvingAgainstBaseURL: false) else {
                continue
            }
            components.scheme = "https"
            guard let url = components.url else {
                continue
            }
            appDelegate.model.url = url
        }
    }
}
