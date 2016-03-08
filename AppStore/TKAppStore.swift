//
//  TKAppStore.swift
//  AppStore
//
//  Created by TashiroTomohiro on 2016/02/24.
//  Copyright © 2016年 Weathernews. All rights reserved.
//
//  従来の課金モジュールからの変更点
//  1. swift で記述
//  2. product情報 SKProductsRequest() を購入ボタンを押したタイミングではなく、アプリ起動時に取得(購入処理時間の短縮)
//  3. AppStore の recieptを transaction.transactionReciept (iOS 7 でdeplicated) の代わりに NSBundle.mainBundle().appStoreReceiptURL を用いて取得するよう変更
//  4. appStoreReceiptURL の参照先ファイルが存在しない場合、SKReceiptRefreshRequest() で更新を要求
//  5. サーバーとの通信を NSURLConnection (iOS 9 でdeplicated) の代わりに NSURLSession を用いて行うよう変更

import Foundation
import StoreKit


// MARK: - protocol TKAppStoreDelegate
@objc protocol TKAppStoreDelegate {
    func productInfoUpdated()
    func purchaseStarted(message :String?)
    func purchaseFinished(result :Bool, message :String?)
}

// MARK: -
class TKAppStore : NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver, SKRequestDelegate
{
    // product情報保持用
    var productDictionary = [String: SKProduct]()
    var productInfoUpdated :NSDate? = nil
    
    enum ProductType :String {
        // アプリで利用する product_id、将来複数になった場合でも対応できるように。
        //case Monthly = "co.xingtuan.i.tingkeling.monthly"
        case Monthly   = "com.weathernews.l10s.monthly"
        case Annual    = "com.weathernews.l10s.annual"
        case Ticket365 = "com.weathernews.l10s.365d"
        
        static let allValues = [ Monthly, Annual, Ticket365 ]
        static let count = allValues.count
        static let productIdSets = Set<String>(arrayLiteral: Monthly.rawValue, Annual.rawValue, Ticket365.rawValue )
        
        func title() -> String? {
            if let product = TKAppStore.sharedInstance.productDictionary[self.rawValue] {
                return product.localizedTitle
            }
            return nil
        }
        
        func price() -> String? {
            if let product = TKAppStore.sharedInstance.productDictionary[self.rawValue] {
                let numberFormatter = NSNumberFormatter()
                numberFormatter.formatterBehavior = .Behavior10_4
                numberFormatter.numberStyle = .CurrencyStyle
                numberFormatter.locale = product.priceLocale
                return numberFormatter.stringFromNumber(product.price)!
            }
            return nil
        }
    }
    
    // TODO: メッセージは Localizable.string に移す
    enum Message :String {
        case NotAbailable               = "この端末では購入はご利用いただけません。"
        case AnotherPurchaseNotFinished = "未完了の購入処理があります。\nしばらくお待ちください。"
        case NullAkey                   = "ログインしてから購入してください。"
        case WrongProductID             = "購入するプランを選択してください。"
        case ProductInfoMissing         = "料金情報の取得に失敗しました。"
        case ServerBusy                 = "現在購入ができません。\nしばらくたってからお試しください。"
//        case OtherChargeType            = "他の課金方法で課金中のため、\n追加の購入は行えません。"
//        case AutoRenewalValid           = "現在購読中のため\n追加の購入は行えません。"
        case PurchaseFinished           = "有効期限を更新しました。"
        case PurchaseFailed             = "購入が失敗しました。"
        case PurchaseDeferred           = "保護者の承認待ちです。"
        case RestoreFinished            = "有効期限を復元しました。";
        case RestoreFailed              = "復元に失敗しました。\n再度お試しください。"
        case RestoreNotFound            = "購入履歴はみつかりませんでした。"
        case RestoreExpired             = "有効期限が切れています。"
    }
    
    var isAvailable :Bool {
        // シミュレータなどでは NO を返す
        return SKPaymentQueue.canMakePayments()
    }
    
    // HTTP POST用
    private let api_url = "http://apns01.wni.co.jp/tingkeling/api_receipt_submit.cgi"
    private let boundary = "ZWFofh45lqDFMYVm" + (CFUUIDCreateString(kCFAllocatorDefault, CFUUIDCreate(kCFAllocatorSystemDefault)) as String)
    
    // MARK: - class lifecycle
    static let sharedInstance = TKAppStore()
    var delegate :TKAppStoreDelegate?
    var purchaseReceiptCount = 0
    var restoredReceiptCount = 0
    private var akey = UIDevice.currentDevice().identifierForVendor!.UUIDString  // DEBUG時は id4vendorで代用
    var validDate :NSDate? {
        get {
            if let date = NSUserDefaults.standardUserDefaults().objectForKey("validDate") {
                return date as? NSDate
            } else {
                return nil
            }
        }
        set {
            if newValue != nil {
                NSUserDefaults.standardUserDefaults().setObject(newValue, forKey: "validDate")
            } else {
                NSUserDefaults.standardUserDefaults().removeObjectForKey("validDate")
            }
            NSUserDefaults.standardUserDefaults().synchronize()
        }
    }
    
    override init() {
        super.init()
        
        // 購入時の処理時間短縮のため、事前に各ProductID に紐つく価格などを取得しておく
        self.productInfoRefresh()

        // アプリが裏に回った場合、その間は SKPaymentQueue.defaultQueue() の transactionObserver を無効にする
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "applicationDidBecomeActive",  name: UIApplicationDidBecomeActiveNotification,  object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "applicationWillResignActive", name: UIApplicationWillResignActiveNotification, object: nil)
        SKPaymentQueue.defaultQueue().addTransactionObserver(self)
    }
    
    deinit {
        LOG(__FUNCTION__)
        NSNotificationCenter.defaultCenter().removeObserver(self)
        SKPaymentQueue.defaultQueue().removeTransactionObserver(self)
    }

    func applicationDidBecomeActive() {
        //LOG(__FUNCTION__)
        SKPaymentQueue.defaultQueue().addTransactionObserver(self)
        self.productInfoRefresh()
    }
    
    func applicationWillResignActive() {
        //LOG(__FUNCTION__)
        SKPaymentQueue.defaultQueue().removeTransactionObserver(self)
    }
    
    // MARK: - public function
    func productInfoRefresh() {
        if productInfoUpdated == nil || productInfoUpdated!.timeIntervalSinceNow < -3600 || productDictionary.count == 0 {
            LOG(__FUNCTION__)
            let request = SKProductsRequest(productIdentifiers: ProductType.productIdSets)
            request.delegate = self
            request.start()
        }
    }
    
    func purchaseStart(productType :ProductType) {
        LOG(__FUNCTION__)
        
        if self.isAvailable == false {
            self.purchaseFinished(false, message: Message.NotAbailable.rawValue)
            return
        }

        let product = self.productDictionary[productType.rawValue]
        if product == nil {
            self.purchaseFinished(false, message: Message.ProductInfoMissing.rawValue)
            return
        }
 
        purchaseReceiptCount = 0
        restoredReceiptCount = 0
        let payment = SKMutablePayment(product: product!)
        payment.applicationUsername = self.akey  // iOS7以降、購入時に"誰が"購入したか、Username をレシートに含めることができるようになった? => サーバーに送信されるレシートにはこの情報は含まれないらしい
        
        LOG("purchase start: \(product!.productIdentifier) <=====")
        SKPaymentQueue.defaultQueue().addPayment(payment)
    }
    
    func restoreStart() {
        LOG(__FUNCTION__)
        
        if self.isAvailable == false {
            self.purchaseFinished(false, message: Message.NotAbailable.rawValue)
            return
        }

        purchaseReceiptCount = 0
        restoredReceiptCount = 0
        self.delegate?.purchaseStarted("Restoreing...")
        SKPaymentQueue.defaultQueue().restoreCompletedTransactions()
    }
    
    private func purchaseFinished(result :Bool, message :String?) {
        LOG( String(format:"\(__FUNCTION__), %@, \(message)", result ? "OK":"NG" ))
        LOG("purchase end <=====")
        
        purchaseReceiptCount = 0
        restoredReceiptCount = 0
        self.delegate?.purchaseFinished(result, message: message)
    }

    // MARK: - SKProductRequestDelegate
    func productsRequest(request: SKProductsRequest, didReceiveResponse response: SKProductsResponse) {
        //LOG(__FUNCTION__)
        request.delegate = nil
        LOG("[productRequest] found \(response.products.count) valid products, \(response.invalidProductIdentifiers.count) invalid products.")

        let numberFormatter = NSNumberFormatter()
        numberFormatter.formatterBehavior = .Behavior10_4
        numberFormatter.numberStyle = .CurrencyStyle
        
        productDictionary = [String: SKProduct]()
        
        // valid products
        for product in response.products {
            productDictionary[product.productIdentifier] = product
            
            numberFormatter.locale = product.priceLocale
            LOG("[product] \(product.productIdentifier), \(product.localizedTitle), price:\(numberFormatter.stringFromNumber(product.price)!)")
        }
        
        // invalid products
        for identifier in response.invalidProductIdentifiers {
            LOG("invalid ProductId: \(identifier)")
        }
        
        productInfoUpdated = NSDate()
        self.delegate?.productInfoUpdated()
    }
    
    // MARK: - SKRequestDelegate
    func requestDidFinish(request: SKRequest) {
        // レシート更新要求の他、ProductInfo取得時もここが呼び出される
        if request.isKindOfClass(SKReceiptRefreshRequest) {
            LOG("\(__FUNCTION__), \(request)")

            if let receiptUrl = NSBundle.mainBundle().appStoreReceiptURL {
                if let path = receiptUrl.path {
                    if NSFileManager.defaultManager().fileExistsAtPath(path) {
                        self.verifyReceipt()
                        return
                    }
                }
            }
            
            LOG("receipt receive failed.!!!")
            if purchaseReceiptCount > 0 {
                self.purchaseFinished(false, message: Message.PurchaseFailed.rawValue)
            } else if restoredReceiptCount > 0 {
                self.purchaseFinished(false, message: Message.RestoreFailed.rawValue)
            } else {
                self.purchaseFinished(false, message: Message.RestoreNotFound.rawValue)
            }
        }

    }
    
    func request(request: SKRequest, didFailWithError error: NSError) {
        LOG("\(__FUNCTION__), \(error.localizedDescription)")

        if request.isKindOfClass(SKReceiptRefreshRequest) {
            if purchaseReceiptCount > 0 {
                self.purchaseFinished(false, message: Message.PurchaseFailed.rawValue)
            } else if restoredReceiptCount > 0 {
                self.purchaseFinished(false, message: Message.RestoreFailed.rawValue)
            } else {
                self.purchaseFinished(false, message: Message.RestoreNotFound.rawValue)
            }
        }
    }
    
    // MARK: - SKPaymentTransactionObserver
    func paymentQueue(queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        LOG("\(__FUNCTION__), recieve \(transactions.count) transactions.")
        self.delegate?.purchaseStarted("Purchasing...")
        
        for transaction in transactions {
            //LOG("transactionID: \(transaction.transactionIdentifier), \(transaction.transactionDate)")
            
            switch (transaction.transactionState) {
            case .Purchasing:
                LOG("Purchasing... \(transaction.payment.productIdentifier)" )
                
            case .Restored:
                // Restore の場合、過去の期限切れも含めてまとめて復元されるので、ループを抜けた後で一括してサーバーに送信する
                LOG("Restored, \(transaction.payment.productIdentifier), \(transaction.transactionIdentifier!), \(transaction.transactionDate!)" )
                queue.finishTransaction(transaction)
                restoredReceiptCount++

            case .Purchased:  // 購入成功
                LOG("Purchase OK, \(transaction.payment.productIdentifier), \(transaction.transactionIdentifier!), \(transaction.transactionDate!)")
                purchaseReceiptCount++
                
            case .Failed:  // 購入失敗
                LOG("Purchase NG, \(transaction.payment.productIdentifier), \(transaction.transactionIdentifier!), \(transaction.error!.code), \(transaction.error!.localizedDescription)")
                queue.finishTransaction(transaction)
                if transaction.error?.code == SKErrorPaymentCancelled {
                    // キャンセルの場合はダイアログを表示しない
                    LOG("purchase cancelled.")
                    self.purchaseFinished(false, message: nil)
                } else {
                    self.purchaseFinished(false, message: Message.PurchaseFailed.rawValue)
                }
                
            case .Deferred:  // 購入承認待ち(ペアレンタルコントロール)
                LOG("Purchase Deferred, \(transaction.payment.productIdentifier), \(transaction.transactionIdentifier), \(transaction.error?.code), \(transaction.error?.localizedDescription)")
                self.purchaseFinished(false, message: Message.PurchaseFailed.rawValue)

//            default:
//                LOG("unexpected state !!!")
            }
        }
        
        // レシートが1件以上ある場合
        if purchaseReceiptCount > 0 || restoredReceiptCount > 0 {
            LOG("found \(purchaseReceiptCount) Purchase receipts, \(restoredReceiptCount) Restore receipts.")
            self.verifyReceipt()
        }
    }
    
    func verifyReceipt() {
        if let receipt = self.appStoreReceipt() {
            if self.sendServer(receipt) {
                // サーバー送信完了
                LOG("\(__FUNCTION__), api send OK")
                if purchaseReceiptCount > 0 {
                    // 購入時は、サーバーにレシート送信が完了してから finishTransaction()する
                    for transaction in SKPaymentQueue.defaultQueue().transactions {
                        if transaction.transactionState == .Purchased {
                            SKPaymentQueue.defaultQueue().finishTransaction(transaction)
                        }
                    }
                    self.purchaseFinished(true, message: Message.PurchaseFinished.rawValue)
                } else if self.validDate?.timeIntervalSinceNow > 0 {
                    // リストア、有効期限内
                    self.purchaseFinished(true, message: Message.RestoreFinished.rawValue)
                } else if self.validDate != nil {
                    // リストア、有効期限切れ
                    self.purchaseFinished(true, message: Message.RestoreExpired.rawValue)
                } else {
                    // リストア、履歴なし
                    self.purchaseFinished(true, message: Message.RestoreNotFound.rawValue)
                }
                return
            }
            else {
                // サーバー送信失敗
                LOG("\(__FUNCTION__), api send NG !!!")
            }
        } else {
            // レシートが取得できない場合
            LOG("\(__FUNCTION__), no receipt !!!!!")
        }
        
        if purchaseReceiptCount > 0 {
            self.purchaseFinished(false, message: Message.PurchaseFailed.rawValue)
        } else if restoredReceiptCount > 0 {
            self.purchaseFinished(false, message: Message.RestoreFailed.rawValue)
        } else {
            self.purchaseFinished(false, message: Message.RestoreNotFound.rawValue)
        }
    }

    func paymentQueue(queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {
/*
        for transaction in transactions {
            LOG("\(__FUNCTION__) \(transaction.transactionIdentifier!)")
        }
*/
    }
    
    func paymentQueueRestoreCompletedTransactionsFinished(queue: SKPaymentQueue) {
        LOG(__FUNCTION__)
        self.purchaseFinished(true, message: nil)
    }

    func paymentQueue(queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: NSError) {
        LOG("\(__FUNCTION__), error:\(error)")
        self.purchaseFinished(false, message: nil)
    }
    
    // MARK: - private function
    private func appStoreReceipt() -> String? {
        if let receiptUrl = NSBundle.mainBundle().appStoreReceiptURL {
            //LOG("receiptURL:\(receiptUrl)")
            
            if let path = receiptUrl.path {
                if NSFileManager.defaultManager().fileExistsAtPath(path) == false {
                    LOG("レシートが存在しないので要求")
                    let req = SKReceiptRefreshRequest()
                    req.delegate = self
                    req.start()
                }
            }
            
            if let receiptData = NSData(contentsOfURL: receiptUrl) {
                //LOG("receiptData:\(receiptData)")
                
                let receiptBase64Str = receiptData.base64EncodedStringWithOptions(NSDataBase64EncodingOptions())
                //LOG("receipt base64:\(receiptBase64Str)")
                return receiptBase64Str
                
            } else {
                // 取得できないのでエラー処理
                LOG("receipt decode failed !!! \(receiptUrl)")
                return nil
            }
        } else {
            LOG("no receipt URL !!!")
            return nil
        }
    }
    
    private func sendServer(receipt :String) -> Bool {
        //LOG(__FUNCTION__)

        // create form data
//        let profileManager = TKProfileManager.sharedManager()
        var fields = [String:String]()
        fields["akey"] = self.akey
//        fields["akey"]      = profileManager.akey
//        fields["devtoken"]  = profileManager.devtoken
//        fields["id4vendor"] = profileManager.id4vendor
//        fields["app_ver"]   = profileManager.app_version
//        fields["ios_ver"]   = profileManager.ios_version
        fields["device"]    = DeviceInfo.deviceName()
        fields["network"]   = DeviceInfo.carrierName()
        fields["receipt"]   = receipt
#if DEBUG
        fields["sandbox"]   = "1"
#endif
        
        let formData = NSData(multiPartFormDataFields: fields, files: nil, boundary: self.boundary)
        //LOG("formData:\(NSString(data:formData, encoding:NSUTF8StringEncoding))")
        
        // create HTTP request
        LOG("API sending... \(self.api_url)")
        let request = NSMutableURLRequest(URL: NSURL(string: self.api_url)!)
        request.HTTPMethod = "POST"
        request.setValue("multipart/form-data; boundary=" + self.boundary, forHTTPHeaderField: "Content-Type")
        request.HTTPBody = formData
        
        var result :Bool = false
        // HTTP 同期通信
        sendSynchronize(request, completion:{ data, response, error in
            let http_response = response as! NSHTTPURLResponse
            let str = NSString(data:data!, encoding:NSUTF8StringEncoding)
            LOG("HTTP response \(http_response.statusCode), \(str)")
            
            if http_response.statusCode != 200 {
                result = false
                return
            }
            
            do {  // parse json
                let json = try NSJSONSerialization.JSONObjectWithData(data!, options: .MutableContainers) as! NSDictionary
                if json["status"]!["auth"] as! String != "OK" {
                    LOG("api auth NG.")
                    result = false
                    return
                }
                
                // api reponse OK
                let tid = json["status"]!["tid"] as! String
                let valid_tm = json["status"]!["valid_tm"] as! Double
                if valid_tm > 0 {
                    self.validDate = NSDate(timeIntervalSince1970: valid_tm)
                    LOG("api auth OK, TID:\(tid), valid_tm:\(valid_tm), expireDate:\(self.validDate!)")
                    result = true
                } else {
                    self.validDate = nil
                    LOG("api auth OK, TID:\(tid), valid_tm:\(valid_tm), expireDate:unknown")
                    result = false
                }
                
            } catch {
                // json parse error
                LOG("json parse failed.")
                result = false
            }
        })
        return result
    }
    
    // NSURLSession を用いた同期通信
    private func sendSynchronize(request :NSURLRequest, completion: (NSData?, NSURLResponse?, NSError?) -> Void) {
        let semaphore = dispatch_semaphore_create(0)
        let subtask = NSURLSession.sharedSession().dataTaskWithRequest(request, completionHandler: { data, response, error in
            completion(data, response, error)
            dispatch_semaphore_signal(semaphore)
        })
        subtask.resume()
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
    }
    
}