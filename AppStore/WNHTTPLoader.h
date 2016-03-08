#import <UIKit/UIKit.h>

@interface WNHTTPLoader : NSObject
{
    id mDelegate;
    NSMutableData   *mDownloadBuffer;
    NSURLConnection *mURLConnection;
    
    BOOL mFinished;
    BOOL mCanceled;
    
    NSString *mLoaderID;
	int mIndex;
}

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate loaderID:(NSString *)loaderID;
- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate loaderID:(NSString *)loaderID index:(int)index;
- (void)cancel;

@property BOOL canceled;
@property (weak) id delegate;
@property int index;
@property (readonly) float sendProgress;
@property (readonly) float recieveProgress;
@property (readonly) NSUInteger expectedReadDataSize;
@property (readonly) NSUInteger readDataSize;

@end

@interface NSObject(WNHTTPLoaderDelegate)

- (void)loader:(WNHTTPLoader *)loader
   didSendBodyData:(NSInteger)bytesWritten
 totalBytesWritten:(NSInteger)totalBytesWritten
totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
      loaderID:(NSString *)loaderID;

- (void)loader:(WNHTTPLoader *)loader didReceiveResponse:(NSURLResponse *)response loaderID:(NSString *)loaderID;
- (void)loader:(WNHTTPLoader *)loader didReceiveData:(NSData *)data loaderID:(NSString *)loaderID;
- (void)loader:(WNHTTPLoader *)loader didFailWithError:(NSError *)error loaderID:(NSString *)loaderID;

@end
