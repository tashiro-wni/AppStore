#import "WNHTTPLoader.h"
#import "DeviceInfo.h"

@implementation WNHTTPLoader

@synthesize canceled = mCanceled;
@synthesize delegate; // = mDelegate;
@synthesize index = mIndex;

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)deleg loaderID:(NSString *)loaderID
{
    self = [super init];
    if(self != nil) {
        if(loaderID)
            mLoaderID = [loaderID copy];
        mDelegate = deleg;
        mCanceled = NO;
        mFinished = NO;
        _sendProgress = 0.0f;
        _readDataSize = _expectedReadDataSize = 0;
        
        NSMutableURLRequest *req = request.mutableCopy;
        [req setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
        
        // set userAgent
        if( [req valueForHTTPHeaderField:@"User-Agent"] == nil ){
            [req setValue:[DeviceInfo userAgentString] forHTTPHeaderField:@"User-Agent"];
        }
        
        mURLConnection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
        NSLog(@"%@, %@ %@, timeout:%g sec", self.class, req.HTTPMethod, req.URL, req.timeoutInterval );
    }
    return self;
}

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)deleg loaderID:(NSString *)loaderID index:(int)index
{
    self = [self initWithRequest:request delegate:deleg loaderID:loaderID];
    if(self != nil) {
        mIndex = index;
    }
    return self;
}

- (void)cancel
{
    if(mCanceled == YES) {
        NSLog(@"HTTPLoder has canceled.");
        return;
    }

    [mURLConnection cancel];
    mFinished = YES;
    mCanceled = YES;
}

- (void)dealloc
{
    if(mFinished == NO)
        [mURLConnection cancel];
}

- (float)recieveProgress
{
    if( self.expectedReadDataSize > 0 )
        return (float)self.readDataSize / (float)self.expectedReadDataSize;
    else
        return 0.0f;
}

#pragma mark urlConnection delegate

- (void)connection:(NSURLConnection *)connection
   didSendBodyData:(NSInteger)bytesWritten
 totalBytesWritten:(NSInteger)totalBytesWritten
totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    if( totalBytesExpectedToWrite > 0 )
        _sendProgress = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;

//    FRLog( @"%@, SEND %zdbytes/%zdbytes (%g%%)",
//          mLoaderID, totalBytesWritten, totalBytesExpectedToWrite , _sendProgress * 100 );

    if(mDelegate != nil && [mDelegate respondsToSelector:@selector(loader:didSendBodyData:totalBytesWritten:totalBytesExpectedToWrite:loaderID:)]) {
        [mDelegate loader:self didSendBodyData:bytesWritten totalBytesWritten:totalBytesWritten
                   totalBytesExpectedToWrite:totalBytesExpectedToWrite loaderID:mLoaderID];
    }
}

/*
- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse
{
    NSLog(@"%@", NSStringFromSelector(_cmd));
    NSLog(@"%@", request);
    NSLog(@"%@", redirectResponse);
    NSURLRequest *newRequest = request;

    if(redirectResponse) {
        newRequest = nil;
    }

    return newRequest;
}
 */

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    _expectedReadDataSize = (NSUInteger)[response expectedContentLength];
    _readDataSize = 0;
    
    if(mDelegate != nil && [mDelegate respondsToSelector:@selector(loader:didReceiveResponse:loaderID:)]) {
        [mDelegate loader:self didReceiveResponse:response loaderID:mLoaderID];
    }

    if(mDownloadBuffer == nil)
        mDownloadBuffer = [[NSMutableData alloc] init];
 	[mDownloadBuffer setLength:0];
/*
    NSDictionary *headerInfo = ((NSHTTPURLResponse *)response).allHeaderFields;
    for( id key in headerInfo.allKeys ){
        FRLog( @"[%@] %@: %@", self.class, key, headerInfo[key] );
    }
*/
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [mDownloadBuffer appendData:data];
    _readDataSize += data.length;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    _sendProgress = 1.0f;
    _readDataSize = _expectedReadDataSize;
    
    if(mDelegate != nil && [mDelegate respondsToSelector:@selector(loader:didReceiveData:loaderID:)]) {
        [mDelegate loader:self didReceiveData:mDownloadBuffer loaderID:mLoaderID];
    }

    mDownloadBuffer = nil;
    mFinished = YES;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    mDownloadBuffer = nil;

    if(mDelegate != nil && [mDelegate respondsToSelector:@selector(loader:didFailWithError:loaderID:)]) {
        [mDelegate loader:self didFailWithError:error loaderID:mLoaderID];
    }
    
    mFinished = YES;
}

@end
