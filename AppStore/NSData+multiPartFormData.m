#import "NSData+multiPartFormData.h"

@implementation NSData (multiPartFormData)

+ (NSData *)dataWithMultiPartFormDataFields:(NSDictionary *)fields files:(NSArray *)files boundary:(NSString *)boundary
{
    static NSString *const BOUNDARY_FORMAT = @"--%@\r\n";
    static NSString *const NORMAL_FIELD_FORMAT = @"Content-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n";
    
    NSMutableData *data = [NSMutableData data];
    NSString *tmpString;
    
    for(NSString *key in [fields keyEnumerator]) {
        [data appendData:[[NSString stringWithFormat:BOUNDARY_FORMAT, boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        tmpString = [NSString stringWithFormat:NORMAL_FIELD_FORMAT, key, [fields objectForKey:key]];
        [data appendData:[tmpString dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    for(NSDictionary *dictionary in files) {
        NSString *name = [dictionary objectForKey:@"name"];
        NSString *filename = [dictionary objectForKey:@"filename"];
        NSString *contentType = [dictionary objectForKey:@"Content-Type"];
        NSData *formData = [dictionary objectForKey:@"data"];
        
        [data appendData:[[NSString stringWithFormat:BOUNDARY_FORMAT, boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        tmpString = [NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", name, filename];
        [data appendData:[tmpString dataUsingEncoding:NSUTF8StringEncoding]];
        tmpString = [NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", contentType];
        [data appendData:[tmpString dataUsingEncoding:NSUTF8StringEncoding]];
        [data appendData:formData];
        
        tmpString = [NSString stringWithFormat:@"\r\n"];
        [data appendData:[tmpString dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    [data appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    return data;
}

@end
