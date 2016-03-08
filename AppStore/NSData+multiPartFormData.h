#import <Foundation/Foundation.h>

@interface NSData (multiPartFormData)
+ (NSData *)dataWithMultiPartFormDataFields:(NSDictionary *)fields files:(NSArray *)files boundary:(NSString *)boundary;
@end
