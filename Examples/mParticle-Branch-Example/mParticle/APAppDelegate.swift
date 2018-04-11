//
//  AppDelegate.swift
//  Fortune
//
//  Created by Edward Smith on 10/3/17.
//  Copyright © 2017 Branch. All rights reserved.
//

import UIKit
import mParticle_Apple_SDK
import mParticle_BranchMetrics
import Branch

@UIApplicationMain
class APAppDelegate: UIResponder, UIApplicationDelegate {

    @IBOutlet var window: UIWindow?

    func application(_ application: UIApplication,
            didFinishLaunchingWithOptions launchOptions:[UIApplicationLaunchOptionsKey: Any]?
        ) -> Bool {
        // Initialize our app data source:
        APAppData.shared.initialize()

        // Turn on all the debug output for testing:
        BNCLogSetDisplayLevel(.all)

        // Start mParticle
        let options = MParticleOptions.init(
            key: "fe8104a87f1fdf4d928f69c7d5dcb9bd",
            secret: "x2JpLm6QXAxCMpjxRpiDHyb4-biuW7Ddl6cdwIKct1YYvNtjeSLyJRnXFDcxyPUN"
        )
//        let request = MPIdentityApiRequest()  EBS
//        request.customerId = "custid_123456"
//        request.email = "email@example.com"
//        options.identifyRequest = request

        let mParticle = MParticle.sharedInstance()
        mParticle.logLevel = .debug
        mParticle.start(with: options)

        return true
    }
}
