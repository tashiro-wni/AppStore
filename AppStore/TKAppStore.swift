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

// TODO: アプリインストール直後、ログインしているAppleIDのレシートが .Purchased でまとめて飛んでくることがある。(.Restoreではない)
// TODO: 購入完了時、サーバー送信前にStoreKitが「購入ありがとうございました」のダイアログを出すので、その後もサーバー検証完了までインジケーターが表示され続けるのは違和感があるかも。
// TODO: 新規購入時、StoreKit のダイアログがなかなか表示されないことがある(iOS7)


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
        //case Monthly   = "com.weathernews.l10s.monthly"
        //case Annual    = "com.weathernews.l10s.annual"
        //case Ticket365 = "com.weathernews.l10s.365d"
        case Monthly   = "com.weathernews.rakuraku.monthly_250"
        case Ticket31  = "com.weathernews.rakuraku.31d"
        case Ticket90  = "com.weathernews.rakuraku.90d"
        case Ticket180 = "com.weathernews.rakuraku.180d"
        case Ticket365 = "com.weathernews.rakuraku.365d_1"
        
        //static let allValues = [ Monthly, Annual, Ticket365 ]  // l10s
        static let allValues = [ Monthly, Ticket31, Ticket90, Ticket180, Ticket365 ]  // rakuraku

        static let count = allValues.count
        //static let productIdSets = Set<String>(arrayLiteral: Monthly.rawValue, Annual.rawValue, Ticket365.rawValue )  // l10s
        static let productIdSets = Set<String>(arrayLiteral: Monthly.rawValue, Ticket31.rawValue, Ticket90.rawValue, Ticket180.rawValue, Ticket365.rawValue )  // rakuraku
        
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
        case Purchasing                 = "Purchasing..."
        case Restoreing                 = "Restoreing..."
        case ServerSending              = "DB updating..."
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
    //private let api_reserve_url = "http://apns01.wni.co.jp/tingkeling/api_purchase_reserve.cgi"
    private let api_reserve_url = "http://apns01.wni.co.jp/rkrk/api_purchase_reserve.cgi"
    //private let api_submit_url  = "http://apns01.wni.co.jp/tingkeling/api_receipt_submit.cgi"
    private let api_submit_url  = "http://apns01.wni.co.jp/rkrk/api_receipt_submit.cgi"
    private let boundary = "ZWFofh45lqDFMYVm" + (CFUUIDCreateString(kCFAllocatorDefault, CFUUIDCreate(kCFAllocatorSystemDefault)) as String)
    
    var delegate :TKAppStoreDelegate?
    var purchaseReceiptCount = 0
    var restoredReceiptCount = 0
    private var purchasingProduct :SKProduct?
    private var receiptRetriving = false
    private var serverSending = false
    private let defaultsKey_validDate = "validDate"
    var validDate :NSDate? {
        get {
            if let date = NSUserDefaults.standardUserDefaults().objectForKey(defaultsKey_validDate) {
                return date as? NSDate
            } else {
                return nil
            }
        }
        set {
            if newValue != nil {
                NSUserDefaults.standardUserDefaults().setObject(newValue, forKey: defaultsKey_validDate)
            } else {
                NSUserDefaults.standardUserDefaults().removeObjectForKey(defaultsKey_validDate)
            }
            NSUserDefaults.standardUserDefaults().synchronize()
        }
    }
    var transactionId :String?
    
    // TODO: akey は profileManager を参照するよう変更予定
    private var akey = UIDevice.currentDevice().identifierForVendor!.UUIDString  // DEBUG時は id4vendorで代用
    
    // MARK: - class lifecycle
    static let sharedInstance = TKAppStore()

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
        } else {
            self.purchasingProduct = product
        }

        
        // create HTTP request 購入事前確認
        var fields = [String:String]()
        fields["akey"] = self.akey
        //        fields["akey"]      = profileManager.akey
        //        fields["devtoken"]  = profileManager.devtoken
        //        fields["id4vendor"] = profileManager.id4vendor
        //        fields["app_ver"]   = profileManager.app_version
        //        fields["ios_ver"]   = profileManager.ios_version
        fields["device"]    = DeviceInfo.deviceName()
        fields["network"]   = DeviceInfo.carrierName()
        fields["product_id"]   = self.purchasingProduct!.productIdentifier
        
        let formData = NSData(multiPartFormDataFields: fields, files: nil, boundary: self.boundary)

        LOG("API sending... \(self.api_reserve_url)")
        let request = NSMutableURLRequest(URL: NSURL(string: self.api_reserve_url)!)
        request.HTTPMethod = "POST"
        request.setValue("multipart/form-data; boundary=" + self.boundary, forHTTPHeaderField: "Content-Type")
        request.HTTPBody = formData
        
        // HTTP 非同期通信
        NSURLSession.sharedSession().dataTaskWithRequest(request, completionHandler: didReceiveReserveResponse).resume()
    }
    
    func didReceiveReserveResponse(data: NSData?, response :NSURLResponse?, error :NSError?) {
        let http_response = response as! NSHTTPURLResponse
        let str = NSString(data:data!, encoding:NSUTF8StringEncoding)
        LOG("HTTP response \(http_response.statusCode), \(str)")
        
        if http_response.statusCode != 200 {
            self.purchaseFinished(false, message: Message.ServerBusy.rawValue)
            return
        }
        
        do {  // parse json
            let json = try NSJSONSerialization.JSONObjectWithData(data!, options: .MutableContainers) as! NSDictionary
            if json["status"] as! String != "OK" {
                LOG("reserve api auth NG.")
                // TODO: reserve NG のエラーメッセージはもう少し場合分けする。akeyなしとか product_id 無効とか
                self.purchaseFinished(false, message: Message.ServerBusy.rawValue)
                return
            }
        } catch {
            // json parse error
            LOG("json parse failed.")
            self.purchaseFinished(false, message: Message.ServerBusy.rawValue)
            return
        }
        
        // reserve OK
        purchaseReceiptCount = 0
        restoredReceiptCount = 0
        let payment = SKMutablePayment(product: self.purchasingProduct!)
        payment.applicationUsername = self.akey  // iOS7以降、購入時に"誰が"購入したか、Username をレシートに含めることができるようになった? => サーバーに送信されるレシートにはこの情報は含まれないらしい
        
        LOG("purchase start: \(self.purchasingProduct!.productIdentifier) <=====")
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
        self.delegate?.purchaseStarted(Message.Restoreing.rawValue)
        SKPaymentQueue.defaultQueue().restoreCompletedTransactions()
    }
    
    private func purchaseFinished(result :Bool, message :String?) {
        LOG( String(format:"\(__FUNCTION__), %@, \(message)", result ? "OK":"NG" ))
        LOG("purchase end <=====")
        
        purchaseReceiptCount = 0
        restoredReceiptCount = 0
        purchasingProduct = nil
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
            self.receiptRetriving = false

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
        if self.delegate != nil {
            self.delegate?.purchaseStarted(Message.Purchasing.rawValue)
        } else {
            LOG("TKAppStore.delegate:nil")
        }
        
        
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
    
    func paymentQueue(queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {
/*
        for transaction in transactions {
            LOG("\(__FUNCTION__) \(transaction.transactionIdentifier!)")
        }
*/
    }
    
    func paymentQueueRestoreCompletedTransactionsFinished(queue: SKPaymentQueue) {
        LOG(__FUNCTION__)
        if self.serverSending == false {
            self.purchaseFinished(true, message: nil)
        }
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
                    self.receiptRetriving = true
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
    
    private func verifyReceipt() {
        if let receipt = self.appStoreReceipt() {
            // サーバーにレシート送信
            self.sendServer(receipt)
            return
        }
        
        // レシートが取得できない場合
        LOG("\(__FUNCTION__), no receipt !!!!!")
        
        if receiptRetriving == false {
            if purchaseReceiptCount > 0 {
                self.purchaseFinished(false, message: Message.PurchaseFailed.rawValue)
            } else if restoredReceiptCount > 0 {
                self.purchaseFinished(false, message: Message.RestoreFailed.rawValue)
            } else {
                self.purchaseFinished(false, message: Message.RestoreNotFound.rawValue)
            }
        }
    }

    private func sendServer(receipt :String) {
        //LOG(__FUNCTION__)
        self.delegate?.purchaseStarted(Message.ServerSending.rawValue)
        
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
        LOG("API sending... \(self.api_submit_url)")
        let request = NSMutableURLRequest(URL: NSURL(string: self.api_submit_url)!)
        request.HTTPMethod = "POST"
        request.setValue("multipart/form-data; boundary=" + self.boundary, forHTTPHeaderField: "Content-Type")
        request.HTTPBody = formData
        
        // HTTP 非同期通信
        self.serverSending = true
        NSURLSession.sharedSession().dataTaskWithRequest(request, completionHandler: didReceiveSubmitResponse).resume()
    }
    
    func didReceiveSubmitResponse(data: NSData?, response :NSURLResponse?, error :NSError?) {
        self.serverSending = false
        let http_response = response as! NSHTTPURLResponse
        let str = NSString(data:data!, encoding:NSUTF8StringEncoding)
        LOG("HTTP response \(http_response.statusCode), \(str)")
        
        if http_response.statusCode != 200 {
            self.purchaseFinished(false, message: Message.ServerBusy.rawValue)
            return
        }
        
        do {  // parse json
            let json = try NSJSONSerialization.JSONObjectWithData(data!, options: .MutableContainers) as! NSDictionary
            if json["status"]!["auth"] as! String != "OK" {
                LOG("api auth NG.")
                self.purchaseFinished(false, message: Message.ServerBusy.rawValue)
                return
            }
            
            // api reponse OK
            let tid = json["status"]!["tid"] as! String
            if tid.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 0 {
                self.transactionId = tid
            }
            
            let valid_tm = json["status"]!["valid_tm"] as! Double
            if valid_tm > 0 {
                self.validDate = NSDate(timeIntervalSince1970: valid_tm)
                LOG("api auth OK, TID:\(tid), valid_tm:\(valid_tm), expireDate:\(self.validDate!)")
                
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

                } else {
                    // リストア、有効期限切れ
                    self.purchaseFinished(true, message: Message.RestoreExpired.rawValue)
                }
                
            } else {
                // リストア、履歴なし
                self.validDate = nil
                LOG("api auth OK, TID:\(tid), valid_tm:\(valid_tm), expireDate:unknown")
                self.purchaseFinished(false, message: Message.RestoreNotFound.rawValue)
            }
            
        } catch {
            // json parse error
            LOG("json parse failed.")
            self.purchaseFinished(false, message: Message.ServerBusy.rawValue)
       }
    }
    
}