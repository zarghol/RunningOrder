//
//  CloudkitContainer.swift
//  RunningOrder
//
//  Created by Lucas Barbero on 26/08/2020.
//  Copyright © 2020 Worldline. All rights reserved.
//

import Foundation
import CloudKit
import Combine
import struct SwiftUI.AppStorage

extension JSONEncoder {
    static var `default`: JSONEncoder = .init()
}

extension JSONDecoder {
    static var `default`: JSONDecoder = .init()
}

extension Set: Storable where Element == String {
    static func decodeData(storedData: Data) throws -> Set<Element> {
        return try JSONDecoder.default.decode(Self.self, from: storedData)
    }

    func encodeToData() throws -> Data {
        try JSONEncoder.default.encode(self)
    }
}

fileprivate extension CKDatabase {
    var subscriptionId: CKSubscription.ID {
        switch self.databaseScope {
        case .private:
            return "privateDBSubscription"
        case .public:
            return "publicDBSubscription"
        case .shared:
            return "sharedDBSubscription"
        @unknown default:
            fatalError("unknown case \(self.databaseScope)")
        }
    }
}

final class CloudKitContainer {
    // MARK: Properties
    static var shared: CloudKitContainer = .init()

    private static let zoneName = "SharedZone"

    @AppStorage("CloudKitCreatedSharedZone") private static var createdCustomZone: Bool = false

    @Stored(fileName: "owners.json", directory: .applicationSupportDirectory) private static var ownerNames: Set<String>?

    private var cancellables = Set<AnyCancellable>()

    let ownedZoneId = CKRecordZone.ID(
        zoneName: CloudKitContainer.zoneName,
        ownerName: CKCurrentUserDefaultName
    )

    let cloudContainer = CKContainer(identifier: "iCloud.com.worldline.RunningOrder")

    var owners: [CKRecordZone.ID] {
        (CloudKitContainer.ownerNames ?? []).map {
            CKRecordZone.ID(zoneName: Self.zoneName, ownerName: $0)
        }
    }

    // MARK: - Setup methods

    private static func createSubscriptions(for database: CKDatabase, zoneId: CKRecordZone.ID) -> AnyPublisher<Never, Error> {
        let subscription = CKDatabaseSubscription(subscriptionID: database.subscriptionId)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let operation = CKModifySubscriptionsOperation(
            subscriptionsToSave: [subscription],
            subscriptionIDsToDelete: []
        )

        operation.qualityOfService = .utility

        database.add(operation)

        return operation.publisher()
            .print(in: Logger.debug)
            .ignoreOutput()
            .eraseToAnyPublisher()
    }

    private static func askPermissionForDiscoverabilityIfNeeded(in container: CKContainer) -> AnyCancellable {
        container.status(forApplicationPermission: .userDiscoverability)
            .filter { $0 == .initialState }
            .flatMap { _ in container.requestApplicationPermission(applicationPermission: .userDiscoverability) }
            .sink(receiveFailure: { error in
                Logger.error.log("error at requesting permission : \(error)")
            }, receiveValue: { status in
                switch status {
                case .couldNotComplete:
                    Logger.error.log("error when requesting permission for discoverability")
                case .granted:
                    Logger.debug.log("Discoverability granted")
                case .denied:
                    Logger.debug.log("Discoverability denied :'(")
                case .initialState:
                    fallthrough
                @unknown default:
                    break
                }
            })
    }

    private func createCustomZoneIfNeeded() {
        guard !CloudKitContainer.createdCustomZone else { return }

        Logger.verbose.log("shared zone creation")
        let sharedZone = CKRecordZone(zoneID: ownedZoneId)
        let zoneOperation = CKModifyRecordZonesOperation()
        zoneOperation.recordZonesToSave = [sharedZone]

        zoneOperation.modifyRecordZonesCompletionBlock = { _, _, error in
            if let error = error {
                Logger.error.log("error while creating custom zone : \(error)")
            } else {
                CloudKitContainer.createdCustomZone = true
            }
        }
        cloudContainer.privateCloudDatabase.add(zoneOperation)
    }

    private init() {
        createCustomZoneIfNeeded()
        enableNotificationsIfNeeded(for: ownedZoneId)

        if let owners = CloudKitContainer.ownerNames {
            for owner in owners {
                enableNotificationsIfNeeded(for: CKRecordZone.ID(zoneName: CloudKitContainer.zoneName, ownerName: owner))
            }
        }

        Self.askPermissionForDiscoverabilityIfNeeded(in: cloudContainer)
            .store(in: &cancellables)
    }

    func enableNotificationsIfNeeded(for zoneId: CKRecordZone.ID) {
        let databaseToEnable = database(for: zoneId)
        databaseToEnable.fetchAllSubscriptions()
            .filter { $0.isEmpty }
            .flatMap { _ in Self.createSubscriptions(for: databaseToEnable, zoneId: zoneId) }
            .sink(receiveFailure: { error in Logger.error.log(error) })
            .store(in: &cancellables)
    }

    func removeSubscriptions() {
        [CKDatabase.Scope.private, .shared].forEach { scope in
            let database = cloudContainer.database(with: scope)
            database.delete(withSubscriptionID: database.subscriptionId) { (id, error) in
                if let error = error {
                    Logger.error.log("error at deletion of subscription : \(error)")
                } else {
                    Logger.debug.log("subscription deletion successful : \(String(describing: id))")
                }
            }
        }
    }

    // MARK: -

    func database(for zoneId: CKRecordZone.ID) -> CKDatabase {
        let scope: CKDatabase.Scope = zoneId.ownerName == CKCurrentUserDefaultName ? .private : .shared
        return cloudContainer.database(with: scope)
    }

    func databaseScopeForNotification(_ userInfo: [String: Any]) -> CKDatabase.Scope? {
        Logger.debug.log("receive Notification : \(userInfo)")
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKDatabaseNotification else { return nil }

        return notification.databaseScope
    }

    func saveOwnerName(_ ownerName: String) {
        if var names = CloudKitContainer.ownerNames {
            names.insert(ownerName)
            CloudKitContainer.ownerNames = names
        } else {
            CloudKitContainer.ownerNames = [ownerName]
        }
    }
}

enum RecordType: String {
    case sprint = "Sprint"
    case story = "Story"
    case storyInformation = "StoryInformation"
    case space = "Space"
}
