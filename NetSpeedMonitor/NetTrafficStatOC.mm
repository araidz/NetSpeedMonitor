#import "NetTrafficStatOC.h"

#import "NetTrafficStatCpp.hpp"

#include <string>

@implementation NetTrafficStatReceiver {
    NetTrafficStatGenerator netTrafficStatGenerator;
}

// This function does not take pppoe into account
- (BOOL)getStatForInterface:(NSString *)interfaceName
            downBytesPerSec:(double *)downBytesPerSec
              upBytesPerSec:(double *)upBytesPerSec
             deltaDownBytes:(int64_t *)deltaDownBytes
               deltaUpBytes:(int64_t *)deltaUpBytes {
    if (netTrafficStatGenerator.update() != 0) {
        return NO;
    }

    const NetTrafficStatMap &map = netTrafficStatGenerator.get_latest_net_traffic_stat_map();
    const char *name = interfaceName.UTF8String;
    if (name == nullptr) {
        return NO;
    }
    auto it = map.find(std::string(name));
    if (it == map.end()) {
        return NO;
    }

    const NetTrafficStat &stat = it->second;
    if (downBytesPerSec) { *downBytesPerSec = stat.ibytes_per_sec; }
    if (upBytesPerSec) { *upBytesPerSec = stat.obytes_per_sec; }
    if (deltaDownBytes) { *deltaDownBytes = stat.delta_ibytes; }
    if (deltaUpBytes) { *deltaUpBytes = stat.delta_obytes; }
    return YES;
}

- (void)resetBaseline {
    netTrafficStatGenerator.reset();
    netTrafficStatGenerator.update();
}

@end
