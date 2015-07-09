# CloudKitAPICache [![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
Cache your third party API data on iCloud using CloudKit to avoid hitting API call limit. No server needed.

## Problem
### tl;dr
Think scale. Save money.
### The long version
Today there are a huge number of third party API ready for use on the web. However many of them apply a limit of calls per hour or per day for free, or you have to pay your money. For applications like weather and news, the update frequency is low - typically in the order of minutes, or hours. Suppose you have 100,000 users using your weather app every morning, they will send at least that 100,000 calls to the API endpoint. And of course, no API is generous enough to handle that many calls for free.

Think it differently. How many are these API calls return the same result? For a weather API, the result typically updates once per half an hour. Why can't we cache these duplicate responses somewhere and update only once per hour? That way the number of API calls per hour will effectively reduce from 100,000 to 2, saving us tons of money.

The way people do it is to build a server of their own to handle this caching mechanism. However, Apple launched [CloudKit](https://developer.apple.com/icloud/) with huge storage upbound. This project leverages that to cache the time insensitive APIs, reducing the overall number of calls to the original endpoint. The whole process works purely on the cloud - there's no need to build a server!

## Prerequesite
1. Swift 2.0
2. Xcode-beta 5

## Usage
  1. Import the framework to your class:
    import CloudKitAPICache
  2. You can call methods on your `NSURLRequest`:

        let request = NSURLRequest(URL: NSURL(string: "https://api.github.com/users/DJBen/repos")!)

  - Caching a request:

        request.cacheRequestWithCompletion({ (data, response, error) -> Void in
          // Process data fetched from source
        }) { (error) in
          // Process any error reported when caching the data to iCloud
        }

  - Fetching a request from cache:

        request.fetchCachedData { (fromCache, data, error) -> Void in
          // Process fetched data
        }

  This method will try to fetch data from iCloud first. If the cached data does not exist, it will automatically fetch from source API. You can turn off this behavior by passing `autoFetch: false` to the method argument.

  - Delete a cached request from cache:

        request.removeCachedRequestWithCompletion { (error) -> Void in
          // Process error
        }
