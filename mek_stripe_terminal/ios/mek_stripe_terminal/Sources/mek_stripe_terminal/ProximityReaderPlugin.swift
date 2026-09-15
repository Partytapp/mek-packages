import ProximityReader
import UIKit

class ProximityReaderPlugin : ProximityReaderPlatformApi {
    private let _viewController: () -> UIViewController?
    
    init(_ viewController: @escaping () -> UIViewController?) {
        self._viewController = viewController
    }

    @MainActor
    private func currentPresenter() throws -> UIViewController {
        // Resolve at presentation time because the engine may not have a controller at registration.
        guard var viewController = self._viewController() else {
            throw createPigeonError(".state_error", "UIViewController is nil");
        }
        while let presented = viewController.presentedViewController {
            viewController = presented
        }
        return viewController
    }
    
    func isAccountLinked(token: String, completion: @escaping (Result<Bool, any Error>) -> Void) {
        handleResult(completion) {
            guard #available(iOS 16.4, *) else {
                throw createUnsupportedOperatingSystem("16.4");
            }
            
            let paymentToken = PaymentCardReader.Token(rawValue: token)
            let reader = PaymentCardReader()
            return try await reader.isAccountLinked(using: paymentToken)
        }
    }
    
    func linkAccount(token: String, completion: @escaping (Result<Void, any Error>) -> Void) {
        handleResult(completion) {
            guard #available(iOS 15.4, *) else {
                throw createUnsupportedOperatingSystem("15.4");
            }
            
            let readerToken = PaymentCardReader.Token(rawValue: token)
            let reader = PaymentCardReader()
            try await reader.linkAccount(using: readerToken)
        }
    }
    
    func presentHowToTap(completion: @escaping (Result<Void, any Error>) -> Void) {
        handleResult(completion) { @MainActor in
            guard #available(iOS 18.0, *) else {
                throw createUnsupportedOperatingSystem("18.0");
            }
            
            let discovery = ProximityReaderDiscovery()
            let content = try await discovery.content(for: .payment(.howToTap))
            var viewController = try self.currentPresenter()
            if let transition = viewController.transitionCoordinator {
                // The PSP's activation screen can still be dismissing when its callback fires.
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    transition.animate(alongsideTransition: nil) { _ in
                        continuation.resume()
                    }
                }
                viewController = try self.currentPresenter()
            }
            guard viewController.viewIfLoaded?.window != nil,
                  !viewController.isBeingDismissed,
                  !viewController.isBeingPresented,
                  viewController.transitionCoordinator == nil else {
                throw createPigeonError(".state_error", "The presentation view controller is not ready");
            }
            try await discovery.presentContent(content, from: viewController)
        }
    }
}
