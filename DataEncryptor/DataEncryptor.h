//
//  DataEncryptor.h
//  Kashoo
//
//  Created by Ben Kennedy on 24-10-2013.
//  Copyright (c) 2013 Kashoo Cloud Accounting Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DataEncryptor : NSObject

- (instancetype)init NS_UNAVAILABLE;
- initWithX509URL:(NSURL *)x509url;

- (NSData *)compressData:(NSData *)plaintext;
- (NSData *)encryptData:(NSData *)plaintext;

@property (nonatomic, readonly) NSData *encryptedSymmetricKey;

@end
