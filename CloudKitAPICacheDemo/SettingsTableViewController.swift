//
//  RequestsTableViewController.swift
//  CloudKitAPICache
//
//  Created by Ben Lu on 7/18/15.
//  Copyright © 2015 DJ.Ben. All rights reserved.
//

import UIKit
import CloudKitAPICache

class SettingsTableViewController: UITableViewController {
    
    static let maxAges: [CloudKitAPICachePolicy.MaxAge] = [.Seconds(20), .TenMinutes, .OneHour, .Infinity]
    static let maxAgesReadableStrings = ["20 sec", "10 min", "1 hour", "Infinity"]
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - Table view data source

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return Requests.allRequests.count
        case 1:
            return SettingsTableViewController.maxAges.count
        default:
            return 0
        }
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCellWithIdentifier("requestCell", forIndexPath: indexPath)
            cell.textLabel?.text = Requests.allRequests[indexPath.row].URL?.host
            if Requests.selectedIndex == indexPath.row {
                cell.accessoryType = .Checkmark
            } else {
                cell.accessoryType = .None
            }
            return cell
        } else if indexPath.section == 1 {
            let cell = tableView.dequeueReusableCellWithIdentifier("maxAgeCell", forIndexPath: indexPath)
            cell.textLabel?.text = SettingsTableViewController.maxAgesReadableStrings[indexPath.row]
            if SettingsTableViewController.maxAges[indexPath.row].seconds == CloudKitAPICacheManager.sharedManager.cachePolicy.maxAge.seconds {
                cell.accessoryType = .Checkmark
            } else {
                cell.accessoryType = .None
            }
            return cell
        }
        return UITableViewCell()
    }
    
    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Requests"
        case 1:
            return "Max cache age"
        default:
            return nil
        }
    }
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        if indexPath.section == 0 {
            Requests.selectedIndex = indexPath.row
        } else if indexPath.section == 1 {
            CloudKitAPICacheManager.sharedManager.cachePolicy = CloudKitAPICachePolicy(maxAge: SettingsTableViewController.maxAges[indexPath.row])
        }
        tableView.reloadData()
    }

}
