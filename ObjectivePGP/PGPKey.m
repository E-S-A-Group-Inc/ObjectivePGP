//
//  PGPTransferableKey.m
//  ObjectivePGP
//
//  Created by Marcin Krzyzanowski on 13/05/14.
//  Copyright (c) 2014 Marcin Krzyżanowski. All rights reserved.
//

#import "PGPKey.h"
#import "PGPPublicKeyPacket.h"
#import "PGPSecretKeyPacket.h"
#import "PGPUser.h"
#import "PGPSignaturePacket.h"
#import "PGPSignatureSubpacket.h"
#import "PGPPublicSubKeyPacket.h"
#import "PGPSecretSubKeyPacket.m"
#import "PGPUserAttributePacket.h"
#import "PGPUserAttributeSubpacket.h"
#import "PGPSubKey.h"
#import "NSValue+PGPUtils.h"

@implementation PGPKey

- (instancetype) initWithPackets:(NSArray *)packets
{
    if (self = [self init]) {
        [self loadPackets:packets];
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"Type %@, %@ primary key: %@",self.type == PGPKeyPublic ? @"public" : @"secret", [super description], self.primaryKeyPacket];
}

- (BOOL)isEqual:(id)object
{
    if (self == object)
        return YES;
    
    if (![object isKindOfClass:[PGPKey class]]) {
        return NO;
    }
    
    //TODO: check all properties
    PGPKey *objectKey = (PGPKey *)object;
    return [self.keyID isEqual:objectKey.keyID] && (self.type == objectKey.type);
}

- (NSUInteger)hash
{
#ifndef NSUINTROTATE
#define NSUINT_BIT (CHAR_BIT * sizeof(NSUInteger))
#define NSUINTROTATE(val, howmuch) ((((NSUInteger)val) << howmuch) | (((NSUInteger)val) >> (NSUINT_BIT - howmuch)))
#endif
    
    NSUInteger hash = [self.primaryKeyPacket hash];
    hash = NSUINTROTATE(hash, NSUINT_BIT / 2) ^ self.type;
    hash = NSUINTROTATE(hash, NSUINT_BIT / 2) ^ [self.users hash];
    hash = NSUINTROTATE(hash, NSUINT_BIT / 2) ^ [self.subKeys hash];
    hash = NSUINTROTATE(hash, NSUINT_BIT / 2) ^ [self.directSignatures hash];
    hash = NSUINTROTATE(hash, NSUINT_BIT / 2) ^ [self.revocationSignature hash];
    hash = NSUINTROTATE(hash, NSUINT_BIT / 2) ^ [self.keyID hash];
    
    return hash;
}

- (NSMutableArray *)users
{
    if (!_users) {
        _users = [NSMutableArray array];
    }
    return _users;
}

- (NSMutableArray *)subKeys
{
    if (!_subKeys) {
        _subKeys = [NSMutableArray array];
    }
    return _subKeys;
}

- (NSMutableArray *)directSignatures
{
    if (!_directSignatures) {
        _directSignatures = [NSMutableArray array];
    }
    return _directSignatures;
}

- (BOOL)isEncrypted
{
    if (self.type == PGPKeySecret) {
        PGPSecretKeyPacket *secretPacket = (PGPSecretKeyPacket *)self.primaryKeyPacket;
        return secretPacket.isEncrypted;
    }
    return NO;
}

- (PGPKeyType)type
{
    PGPKeyType t = PGPKeyUnknown;

    switch (self.primaryKeyPacket.tag) {
        case PGPPublicKeyPacketTag:
        case PGPPublicSubkeyPacketTag:
            t = PGPKeyPublic;
            break;
        case PGPSecretKeyPacketTag:
        case PGPSecretSubkeyPacketTag:
            t = PGPKeySecret;
        default:
            break;
    }

    return t;
}

- (PGPKeyID *)keyID
{
    PGPPublicKeyPacket *primaryKeyPacket = (PGPPublicKeyPacket *)self.primaryKeyPacket;
    PGPKeyID *keyID = [[PGPKeyID alloc] initWithFingerprint:primaryKeyPacket.fingerprint];
    return keyID;
}

- (void) loadPackets:(NSArray *)packets
{
    // based on packetlist2structure
    PGPKeyID *primaryKeyID = nil;
    PGPSubKey *subKey      = nil;
    PGPUser *user          = nil;

    for (PGPPacket *packet in packets) {
        switch (packet.tag) {
            case PGPPublicKeyPacketTag:
                primaryKeyID = [(PGPPublicKeyPacket *)packet keyID];
                self.primaryKeyPacket = packet;
                break;
            case PGPSecretKeyPacketTag:
                primaryKeyID = [(PGPSecretKeyPacket *)packet keyID];
                self.primaryKeyPacket = packet;
                break;
            case PGPUserAttributePacketTag:
                if (!user) {
                    continue;
                }
                user.userAttribute = (PGPUserAttributePacket *)packet;
                break;
            case PGPUserIDPacketTag:
                if (!user) {
                    user = [[PGPUser alloc] initWithUserIDPacket:(PGPUserIDPacket *)packet];
                }
                [self.users addObject:user];
                break;
            case PGPPublicSubkeyPacketTag:
            case PGPSecretSubkeyPacketTag:
                user = nil;
                subKey = [[PGPSubKey alloc] initWithPacket:packet];
                [self.subKeys addObject:subKey];
                break;
            case PGPSignaturePacketTag:
            {
                PGPSignaturePacket *signaturePacket = (PGPSignaturePacket *)packet;
                switch (signaturePacket.type) {
                    case PGPSignatureGenericCertificationUserIDandPublicKey:
                    case PGPSignatureCasualCertificationUserIDandPublicKey:
                    case PGPSignaturePositiveCertificationUserIDandPublicKey:
                    case PGPSignaturePersonalCertificationUserIDandPublicKey:
                        if (!user) {
                            continue;
                        }
                        if ([signaturePacket.issuerKeyID isEqual:primaryKeyID]) {
                            user.selfCertifications = [user.selfCertifications arrayByAddingObject:packet];
                        } else {
                            user.otherSignatures = [user.otherSignatures arrayByAddingObject:packet];
                        }
                        break;
                    case PGPSignatureCertificationRevocation:
                        if (user) {
                            user.revocationSignatures = [user.revocationSignatures arrayByAddingObject:packet];
                        } else {
                            [self.directSignatures addObject:packet];
                        }
                        break;
                    case PGPSignatureDirectlyOnKey:
                        [self.directSignatures addObject:packet];
                        break;
                    case PGPSignatureSubkeyBinding:
                        if (!subKey) {
                            continue;
                        }
                        subKey.bindingSignature = (PGPSignaturePacket *)packet;
                        break;
                    case PGPSignatureKeyRevocation:
                        self.revocationSignature = (PGPSignaturePacket *)packet;
                        break;
                    case PGPSignatureSubkeyRevocation:
                        if (!subKey) {
                            continue;
                        }
                        subKey.revocationSignature = (PGPSignaturePacket *)packet;
                        break;
                    default:
                        break;
                }
            }
                break;
            default:
                break;
        }
    }
}

// signature packet that is available for signing data
- (PGPPacket *) signingKeyPacket
{
    NSAssert(self.type == PGPKeySecret, @"Need secret key to sign");
    if (self.type == PGPKeyPublic) {
        NSLog(@"Need secret key to sign");
        return nil;
    }

    // check primary user self certificates
    PGPSignaturePacket *primaryUserSelfCertificate = nil;
    [self primaryUserAndSelfCertificate:&primaryUserSelfCertificate];
    if (primaryUserSelfCertificate)
    {
        if (primaryUserSelfCertificate.canBeUsedToSign) {
            return self.primaryKeyPacket;
        }
    }

    for (PGPSubKey *subKey in self.subKeys) {
        PGPSignaturePacket *signaturePacket = subKey.bindingSignature;
        if (signaturePacket.canBeUsedToSign) {
            return subKey.primaryKeyPacket;
        }
    }

    return nil;
}

// signature packet that is available for signing data
- (PGPPacket *) encryptionKeyPacket
{
    NSAssert(self.type == PGPKeyPublic, @"Need public key to encrypt");
    if (self.type == PGPKeySecret) {
        NSLog(@"Need public key to encrypt");
        return nil;
    }
    
    for (PGPSubKey *subKey in self.subKeys) {
        PGPSignaturePacket *signaturePacket = subKey.bindingSignature;
        if (signaturePacket.canBeUsedToEncrypt) {
            return subKey.primaryKeyPacket;
        }
    }

    // check primary user self certificates
    PGPSignaturePacket *primaryUserSelfCertificate = nil;
    [self primaryUserAndSelfCertificate:&primaryUserSelfCertificate];
    if (primaryUserSelfCertificate)
    {
        if (primaryUserSelfCertificate.canBeUsedToEncrypt) {
            return self.primaryKeyPacket;
        }
    }
    
    return nil;
}

- (PGPSecretKeyPacket *) decryptionKeyPacket
{
    NSAssert(self.type == PGPKeySecret, @"Need secret key to encrypt");
    if (self.type == PGPKeyPublic) {
        NSLog(@"Need public key to encrypt");
        return nil;
    }
    
    for (PGPSubKey *subKey in self.subKeys) {
        PGPSignaturePacket *signaturePacket = subKey.bindingSignature;
        if (signaturePacket.canBeUsedToEncrypt) {
            return (PGPSecretKeyPacket *)subKey.primaryKeyPacket;
        }
    }
    
    // check primary user self certificates
    PGPSignaturePacket *primaryUserSelfCertificate = nil;
    [self primaryUserAndSelfCertificate:&primaryUserSelfCertificate];
    if (primaryUserSelfCertificate)
    {
        if (primaryUserSelfCertificate.canBeUsedToEncrypt) {
            return (PGPSecretKeyPacket *)self.primaryKeyPacket;
        }
    }
    
    return nil;
}

// Note: After decryption encrypted packets are replaced with new decrypted instances on key.
- (BOOL) decrypt:(NSString *)passphrase error:(NSError *__autoreleasing *)error
{
    if ([self.primaryKeyPacket isKindOfClass:[PGPSecretKeyPacket class]]) {
        PGPSecretKeyPacket *secretPacket = (PGPSecretKeyPacket *)self.primaryKeyPacket;
        self.primaryKeyPacket = [secretPacket decryptedKeyPacket:passphrase error:error];
        if (*error) {
            return NO;
        }
    }

    for (PGPSubKey *subKey in self.subKeys) {
        if ([subKey.primaryKeyPacket isKindOfClass:[PGPSecretKeyPacket class]]) {
            PGPSecretKeyPacket *secretPacket = (PGPSecretKeyPacket *)subKey.primaryKeyPacket;
            self.primaryKeyPacket = [secretPacket decryptedKeyPacket:passphrase error:error];
            if (*error) {
                return NO;
            }
        }
    }
    return YES;
}

- (NSData *) export:(NSError *__autoreleasing *)error
{
    NSMutableData *result = [NSMutableData data];

    for (PGPPacket * packet in [self allPacketsArray]) {
        [result appendData:[packet exportPacket:error]]; //TODO: decode secret key first
        NSAssert(!*error,@"Error while export public key");
        if (*error) {
            return nil;
        }
    }
    return [result copy];
}

#pragma mark - Verification

// Returns primary user with self certificate
- (PGPUser *) primaryUserAndSelfCertificate:(PGPSignaturePacket * __autoreleasing *)selfCertificateOut
{
    PGPUser *foundUser = nil;

    for (PGPUser *user in self.users) {
        if (!user.userID || user.userID.length == 0) {
            continue;
        }

        PGPSignaturePacket *selfCertificate = [user validSelfCertificate:self];
        if (!selfCertificate) {
            continue;
        }

        if (selfCertificate.isPrimaryUserID) {
            foundUser = user;
        } else if (!foundUser) {
            foundUser = user;
        }
        *selfCertificateOut = selfCertificate;
    }
    return foundUser;
}

#pragma mark - Preferences

- (PGPSymmetricAlgorithm) preferredSymmetricAlgorithm
{
    return [[self class] preferredSymmetricAlgorithmForKeys:@[self]];
}

+ (PGPSymmetricAlgorithm) preferredSymmetricAlgorithmForKeys:(NSArray *)keys
{
    // 13.2.  Symmetric Algorithm Preferences
    // Since TripleDES is the MUST-implement algorithm, if it is not explicitly in the list, it is tacitly at the end.

    NSMutableArray *preferecesArray = [NSMutableArray array];
    for (PGPKey *key in keys) {
        NSMutableArray *keyAlgorithms = [NSMutableArray array];
        
        PGPSignaturePacket *selfCertificate = nil;
        PGPUser *primaryUser = [key primaryUserAndSelfCertificate:&selfCertificate];
        if (primaryUser && selfCertificate) {
            PGPSignatureSubpacket *subpacket = [[selfCertificate subpacketsOfType:PGPSignatureSubpacketTypePreferredSymetricAlgorithm] firstObject];
            NSArray *preferencesArray = subpacket.value;
            for (NSValue *preferedValue in preferencesArray) {
                if ([preferedValue objCTypeIsEqualTo:@encode(PGPSymmetricAlgorithm)]) {
                    PGPSymmetricAlgorithm algorithm = PGPSymmetricPlaintext;
                    [preferedValue getValue:&algorithm];
                    [keyAlgorithms addObject:@(algorithm)];
                }
            }
        }
        
        if (keyAlgorithms.count > 0) {
            [preferecesArray addObject:keyAlgorithms];
        }
    }
    
    // intersect
    if (preferecesArray.count > 0) {
        NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSetWithArray:preferecesArray[0]];
        for (NSArray *prefArray in preferecesArray) {
            [set intersectSet:[NSSet setWithArray:prefArray]];
        }
        return [set[0] unsignedIntValue];
    }
    
    return PGPSymmetricTripleDES;
}

#pragma mark - Private

/**
 *  Ordered list of packets. Trust Packet is not exported.
 *
 *  @return array
 */
- (NSArray *)allPacketsArray
{
    //TODO: handle trust packet somehow. The Trust packet is used only within keyrings and is not normally exported.
    NSMutableArray *arr = [NSMutableArray array];

    [arr addObject:self.primaryKeyPacket];

    if (self.revocationSignature) {
        [arr addObject:self.revocationSignature];
    }

    for (id packet in self.directSignatures) {
        [arr addObject:packet];
    }

    for (PGPUser *user in self.users) {
        [arr addObjectsFromArray:[user allPackets]];
    }

    for (PGPSubKey *subKey in self.subKeys) {
        [arr addObjectsFromArray:[subKey allPackets]];
    }

    return [arr copy];
}

- (NSArray *)allKeyPackets
{
    NSMutableArray *arr = [NSMutableArray arrayWithObject:self.primaryKeyPacket];
    for (PGPSubKey *subKey in self.subKeys) {
        [arr addObject:subKey.primaryKeyPacket];
    }
    return [arr copy];
}

@end
