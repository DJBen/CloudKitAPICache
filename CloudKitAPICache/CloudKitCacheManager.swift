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

/// The API cache manager, which is capable of caching an `NSURLRequest` to the iCloud to reduce the call to the original API.

public typealias CachedDataCompletionBlock =  (Bool, NSData?, NSError?) -> Void
public typealias CacheDataBlock = (NSData?, NSError?) -> Void
public typealias CacheErrorBlock = (NSError?) -> Void
public typealias CacheNetworkResponseBlock = (NSData?, NSURLResponse?, NSError?) -> Void

public class CloudKitAPICacheManager: NSObject {
    
    /// The shared singleton instance of the manager.
    public static let sharedManager = CloudKitAPICacheManager()

    public static let UnderlyingErrorKey = "underlyingError"
    public static let OldDataKey = "oldData"

    public enum CloudKitAPICacheError: ErrorType {
        case RequestError(underlyingError: NSError)
        case NoData
        case CachedRecordExpired(oldData: NSData)
        case MalformedRequest
        case NotCached // The user has responded `false` to the `shouldCacheData` block, therefore the data is not cached
        
        // This is a hack involving ErrorType loses the associated object when cast to NSError
        // We have to replicate an NSError in order to pass the associated object into userInfo dict
        // This issue is present as of beta 3
        func toNSError() -> NSError {
            switch self {
            case .RequestError(let underlyingError):
                let error = NSError(domain: "CloudKitAPICache.CloudKitAPICacheManager.CloudKitAPICacheError", code: 0, userInfo: [UnderlyingErrorKey: underlyingError])
                return error
            case .CachedRecordExpired(let oldData):
                let error = NSError(domain: "CloudKitAPICache.CloudKitAPICacheManager.CloudKitAPICacheError", code: 2, userInfo: [OldDataKey: oldData])
                return error
            default:
                return self as NSError
            }
        }
    }
    
    var publicDatabase: CKDatabase {
        return CKContainer.defaultContainer().publicCloudDatabase
    }
    
    public var cachePolicy = CloudKitAPICachePolicy.defaultPolicy
    
    /// The callback that checks if certain data fetched from source API should be cached.
    /// There are some situations you should selectively choose whether to cache the data.
    /// For example, you may want only to cache the data when it does not contain an error.
    public var shouldCacheData: (NSData, NSURLRequest) -> Bool = { _ in true }
    
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
    public func fetchCachedDataForRequest(request: NSURLRequest, autoFetch: Bool = true, fetchCompletion: CacheDataBlock? = nil, cacheCompletion: CacheErrorBlock? = nil, completion: CachedDataCompletionBlock) {
        let mainThreadFetchCompletion: CacheDataBlock = { data, error in
            dispatch_async(dispatch_get_main_queue()) {
                fetchCompletion?(data, error)
            }
        }
        let mainThreadCacheCompletion: CacheErrorBlock = { error in
            dispatch_async(dispatch_get_main_queue()) {
                cacheCompletion?(error)
            }
        }
        let mainThreadCompletion: CachedDataCompletionBlock = { isCached, data, error in
            dispatch_async(dispatch_get_main_queue()) {
                completion(isCached, data, error)
            }
        }
        let recordName = request.SHA1!
        publicDatabase.fetchRecordWithID(CKRecordID(recordName: recordName)) { (record, error) -> Void in
            guard error == nil || error!.code == CKErrorCode.UnknownItem.rawValue else {
                mainThreadFetchCompletion(nil, CloudKitAPICacheError.RequestError(underlyingError: error!).toNSError())
                mainThreadCompletion(false, nil, CloudKitAPICacheError.RequestError(underlyingError: error!).toNSError())
                return
            }
            
            // Called when the manager fails to find record in iCloud because of any reason
            let tryFetchFromSource: (expired: Bool, data: NSData?) -> Void = { expired, data in
                guard autoFetch else {
                    let notExistError = expired ? CloudKitAPICacheError.CachedRecordExpired(oldData: data!) : .NoData
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

                    guard self.shouldCacheData(data!, request) == true else {
                        mainThreadCacheCompletion(CloudKitAPICacheError.NotCached.toNSError())
                        return
                    }
                    self.cacheRequest(request, data: data!, savePolicy: .ChangedKeys) { (error) -> Void in
                        mainThreadCacheCompletion(error)
                    }
                }
                task.resume()
            }
            
            if let responseData = record?[.ResponseData] as? NSData {
                if let modificationDate = record?.modificationDate
                    where NSDate().timeIntervalSinceDate(modificationDate) > self.cachePolicy.maxAge.seconds {
                        tryFetchFromSource(expired: true, data: responseData)
                } else {
                    mainThreadFetchCompletion(responseData, nil)
                    mainThreadCompletion(true, responseData, nil)
                }
            } else {
                tryFetchFromSource(expired: false, data: nil)
            }
        }
    }
    
    /**
    Cache a request to iCloud. This method will call all the completion blocks on the main thread.
    
    :param: request           The URL request to be cached
    :param: requestCompletion The completion block being called upon request is finished
    :param: cacheCompletion   The completion block being called upon completing caching the request to iCloud
    :discussion: The first time the method is called, it will check for existing cached APIs if available. It will 
    overwrite the cached APIs on iCloud if it is expired according to the cache policy.

    */
    public func cacheRequest(request: NSURLRequest, requestCompletion: CacheNetworkResponseBlock, cacheCompletion: CacheErrorBlock? = nil) {
        let mainThreadCacheCompletion: CacheErrorBlock = { error in
            dispatch_async(dispatch_get_main_queue()) {
                cacheCompletion?(error)
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
                    mainThreadCacheCompletion(CloudKitAPICacheError.RequestError(underlyingError: error!).toNSError())
                    return
                }
                mainThreadRequestCompletion(data, response, nil)
                guard data != nil else {
                    mainThreadCacheCompletion(CloudKitAPICacheError.NoData.toNSError())
                    return
                }
                guard self.shouldCacheData(data!, request) == true else {
                    mainThreadCacheCompletion(CloudKitAPICacheError.NotCached.toNSError())
                    return
                }
                self.cacheRequest(request, data: data!, savePolicy: policy, completion: mainThreadCacheCompletion)
            }
            task.resume()
        }
        
        let recordName = request.SHA1!
        
        publicDatabase.fetchRecordWithID(CKRecordID(recordName: recordName)) { (record, error) -> Void in
            let savePolicy: CKRecordSavePolicy
            
            // Check if the cached version is expired, overwrite the cached API if needed.
            if let lastModifiedDate = record?.modificationDate where error == nil {
                if NSDate().timeIntervalSinceDate(lastModifiedDate) > self.cachePolicy.maxAge.seconds {
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
    
    func cacheRequest(request: NSURLRequest, data: NSData, savePolicy: CKRecordSavePolicy = .IfServerRecordUnchanged, completion: ((NSError?) -> Void)?) {
        guard let record = request.cachedRequestRecord else {
            completion?(CloudKitAPICacheError.MalformedRequest.toNSError())
            return
        }
        record[.ResponseData] = data
        let saveRecordOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        saveRecordOperation.savePolicy = savePolicy
        saveRecordOperation.modifyRecordsCompletionBlock = { savedRecords, _, error in
            guard error == nil else {
                completion?(CloudKitAPICacheError.RequestError(underlyingError: error!).toNSError())
                return
            }
            completion?(nil)
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
    
    public func cacheRequestWithCompletion(requestCompletion: CacheNetworkResponseBlock, cacheCompletion: CacheErrorBlock? = nil) {
        CloudKitAPICacheManager.sharedManager.cacheRequest(self, requestCompletion: requestCompletion, cacheCompletion: cacheCompletion)
    }
    
    public func fetchCachedData(autoFetch autoFetch: Bool = true, fetchCompletion: CacheDataBlock? = nil, cacheCompletion: CacheErrorBlock? = nil, completion: CachedDataCompletionBlock) {
        CloudKitAPICacheManager.sharedManager.fetchCachedDataForRequest(self, autoFetch: autoFetch, fetchCompletion: fetchCompletion, cacheCompletion: cacheCompletion, completion: completion)
    }
}
