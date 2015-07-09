//
//  CloudKitAPICachePolicy.swift
//  CloudKitAPICache
//
//  Created by Ben Lu on 7/13/15.
//  Copyright © 2015 DJ.Ben. All rights reserved.
//

import UIKit

public class CloudKitAPICachePolicy: NSObject {
    public enum MaxAge {
        case TenMinutes
        case ThirtyMinutes
        case Minutes(Double)
        case OneHour
        case TwoHours
        case SixHours
        case TwelveHours
        case Hours(Double)
        case OneDay
        case Days(Double)
        case OneWeek
        case Weeks(Double)
        case OneMonth
        case Months(Double)
        case Seconds(NSTimeInterval)
        case Infinity
        
        public var seconds: NSTimeInterval {
            get {
                switch self {
                case .TenMinutes:
                    return 10 * 60
                case .ThirtyMinutes:
                    return 30 * 60
                case .Minutes(let minutes):
                    return minutes * 60
                case .OneHour:
                    return 60 * 60
                case .TwoHours:
                    return 2 * 60 * 60
                case .SixHours:
                    return 6 * 60 * 60
                case .TwelveHours:
                    return 12 * 60 * 60
                case .Hours(let hours):
                    return hours * 60 * 60
                case .OneDay:
                    return 24 * 60 * 60
                case .Days(let days):
                    return days * MaxAge.OneDay.seconds
                case .OneWeek:
                    return 7 * MaxAge.OneDay.seconds
                case .Weeks(let weeks):
                    return weeks * 7 * MaxAge.OneDay.seconds
                case .OneMonth:
                    return 30 * MaxAge.OneDay.seconds
                case .Months(let months):
                    return months * MaxAge.OneMonth.seconds
                case .Seconds(let interval):
                    return interval
                case .Infinity:
                    return NSTimeInterval.infinity
                }
            }
        }
    }
    
    public let maxAge: MaxAge
    
    private convenience override init() {
        self.init(maxAge: .OneHour)
    }
    
    public init(maxAge: MaxAge) {
        self.maxAge = maxAge
        super.init()
    }
    
    class var noPolicy: CloudKitAPICachePolicy {
        let policy = CloudKitAPICachePolicy(maxAge: .Infinity)
        return policy
    }
    
    class var defaultPolicy: CloudKitAPICachePolicy {
        let policy = CloudKitAPICachePolicy()
        return policy
    }
}