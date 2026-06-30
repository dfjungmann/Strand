import SwiftUI
import UIKit

extension Notification.Name {
    static let clockTabReselected = Notification.Name("Strand.clockTabReselected")
}

/// Erkennt erneutes Tippen auf einen bereits gewählten Tab in der Tab-Leiste.
struct TabBarReselectObserver: UIViewControllerRepresentable {
    let tabIndex: Int
    let notificationName: Notification.Name

    func makeCoordinator() -> Coordinator {
        Coordinator(tabIndex: tabIndex, notificationName: notificationName)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = ObserverViewController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.tabIndex = tabIndex
        context.coordinator.notificationName = notificationName
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var tabIndex: Int
        var notificationName: Notification.Name
        private weak var attachedTabBar: UITabBarController?

        init(tabIndex: Int, notificationName: Notification.Name) {
            self.tabIndex = tabIndex
            self.notificationName = notificationName
        }

        func install(on tabBarController: UITabBarController) {
            guard attachedTabBar !== tabBarController else { return }
            attachedTabBar = tabBarController
            tabBarController.delegate = self
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            if let viewControllers = tabBarController.viewControllers,
               let index = viewControllers.firstIndex(of: viewController),
               index == tabIndex,
               tabBarController.selectedIndex == index {
                NotificationCenter.default.post(name: notificationName, object: nil)
            }
            return true
        }
    }

    final class ObserverViewController: UIViewController {
        weak var coordinator: Coordinator?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if let tabBarController {
                coordinator?.install(on: tabBarController)
            }
        }
    }
}
