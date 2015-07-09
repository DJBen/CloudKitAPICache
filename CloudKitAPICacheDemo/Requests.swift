//
//  Requests.swift
//  CloudKitAPICache
//
//  Created by Ben Lu on 7/18/15.
//  Copyright © 2015 DJ.Ben. All rights reserved.
//

import UIKit
import CloudKitAPICache

class Requests: NSObject {
    
    static let sharedRequests = Requests()
    
    static let allRequests = [githubRequest, breezometerRequest, firebaseRequest]
    
    static var selectedIndex: Int = 0
    
    static var currentRequest: NSURLRequest {
        return allRequests[selectedIndex]
    }
    
    static var githubRequest: NSURLRequest = {
        return NSURLRequest(URL: NSURL(string: "https://api.github.com/users/DJBen/repos")!)
        }()
    
    private static var APIKeys: [String: String] = {
        let path = NSBundle.mainBundle().pathForResource("APIKeys", ofType: "plist")!
        return NSDictionary(contentsOfFile: path) as! [String: String]
    }()
    
    static var breezometerRequest: NSURLRequest = {
        let urlComponents = NSURLComponents(string: "https://api-beta.breezometer.com/baqi/")!
        urlComponents.queryItems = [NSURLQueryItem(name: "location", value: "Los Altos"),
            NSURLQueryItem(name: "key", value: APIKeys["Breezometer"] ?? "NEED CREDENTIAL")]
        let request = NSURLRequest(URL: urlComponents.URL!)
        return request
    }()
    
    static var firebaseRequest: NSURLRequest = {
        let request = NSMutableURLRequest(URL: NSURL(string: "https://djben.firebaseio.com/testCache.json")!)
        request.HTTPMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        let testDict = ["name": "DJBen", "lucky_numbers": [32768, 42]]
        let json = try! NSJSONSerialization.dataWithJSONObject(testDict, options: NSJSONWritingOptions())
        request.HTTPBody = json
        return request
    }()
    
}
