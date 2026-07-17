#pragma once

#import <Foundation/Foundation.h>

#import "NetTrafficStatCpp.hpp"


@interface NetTrafficStatOC : NSObject
@property (nonatomic, assign) NSInteger delta_ibytes;
@property (nonatomic, assign) NSInteger delta_obytes;
@property (nonatomic, assign) double ibytes_per_sec;
@property (nonatomic, assign) double obytes_per_sec;
@end


@interface NetTrafficStatReceiver : NSObject
@property (nonatomic, strong) NSMutableDictionary *netTrafficStatMap;
- (NSMutableDictionary *)getNetTrafficStatMap;
@end
