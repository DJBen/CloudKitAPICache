//
//  NSURLRequest+CloudKitAPICache.swift
//  CloudKitAPICache
//
//  Created by Ben Lu on 7/9/15.
//  Copyright © 2015 DJ.Ben. All rights reserved.
//

import Foundation
import CloudKit

enum CloudKitAPICacheRecordKeys: String {
    case Method = "method"
    case BodySHA1 = "body_sha1"
    case URLSHA1 = "url_sha1"
    case URL = "url"
    case Header = "header"
    case ResponseData = "response_data"
}

extension NSURLRequest {
    var cachedRequestRecordType: String? {
        guard let hostSHA1 = URL?.host?.SHA1 else {
            return nil
        }
        return "req_\(hostSHA1)"
    }
    
    var cachedRequestRecord: CKRecord? {
        guard let type = cachedRequestRecordType else {
            return nil
        }
        let record = CKRecord(recordType: type, recordID: CKRecordID(recordName: SHA1!))
        record[.Method] = HTTPMethod!
        record[.BodySHA1] = bodySHA1 ?? ""
        record[.URLSHA1] = URL?.absoluteString.SHA1 ?? ""
        record[.URL] = URL?.absoluteString ?? ""
        var header: String?
        defer {
            record[.Header] = header ?? ""
        }
        if let headerJSON = allHTTPHeaderFields {
            do {
                header = try String(data: NSJSONSerialization.dataWithJSONObject(headerJSON, options: NSJSONWritingOptions()), encoding: NSUTF8StringEncoding)
            } catch {
            }
        }
        return record
    }
    
    var bodySHA1: String? {
        var result: String?
        if let HTTPBodySHA1 = HTTPBody?.SHA1 {
            result = String(data: HTTPBodySHA1, encoding: NSUTF8StringEncoding)
        }
        return result
    }
    
    var SHA1: String? {
        let dict = [CloudKitAPICacheRecordKeys.Method.rawValue: HTTPMethod!,
            CloudKitAPICacheRecordKeys.BodySHA1.rawValue: bodySHA1 ?? "",
            CloudKitAPICacheRecordKeys.URL.rawValue: URL?.absoluteString ?? "",
            CloudKitAPICacheRecordKeys.Header.rawValue: allHTTPHeaderFields ?? [:]]
        do {
            let json = try String(data: NSJSONSerialization.dataWithJSONObject(dict, options: NSJSONWritingOptions()), encoding: NSUTF8StringEncoding)!
            return json.SHA1
        } catch {
            return nil
        }
    }
}

extension CKRecord {
    subscript(key: CloudKitAPICacheRecordKeys) -> CKRecordValue? {
        get {
            return self[key.rawValue]
        }
        set {
            self[key.rawValue] = newValue
        }
    }
}