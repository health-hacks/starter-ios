//
//  HealthKitManager.swift
//  Starter App
//
//  Created by ismails on 5/27/16.
//  Copyright © 2016 Saad Ismail. All rights reserved.
//

import Foundation
import HealthKit

//T1ODO-ADD-NEW-DATA-TYPE
//Add in a key for the values inside a HKObject
//This is used to parse the values out of the HK Object and store it in a dictionary
enum HKObjectKey: String {
    case Date = "date"
    case SourceName = "sourceName"
    case HealthKitUUID = "healthkitUUID"
    case Value = "value"
}

/// Manages HealthKit authorization, querying, storing, etc.
class HealthKitManager {
    /// Shared Instance - This class is a singleton. You must use this instance to interact with HealthKitManager.
    static let sharedInstance = HealthKitManager()
    
    // MARK: - Properties
    var didConfigureHKAuth: Bool {
        get {
            let prefs = NSUserDefaults.standardUserDefaults()
            return prefs.boolForKey("didConfigureHKAuth")
        }
        set {
            let prefs = NSUserDefaults.standardUserDefaults()
            prefs.setBool(newValue, forKey: "didConfigureHKAuth")
        }
    }
    
    private var readAuthArr: [HKObjectType] = []
    private var writeAuthArr: [HKSampleType] = []
    private var backgroundDeliveryArr: [HKSampleType] = []
    
    let hkHealthStore = HKHealthStore()
    
    // MARK: - Closures
    
    // MARK: - Notifications
    /**
     Keys for Items in User Info Dictionary in NSNotification
     
     - ErrorObj: the NSError object
     */
    enum NotificationUserInfoKey: String {
        case ErrorObj = "ErrorObj"
        case HKObjects = "HKObjects"
        case HKObjectTypeId = "HKObjectType"
    }
    
    /**
     Names of NSNotifications that are published
     
     - AuthorizationSuccess: notification for when authorization was  successfull
     - AuthorizatonError:    notification for when authorization failed
     */
    enum Notification: String {
        case AuthorizationSuccess = "AuthSuccess"
        case AuthorizatonError = "AuthError"
        case BackgroundDeliveryError = "BackgroundDeliveryError"
        case BackgroundDeliveryResultError = "BackgroundDeliveryResultError"
        case BackgroundDeliveryResultSuccess = "BackgroundDeliveryResultSuccess"
    }
    
    // MARK: - Errors
    enum HKAuthorizationError: ErrorType {
        case AlreadyConfigured
        case HealthDataUnavailable
    }
    
    // MARK: - Configure
    func initializeHealthKitManager(sampleTypesForReadAuth readArr: [HKObjectType],
                                                           sampleTypesForWriteAuth writeArr: [HKSampleType],
                                                                                   sampleTypesForBackgroundDelivery backgroundDeliveryArr: [HKSampleType]) throws {
        
        self.readAuthArr = readArr
        self.writeAuthArr = writeArr
        self.backgroundDeliveryArr = backgroundDeliveryArr
        
        // if we have already asked for health kit authorization, then enable background delivery
        // if not, then request for authorization. in the notification of a successful auth,
        // then we enable background delivery
        if HealthKitManager.sharedInstance.didConfigureHKAuth {
            HealthKitManager.sharedInstance.enableBackgroundDelivery(self.backgroundDeliveryArr)
        } else {
            try HealthKitManager.sharedInstance.requestHKAuthorization(sampleTypesForReadAuth: Set(self.readAuthArr), sampleTypesForWriteAuth: Set(self.writeAuthArr))
        }
    }
    
    // MARK: - Initial Setup/Config
    /**
     Requests HealthKit authorization based on the readSet and writeSet that are passed.
     This function will not attempt to authorize if it has already authorized once or if
     health data is not available on the device.
     
     An NSNotification will be sent out based on the status of the authorization.
     
     - parameter readSet:  objects that requesting for read access
     - parameter writeSet: objects that requesting for write access
     
     - throws: an HKAuthorizationError
     */
    func requestHKAuthorization(sampleTypesForReadAuth readSet: Set<HKObjectType>,
                                                       sampleTypesForWriteAuth writeSet: Set<HKSampleType>) throws {
        defer {
            didConfigureHKAuth = true
        }
        
        // If user already configured HealthKit access then do not configure again.
        // Apple only allows configuration once (CONFIRM). After the first configuration,
        // the user can update the app's health kit access settings in the Apple Health App
        guard didConfigureHKAuth == false else {
            throw HKAuthorizationError.AlreadyConfigured
        }
        
        // Not all devices support HealthKit (e.g. iPad). Check to see if health data is
        // available in the first place.
        guard HKHealthStore.isHealthDataAvailable() == true else {
            throw HKAuthorizationError.HealthDataUnavailable
        }
        
        hkHealthStore.requestAuthorizationToShareTypes(writeSet, readTypes: readSet) { (success, error) in
            if success {
                // We successfully asked for HealthKit Authorization. Send out the notification and enable background delivery.
                dispatch_async(dispatch_get_main_queue(), {
                    NSNotificationCenter.defaultCenter().postNotificationName(Notification.AuthorizationSuccess.rawValue, object: HealthKitManager.sharedInstance, userInfo: nil)
                })
                
                self.enableBackgroundDelivery(self.backgroundDeliveryArr)
                
                return
            }
            
            // Something went wrong while asking HealthKit for authorization. This does not
            // indicate whether or not we were granted authorization to read/write data from HealthKit.
            
            var userInfo: [NSObject: AnyObject] = [:]
            if let errorObj = error {
                userInfo[NotificationUserInfoKey.ErrorObj.rawValue] = errorObj
            }
            
            dispatch_async(dispatch_get_main_queue(), {
                NSNotificationCenter.defaultCenter().postNotificationName(Notification.AuthorizatonError.rawValue, object: HealthKitManager.sharedInstance, userInfo: userInfo)
            })
        }
        
    }
    
    // MARK: - Query for Data
    /**
     Query for objects in HealthKit.
     
     - parameter sampleType:          the type of the HealthKit object
     - parameter afterDate:           filter the query by after a certain date
     - parameter beforeDate:          filter the query by before a certain date
     - parameter limit:               limit the number of items retireved from HealthKit
     - parameter sortDateAscending:   sort by date (ascending)
     - parameter queryResultsHandler: handler for when results are returned from the query
     */
    func queryForSampleType(sampleType: HKSampleType, afterDate: NSDate?, beforeDate: NSDate?, limit: Int, sortDateAscending: Bool, queryResultsHandler: (HKSampleQuery, [HKSample]?, NSError?) -> Void)
    {
        var predicate: NSPredicate?
        
        if(afterDate != nil && beforeDate != nil) {
            predicate = NSPredicate(format: "(startDate >= %@) and (startDate < %@)", afterDate!, beforeDate!)
        } else if(afterDate != nil) {
            predicate = NSPredicate(format: "(startDate >= %@)", afterDate!)
        } else if(beforeDate != nil) {
            predicate = NSPredicate(format: "(startDate < %@)", beforeDate!)
        }
        
        let sortDescriptors = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: sortDateAscending)
        
        let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: limit, sortDescriptors: [sortDescriptors], resultsHandler: queryResultsHandler)
        
        self.hkHealthStore.executeQuery(query)
    }
    
    // MARK: - Background Delivery
    /**
     Enable background delivery for HealthKit. This registers the application for updates
     to HealthKit obects in the background.
     
     When we get the notification stating that there have been updates, we will need to query for
     the latest objects. This query searches for any new objects in the past hour. An NSNotification will
     then be posted with an array of the objects updated in the last hour.
     
     The class that is listening to the NSNotification must iterate through the array of objects and compare it
     with the objects saved locally to find the new objects (reword)
     
     - parameter sampleTypesArr:  objects that need to be registered for background delivery
     - parameter updateFrequency: the update frequency of the background delivery (defaults to .Immediate)
     */
    func enableBackgroundDelivery(sampleTypesArr: [HKSampleType], updateFrequency: HKUpdateFrequency = .Immediate) {
        for sampleType in sampleTypesArr {
            self.hkHealthStore.enableBackgroundDeliveryForType(sampleType, frequency: updateFrequency) { (success, error) -> Void in
                if success {
                    let hourAgo = NSDate(timeIntervalSinceNow: -3600)
                    let pred = NSPredicate(format: "startDate > %@", hourAgo)
                    let query = HKObserverQuery(sampleType: sampleType, predicate: pred, updateHandler: self.backgroundQueryHandler)
                    
                    self.hkHealthStore.executeQuery(query)
                    
                    print("Enabled background delivery for \(sampleType)")
                } else {
                    print("Error enabling background delivery for \(sampleType). Error: \(error)")
                }
            }
        }
    }
    
    /**
     Handler for background delivery update. When we get a notification stating that something has updated,
     we will need to query for it. The handler for this query is located at backgroundQueryResultsHandler.
     
     - parameter query:             the query that the background delivery was triggered on
     - parameter completionHandler: the completion handler of the background delivery query
     - parameter error:             the error returned by the background delivery query
     */
    func backgroundQueryHandler(query: HKObserverQuery, completionHandler: HKObserverQueryCompletionHandler, error : NSError?) {
        guard error == nil else {
            dispatch_async(dispatch_get_main_queue(), {
                NSNotificationCenter.defaultCenter().postNotificationName(Notification.BackgroundDeliveryError.rawValue, object: HealthKitManager.sharedInstance, userInfo: [NotificationUserInfoKey.ErrorObj.rawValue: error!])
            })
            
            return
        }
        
        guard let sampleType = query.objectType as? HKSampleType else {
            dispatch_async(dispatch_get_main_queue(), {
                NSNotificationCenter.defaultCenter().postNotificationName(Notification.BackgroundDeliveryError.rawValue, object: HealthKitManager.sharedInstance, userInfo: nil)
            })
            
            return
        }
        
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        
        let sampleQuery = HKSampleQuery(sampleType: sampleType, predicate: query.predicate, limit: 100, sortDescriptors: sort, resultsHandler: self.backgroundQueryResultHandler)
        
        self.hkHealthStore.executeQuery(sampleQuery)
        
        //must call when subscribing to background updates
        completionHandler()
    }
    
    /**
     Handler for the query made inside backgroundQueryHandler.
     
     - parameter query:   the query that the handler is responding to
     - parameter results: the results from the query that was just executed
     - parameter error:   an error returned by the sample query
     */
    func backgroundQueryResultHandler(query: HKSampleQuery, results: [HKSample]?, error: NSError?) {
        guard error == nil else {
            dispatch_async(dispatch_get_main_queue(), {
                NSNotificationCenter.defaultCenter().postNotificationName(Notification.BackgroundDeliveryResultError.rawValue, object: HealthKitManager.sharedInstance, userInfo: [NotificationUserInfoKey.ErrorObj.rawValue: error!])
            })
            
            return
        }
        
        guard let sampleResults = results where sampleResults.count != 0 else {
            dispatch_async(dispatch_get_main_queue(), {
                NSNotificationCenter.defaultCenter().postNotificationName(Notification.BackgroundDeliveryResultError.rawValue, object: HealthKitManager.sharedInstance, userInfo: nil)
            })
            
            return
        }
        
        //let sampleResultsDict = sampleResults.map { $0.toDictionary() }
        let typeIdentifier = query.objectType?.identifier
        
        let userInfo: [String: AnyObject] = [
            NotificationUserInfoKey.HKObjectTypeId.rawValue: typeIdentifier != nil ? typeIdentifier! : "Unknown",
            NotificationUserInfoKey.HKObjects.rawValue: sampleResults]
        
        dispatch_async(dispatch_get_main_queue(), {
            NSNotificationCenter.defaultCenter().postNotificationName(Notification.BackgroundDeliveryResultSuccess.rawValue, object: HealthKitManager.sharedInstance, userInfo: userInfo)
        })
    }
}