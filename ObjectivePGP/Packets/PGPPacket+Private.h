//
//  PGPPacket+Private.h
//  ObjectivePGP
//
//  Created by Marcin Krzyzanowski on 09/07/2017.
//  Copyright © 2017 Marcin Krzyżanowski. All rights reserved.
//

#import "PGPPacket.h"
#import <ObjectivePGP/ObjectivePGP.h>

NS_ASSUME_NONNULL_BEGIN

@interface PGPPacket ()

@property (nonatomic) BOOL indeterminateLength; // should not be used, but gpg uses it
@property (nonatomic, readwrite) PGPPacketTag tag;

+ (NSData *)buildNewFormatLengthDataForData:(NSData *)bodyData;

@end

NS_ASSUME_NONNULL_END
