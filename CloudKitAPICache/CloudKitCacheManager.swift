//
//  CacheManager.swift
//  CloudKitAPICache
//
//  Created by Ben Lu on 7/9/15.
//  Copyright © 2015 DJ.Ben. All rights reserved.
//

import UIKit
import CommonCrypto
import CloudKit

public typealias CachedDataCompletionBlock =  (Bool, NSData?, NSError?) -> Void
public typealias CacheDataBlock = (NSData?, NSError?) -> Void
public typealias CacheErrorBlock = (NSError?) -> Void
public typealias CacheNetworkResponseBlock = (NSData?, NSURLResponse?, NSError?) -> Void

/// The delegate for CloudKitAPICacheManager.

@objc public protocol CloudKitAPICacheDelegate {
    
    /**
    The callback that checks if certain data fetched from source API should be cached.
    There are some situations you should selectively choose whether to cache the data.
    For example, you may want only to cache the data when it does not contain an error.
    The client will by default cache all data retrieved if no implementation is supplied.
    
    :param: data    The data to be cached
    :param: request The URL request that generates the data
    :return: `true` if the data for the specified URL request should be cached
    */
    
    optional func shouldCacheData(data: NSData, forRequest request: NSURLRequest) -> Bool
    
    /**
    Specify the cache policy for every request. If you don't implement this method, 
    the cache policy will default to `CloudKitAPICachePolicy.defaultPolicy`
    
    :param: request The URL request
    :return: The cache policy for the specified URL request
    */
    optional func cachePolicyForRequest(request: NSURLRequest) -> CloudKitAPICachePolicy
    
}

/// The API cache manager, which is capable of caching an `NSURLRequest` to the iCloud to reduce the call to the original API.

public class CloudKitAPICacheManager: NSObject {
    
    /// The shared singleton instance of the manager.
    public static let sharedManager = CloudKitAPICacheManager()

    public static let UnderlyingErrorKey = "underlyingError"
    public static let RetriesLeftKey = "retriesLeft"
    public static let RetryDelayKey = "retryDelay"

    public enum CloudKitAPICacheError: ErrorType {
        case RequestError(underlyingError: NSError)
        case NoData
        case CachedRecordExpired
        case MalformedRequest
        case NotCached // The user has responded `false` to the `shouldCacheData` block, therefore the data is not cached
        case TemporaryError(underlyingError: NSError, retriesLeft: Int, retryDelay: NSTimeInterval)
        case AlreadyProcessing
        
        // This is a hack involving ErrorType loses the associated object when cast to NSError
        // We have to replicate an NSError in order to pass the associated object into userInfo dict
        // This issue is present as of beta 3
        func toNSError() -> NSError {
            switch self {
            case .RequestError(let underlyingError):
                let error = NSError(domain: "CloudKitAPICache.CloudKitAPICacheManager.CloudKitAPICacheError", code: 0, userInfo: [UnderlyingErrorKey: underlyingError])
                return error
            case let .TemporaryError(underlyingError, retries, retryDelay):
                let error = NSError(domain: "CloudKitAPICache.CloudKitAPICacheManager.CloudKitAPICacheError", code: 5, userInfo: [UnderlyingErrorKey: underlyingError, RetriesLeftKey: retries, RetryDelayKey: retryDelay])
                return error
            default:
                return self as NSError
            }
        }
    }
    
    public var delegate: CloudKitAPICacheDelegate?
    
    /// Container to use in iCloud, customize this before you do any caching operations
    public lazy var container: CKContainer = CKContainer.defaultContainer()
    
    var publicDatabase: CKDatabase {
        return container.publicCloudDatabase
    }
    
    /// The global cache policy. Defaults to one hour of age. If you wish to change the policy, you can initialize your own policy object and assign to this property. Note that the delegate method `-shouldCacheData:forRequest:` takes precedence over this property.
    public var globalCachePolicy = CloudKitAPICachePolicy.defaultPolicy
    
    private var requestProcessing = [String: NSURLRequest]()
    
    private override init() {
        super.init()
    }
    
    /**
    Attempt to fetch data from a cached `NSURLRequest`. If the data is already cached in the iCloud, the `cacheCompletion` 
    block will never be executed. Otherwise, by specifying `autoCache` property, the method will decide whether to fetch 
    the data from the original API automatically and cache it onto iCloud. This method will call all the completion blocks
    on the main thread.
    
    :param: request         The URL request
    :param: autoFetch       `true` if should automatically fetch from source API when cached request doesn't exist
    :param: fetchCompletion The completion block being called upon completing fetching the cached data
    :param: cacheCompletion The completion block being called upon completing caching the data
    :param: completion      The completion block that returns the cached data of the request; if the data has not been 
    cached, it will fetch the data from the original API and return it
    */
    public func fetchCachedDataForRequest(request: NSURLRequest, autoFetch: Bool = true, fetchCompletion: CacheDataBlock? = nil, cacheCompletion: CacheDataBlock? = nil, completion: CachedDataCompletionBlock) {
        
        let recordHash = request.SHA1!

        let mainThreadFetchCompletion: CacheDataBlock = { data, error in
            dispatch_async(dispatch_get_main_queue()) {
                fetchCompletion?(data, error)
            }
        }
        let mainThreadCacheCompletion: CacheDataBlock = { data, error in
            dispatch_async(dispatch_get_main_queue()) {
                cacheCompletion?(data, error)
            }
        }
        let mainThreadCompletion: CachedDataCompletionBlock = { isCached, data, error in
            if error?.code != CloudKitAPICacheError.AlreadyProcessing._code || error == nil {
                self.requestProcessing[recordHash] = nil
            }
            dispatch_async(dispatch_get_main_queue()) {
                completion(isCached, data, error)
            }
        }
        
        // Called when the manager fails to find record in iCloud because of any reason
        let tryFetchFromSource: (expired: Bool) -> Void = { expired in
            guard autoFetch else {
                let notExistError = expired ? CloudKitAPICacheError.CachedRecordExpired : .NoData
                mainThreadFetchCompletion(nil, notExistError.toNSError())
                mainThreadCompletion(false, nil, notExistError.toNSError())
                return
            }
            let task = NSURLSession.sharedSession().dataTaskWithRequest(request) { (data, _, error) -> Void in
                guard error == nil else {
                    mainThreadFetchCompletion(nil, CloudKitAPICacheError.RequestError(underlyingError: error!).toNSError())
                    mainThreadCompletion(false, nil, CloudKitAPICacheError.RequestError(underlyingError: error!).toNSError())
                    return
                }
                mainThreadCompletion(false, data, nil)
                
                guard self.delegate?.shouldCacheData?(data!, forRequest: request) ?? true else {
                    mainThreadCacheCompletion(data, CloudKitAPICacheError.NotCached.toNSError())
                    return
                }
                self.cacheRequest(request, data: data!, savePolicy: .ChangedKeys) { (error) -> Void in
                    mainThreadCacheCompletion(error)
                }
            }
            task.resume()
        }
        
        // Fetch the whole record
        let fetchRecordFromCloud: (recordName: String) -> Void = { recordName in
            self.publicDatabase.fetchRecordWithID(CKRecordID(recordName: recordName)) { (record, error) -> Void in
                guard error == nil || error!.code == CKErrorCode.UnknownItem.rawValue else {
                    mainThreadFetchCompletion(nil, CloudKitAPICacheError.RequestError(underlyingError: error!).toNSError())
                    mainThreadCompletion(false, nil, CloudKitAPICacheError.RequestError(underlyingError: error!).toNSError())
                    return
                }
                
                if let responseData = record?[.ResponseData] as? NSData {
                    mainThreadFetchCompletion(responseData, nil)
                    mainThreadCompletion(true, responseData, nil)
                } else {
                    tryFetchFromSource(expired: false)
                }
            }
        }
        
        // Make sure that the same request is currently processing
        guard requestProcessing[recordHash] == nil else {
            mainThreadFetchCompletion(nil, CloudKitAPICacheError.AlreadyProcessing.toNSError())
            mainThreadCompletion(false, nil, CloudKitAPICacheError.AlreadyProcessing.toNSError())
            return
        }
        requestProcessing[recordHash] = request
        
        // Fetch only the metadata first, then decide whether to fetch from source or to fetch from cloud based on whether the data has expired
        let recordID = CKRecordID(recordName: recordHash)
        let fetchOperation = CKFetchRecordsOperation(recordIDs: [recordID])
        fetchOperation.desiredKeys = []
        fetchOperation.fetchRecordsCompletionBlock = { recordDict, error in
            let realErrorOccurred: Bool
            if error != nil {
                if let dict = error?.userInfo[CKPartialErrorsByItemIDKey], subError = dict[recordID] as? NSError where error!.code == CKErrorCode.PartialFailure.rawValue {
                    realErrorOccurred = subError.code != CKErrorCode.UnknownItem.rawValue
                } else {
                    realErrorOccurred = error!.code != CKErrorCode.UnknownItem.rawValue
                }
            } else {
                realErrorOccurred = false
            }
            guard realErrorOccurred == false else {
                mainThreadFetchCompletion(nil, CloudKitAPICacheError.RequestError(underlyingError: error!).toNSError())
                mainThreadCompletion(false, nil, CloudKitAPICacheError.RequestError(underlyingError: error!).toNSError())
                return
            }
            if recordDict!.count > 0 {
                let record = Array(recordDict!.values)[0]
                let cachePolicy = self.delegate?.cachePolicyForRequest?(request) ?? self.globalCachePolicy
                if let modificationDate = record.modificationDate
                    where NSDate().timeIntervalSinceDate(modificationDate) > cachePolicy.maxAge.seconds {
                    tryFetchFromSource(expired: true)
                } else {
                    fetchRecordFromCloud(recordName: recordHash)
                }
            } else {
                tryFetchFromSource(expired: false)
            }
        }
        publicDatabase.addOperation(fetchOperation)
    }
    
    /**
    Cache a request to iCloud. This method will call all the completion blocks on the main thread.
    
    :param: request           The URL request to be cached
    :param: requestCompletion The completion block being called upon request is finished
    :param: cacheCompletion   The completion block being called upon completing caching the request to iCloud
    :discussion: The first time the method is called, it will check for existing cached APIs if available. It will 
    overwrite the cached APIs on iCloud if it is expired according to the cache policy.

    */
    public func cacheRequest(request: NSURLRequest, requestCompletion: CacheNetworkResponseBlock, cacheCompletion: CacheDataBlock? = nil) {
        
        let recordHash = request.SHA1!

        let mainThreadCacheCompletion: CacheDataBlock = { data, error in
            if error?.code != CloudKitAPICacheError.AlreadyProcessing._code || error == nil {
                self.requestProcessing[recordHash] = nil
            }
            dispatch_async(dispatch_get_main_queue()) {
                cacheCompletion?(data, error)
            }
        }
        let mainThreadRequestCompletion: CacheNetworkResponseBlock = { data, response, error in
            dispatch_async(dispatch_get_main_queue()) {
                requestCompletion(data, response, error)
            }
        }
        
        let fetchDataTask: (CKRecordSavePolicy) -> Void = { policy in
            let task = NSURLSession.sharedSession().dataTaskWithRequest(request) { (data, response, error) -> Void in
                guard error == nil else {
                    mainThreadRequestCompletion(data, response, CloudKitAPICacheError.RequestError(underlyingError: error!).toNSError())
                    mainThreadCacheCompletion(data, CloudKitAPICacheError.RequestError(underlyingError: error!).toNSError())
                    return
                }
                mainThreadRequestCompletion(data, response, nil)
                guard data != nil else {
                    mainThreadCacheCompletion(nil, CloudKitAPICacheError.NoData.toNSError())
                    return
                }
                guard self.delegate?.shouldCacheData?(data!, forRequest: request) ?? true else {
                    mainThreadCacheCompletion(data, CloudKitAPICacheError.NotCached.toNSError())
                    return
                }
                self.cacheRequest(request, data: data!, savePolicy: policy, completion: mainThreadCacheCompletion)
            }
            task.resume()
        }
    
        // Make sure that the same request is currently processing
        guard requestProcessing[recordHash] == nil else {
            mainThreadRequestCompletion(nil, nil, CloudKitAPICacheError.AlreadyProcessing.toNSError())
            mainThreadCacheCompletion(nil, CloudKitAPICacheError.AlreadyProcessing.toNSError())
            return
        }
        requestProcessing[recordHash] = request
        
        publicDatabase.fetchRecordWithID(CKRecordID(recordName: recordHash)) { (record, error) -> Void in
            let savePolicy: CKRecordSavePolicy
            
            // Check if the cached version is expired, overwrite the cached API if needed.
            if let lastModifiedDate = record?.modificationDate where error == nil {
                let cachePolicy = self.delegate?.cachePolicyForRequest?(request) ?? self.globalCachePolicy
                if NSDate().timeIntervalSinceDate(lastModifiedDate) > cachePolicy.maxAge.seconds {
                    savePolicy = .ChangedKeys
                } else {
                    savePolicy = .IfServerRecordUnchanged
                }
            } else {
                print("Warning: Unable to check for remote record when caching request. Will not overwrite.")
                savePolicy = .IfServerRecordUnchanged
            }
            
            fetchDataTask(savePolicy)
        }
        
    }
    
    func cacheRequest(request: NSURLRequest, data: NSData, savePolicy: CKRecordSavePolicy = .IfServerRecordUnchanged, completion: CacheDataBlock?) {
        let cachePolicy = self.delegate?.cachePolicyForRequest?(request) ?? self.globalCachePolicy
        cacheRequest(request, data: data, savePolicy: savePolicy, retryTimes: cachePolicy.cacheRetryTimes, retryDelay: cachePolicy.cacheRetryDelay, completion: completion)
    }
    
    func cacheRequest(request: NSURLRequest, data: NSData, savePolicy: CKRecordSavePolicy = .IfServerRecordUnchanged, retryTimes: Int, retryDelay: NSTimeInterval, completion: CacheDataBlock?) {
        guard let record = request.cachedRequestRecord else {
            completion?(data, CloudKitAPICacheError.MalformedRequest.toNSError())
            return
        }
        record[.ResponseData] = data
        let saveRecordOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        saveRecordOperation.savePolicy = savePolicy
        saveRecordOperation.modifyRecordsCompletionBlock = { savedRecords, _, error in
            guard error == nil else {
                if error!.code == CKErrorCode.ZoneBusy.rawValue {
                    // Server busy, retry with exponentially growing retry delay and limited retry times
                    // According to the advice from Apple on how to deal with `ZoneBusy` errors
                    if retryTimes > 0 {
                        let nextRetryDelay: NSTimeInterval = retryDelay == 0 ? 1 : retryDelay * 2
                        completion?(data, CloudKitAPICacheError.TemporaryError(underlyingError: error!, retriesLeft: retryTimes - 1, retryDelay: retryDelay).toNSError())
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(retryDelay * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
                            self.cacheRequest(request, data: data, savePolicy: savePolicy, retryTimes: retryTimes - 1, retryDelay: nextRetryDelay, completion: completion)
                        }
                    } else {
                        completion?(data, CloudKitAPICacheError.RequestError(underlyingError: error!).toNSError())
                    }
                } else {
                    completion?(data, CloudKitAPICacheError.RequestError(underlyingError: error!).toNSError())
                }
                return
            }
            completion?(data, nil)
        }
        publicDatabase.addOperation(saveRecordOperation)
    }
    
    /**
    Remove a cached request from iCloud. This method will call the completion block on the main thread.
    
    :param: request    The request to be removed from the cache
    :param: completion The completion block being called upon the deletion of the cached request
    */
    public func removeCachedRequest(request: NSURLRequest, completion: CacheErrorBlock) {
        let mainThreadCompletion: CacheErrorBlock = { error in
            dispatch_async(dispatch_get_main_queue()) {
                completion(error)
            }
        }
        guard let recordName = request.SHA1 else {
            mainThreadCompletion(CloudKitAPICacheError.MalformedRequest.toNSError())
            return
        }
        publicDatabase.deleteRecordWithID(CKRecordID(recordName: recordName)) { recordID, error in
            if let deletionError = error {
                mainThreadCompletion(CloudKitAPICacheError.RequestError(underlyingError: deletionError).toNSError())
            } else {
                mainThreadCompletion(nil)
            }
        }
    }
}

extension NSURLRequest {
    
    public func removeCachedRequestWithCompletion(completion: CacheErrorBlock) {
        CloudKitAPICacheManager.sharedManager.removeCachedRequest(self, completion: completion)
    }
    
    public func cacheRequestWithCompletion(requestCompletion: CacheNetworkResponseBlock, cacheCompletion: CacheDataBlock? = nil) {
        CloudKitAPICacheManager.sharedManager.cacheRequest(self, requestCompletion: requestCompletion, cacheCompletion: cacheCompletion)
    }
    
    public func fetchCachedData(autoFetch autoFetch: Bool = true, fetchCompletion: CacheDataBlock? = nil, cacheCompletion: CacheDataBlock? = nil, completion: CachedDataCompletionBlock) {
        CloudKitAPICacheManager.sharedManager.fetchCachedDataForRequest(self, autoFetch: autoFetch, fetchCompletion: fetchCompletion, cacheCompletion: cacheCompletion, completion: completion)
    }
}
