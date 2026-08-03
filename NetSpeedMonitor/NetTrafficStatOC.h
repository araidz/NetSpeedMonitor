#pragma once

#import <Foundation/Foundation.h>

@interface NetTrafficStatReceiver : NSObject
// Samples all interfaces (sizing and data sysctl calls) and fills the named interface's rates and
// byte deltas without allocating a per-interface dictionary. Returns NO when the
// interface is absent.
- (BOOL)getStatForInterface:(NSString *)interfaceName
            downBytesPerSec:(double *)downBytesPerSec
              upBytesPerSec:(double *)upBytesPerSec
             deltaDownBytes:(int64_t *)deltaDownBytes
               deltaUpBytes:(int64_t *)deltaUpBytes;
- (void)resetBaseline;
@end
