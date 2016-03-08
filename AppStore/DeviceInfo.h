//
//  DeviceInfo.h
//  l10s
//
//  Created by Tomohiro Tashiro on 2013/03/13.
//  Copyright (c) 2013年 weathernews. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DeviceInfo : NSObject

+ (NSString *)hwMachine;
+ (NSString *)deviceName;
+ (NSString *)carrierName;
+ (NSString *)userAgentString;
+ (BOOL)is4inch;

@end
