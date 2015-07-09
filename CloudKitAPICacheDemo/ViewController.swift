//
//  ViewController.swift
//  CloudKitAPICacheDemo
//
//  Created by Ben Lu on 7/9/15.
//  Copyright © 2015 DJ.Ben. All rights reserved.
//

import UIKit
import CloudKitAPICache

class ViewController: UIViewController {

    @IBOutlet weak var dataTextView: UITextView!
    
    @IBOutlet weak var responseTextView: UITextView!
    
    @IBOutlet weak var autoFetchSwitch: UISwitch!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func finishChoosingRequest(segue: UIStoryboardSegue) {
        
    }

    @IBAction func cacheRequest(sender: UIButton) {
        self.clearDisplay()
        sender.enabled = false
        let group = dispatch_group_create()
        dispatch_group_enter(group)
        dispatch_group_enter(group)
        dispatch_group_notify(group, dispatch_get_main_queue()) {
            sender.enabled = true
        }
        Requests.currentRequest.cacheRequestWithCompletion({ (data, response, error) -> Void in
            defer {
                dispatch_group_leave(group)
            }
            guard error == nil else {
                self.responseTextView.appendText("\(error)")
                return
            }
            do {
                let JSONObject = try NSJSONSerialization.JSONObjectWithData(data!, options: .AllowFragments)
                self.dataTextView.appendText("\(JSONObject)")
            } catch let JSONError {
                self.responseTextView.appendText("\(JSONError)")
            }
        }) { (error) in
            defer {
                dispatch_group_leave(group)
            }
            guard error == nil else {
                self.responseTextView.appendText("\(error)")
                return
            }
            self.responseTextView.appendText("<succeeded>")
        }
    }
    
    @IBAction func fetchRequest(sender: UIButton) {
        self.clearDisplay()
        sender.enabled = false
        Requests.currentRequest.fetchCachedData(autoFetch: autoFetchSwitch.on) { (cached, data, error) -> Void in
            defer {
                sender.enabled = true
            }
            guard error == nil else {
                self.responseTextView.appendText("\(error)")
                return
            }
            do {
                let JSONObject = try NSJSONSerialization.JSONObjectWithData(data!, options: .AllowFragments)
                self.dataTextView.appendText("\(JSONObject)")
                self.responseTextView.appendText("<succeeded>")
            } catch let JSONError {
                self.responseTextView.appendText("\(JSONError)")
                print(JSONError)
            }
        }
    }
    
    @IBAction func removeCachedRequest(sender: UIButton) {
        self.clearDisplay()
        sender.enabled = false
        Requests.currentRequest.removeCachedRequestWithCompletion { (error) -> Void in
            defer {
                sender.enabled = true
            }
            guard error == nil else {
                self.responseTextView.appendText("\(error)")
                return
            }
            self.responseTextView.appendText("<succeeded>")
            self.dataTextView.appendText("<No data>")
        }
    }
    
    @IBAction func toggleAutoFetch(sender: UISwitch) {
        self.clearDisplay()
    }
    
    private func clearDisplay() {
        self.responseTextView.text = ""
        self.dataTextView.text = ""
    }
    
}

extension UITextView {
    func appendText(text: String) {
        if self.text == nil {
            self.text = ""
        }
        self.text = self.text! + "\n" + text
    }
}

