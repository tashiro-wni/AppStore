//
//  DeviceInfo.m
//  l10s
//
//  Created by Tomohiro Tashiro on 2013/03/13.
//  Copyright (c) 2013年 weathernews. All rights reserved.
//
//  機種名リストは下記を元に作成した
//  https://gist.github.com/Jaybles/1323251

#import "DeviceInfo.h"
#include <sys/types.h>
#include <sys/sysctl.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
@import Foundation;
@import UIKit;

@implementation DeviceInfo

+ (NSString *)hwMachine
{
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithCString:machine
                                            encoding:NSUTF8StringEncoding];
    free(machine);
    return platform;
}

+ (NSString *)deviceName
{
    NSString* hwMachine = [self hwMachine];
    NSString* filePath = [[NSBundle mainBundle] pathForResource:@"DeviceNameList" ofType:@"plist"];
    NSDictionary* deviceList = [NSDictionary dictionaryWithContentsOfFile:filePath];
    NSString* deviceName = deviceList[hwMachine];
    
    if (deviceName == nil) {
        deviceName = hwMachine;
    }
    return deviceName;
}

+ (NSString *)carrierName
{
    CTTelephonyNetworkInfo *info = CTTelephonyNetworkInfo.new;
    CTCarrier *carrier = info.subscriberCellularProvider;
    NSString *carrierName = carrier.carrierName;
    
    if( carrierName == nil )  carrierName = @"SIMなし";
    return carrierName;
}

+ (NSString *)userAgentString
{
    return [NSString stringWithFormat:@"%@/%@ iOS/%@ locale/%@_%@ timezone/%@ device/(%@)",
            NSBundle.mainBundle.infoDictionary[(NSString *)kCFBundleNameKey],   // appName
            NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"],  // app version
            [UIDevice currentDevice].systemVersion,                             // iOS version
            [NSLocale preferredLanguages].firstObject,
            [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode],  // locale (en_US,ja_JP,...)
            [NSTimeZone localTimeZone].name,   // timezone
            [self deviceName]];          // device
}

+ (BOOL)is4inch
{
    // iPhone5 screen size
    return ( [UIScreen mainScreen].bounds.size.height >= 568 )? YES:NO;
}

@end
