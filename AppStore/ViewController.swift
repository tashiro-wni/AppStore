//
//  ViewController.swift
//  AppStore
//
//  Created by TashiroTomohiro on 2016/03/01.
//  Copyright © 2016年 Weathernews. All rights reserved.
//

import UIKit

class ViewController: UIViewController, TKAppStoreDelegate, UITableViewDataSource, UITableViewDelegate {
    @IBOutlet weak var infoLabel :UILabel!
    @IBOutlet weak var infoTable :UITableView!
    
    private let cellIdentifier = "defaultCell"
    private let dateFormatter = NSDateFormatter()
    private var hud :MBProgressHUD? = nil
    
    private enum Section :Int {
        case Purchase
        case Restore
        case _count   // dummy for element count
        
        static let count = _count.rawValue
    }
    
    deinit {
        TKAppStore.sharedInstance.delegate = nil

        infoTable.dataSource = nil
        infoTable.delegate = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        dateFormatter.locale = NSLocale(localeIdentifier: "ja_JP")
        dateFormatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        self.updateValidDate()
        
        infoTable.dataSource = self
        infoTable.delegate = self
        infoTable.tableFooterView = UIView(frame: CGRectZero)
        infoTable.registerClass(UITableViewCell.self, forCellReuseIdentifier: cellIdentifier)

        TKAppStore.sharedInstance.delegate = self
    }

    override func viewDidAppear(animated: Bool) {
        LOG(__FUNCTION__)
        super.viewDidAppear(animated)
    }
    
    override func didReceiveMemoryWarning() {
        LOG(__FUNCTION__)
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - TKAppStoreDelegate
    func productInfoUpdated() {
        LOG(__FUNCTION__)
        infoTable.reloadData()
    }
    
    func purchaseStarted(message :String?) {
        //LOG("\(__FUNCTION__), \(message)")
        self.performSelectorOnMainThread("showLoadingDialog:", withObject: message, waitUntilDone: true)
    }
    
    func purchaseFinished(result :Bool, message :String?) {
        //LOG(__FUNCTION__ + ", \(message)")
        self.performSelectorOnMainThread("hideLoadingDialog:", withObject: message, waitUntilDone: true)
    }

    func updateValidDate() {
        if let date = TKAppStore.sharedInstance.validDate {
            infoLabel.text = "有効期限: " + dateFormatter.stringFromDate(date)
            infoLabel.textColor = date.timeIntervalSinceNow < 0 ? UIColor.redColor(): UIColor.blackColor()
            
            if let tid = TKAppStore.sharedInstance.transactionId {
                infoLabel.text = infoLabel.text! + "\ntid: \(tid)"
            }
            
        } else {
            infoLabel.text = "有効期限: ---"
        }
    }
    
    // MARK: - UITableViewDataSource
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return Section.count
    }

    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case Section.Purchase.rawValue:  return TKAppStore.ProductType.count
        case Section.Restore.rawValue:   return 1
        default:                         return 0
        }
    }
    
    func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case Section.Purchase.rawValue:  return "Purchase"
        case Section.Restore.rawValue:   return "Restore"
        default: return nil
        }
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        //LOG("\(__FUNCTION__), indexPath:\(indexPath)")
        let cell = tableView.dequeueReusableCellWithIdentifier(cellIdentifier, forIndexPath: indexPath)
        cell.textLabel!.font = UIFont.systemFontOfSize(14.0)

        switch indexPath.section {
        case Section.Purchase.rawValue:
            let productType = TKAppStore.ProductType.allValues[indexPath.row]
            if let title = productType.title() {
                let price = productType.price()!
                cell.textLabel!.text = "\(title) \(price)"
                cell.textLabel!.minimumScaleFactor = 0.5
                cell.textLabel!.adjustsFontSizeToFitWidth = true
            } else {
                cell.textLabel!.text = "loading..."
            }
            
        case Section.Restore.rawValue:
            cell.textLabel!.text = "リストア"
        default:
            break
        }
        return cell
    }
    
    // MARK: - UITableViewDelegate
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)

        switch indexPath.section {
        case Section.Purchase.rawValue:
            let productType = TKAppStore.ProductType.allValues[indexPath.row]
            TKAppStore.sharedInstance.purchaseStart(productType)

        case Section.Restore.rawValue:
            TKAppStore.sharedInstance.restoreStart()

        default:
            break
        }
    }
    
    // MARK: - private function
    func showLoadingDialog(message :String?) {
        LOG(String(format: "%@, \"%@\"", __FUNCTION__, (message != nil) ? message! : ""))
        if hud == nil {
            hud = MBProgressHUD.init(view: self.view)
            hud!.dimBackground = true
            self.view.addSubview(hud!)
        }
        if let msg = message {
            hud!.labelText = msg
        }
        hud!.show(true)
        
        self.view.setNeedsDisplay()
    }
    
    func hideLoadingDialog(message :String?) {
        hud?.hide(true)
        self.showAlert(message)
        
        self.updateValidDate()
    }

    func showAlert(message :String?) {
        if message == nil {
            return
        }
        
        if #available(iOS 8.0, *) {
            let alert = UIAlertController(title: nil, message: message!, preferredStyle: .Alert)
            alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
            self.presentViewController(alert, animated: true, completion: nil)
        } else {
            let alert = UIAlertView(title: "", message: message!, delegate: nil, cancelButtonTitle: "OK")
            alert.show()
        }
    }
}

