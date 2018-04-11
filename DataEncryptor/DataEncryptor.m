//
//  DataEncryptor.m
//  Kashoo
//
//  Created by Ben Kennedy on 24-10-2013.
//  Copyright (c) 2013 Kashoo Cloud Accounting Inc. All rights reserved.
//
//  A lightweight utility for applying gzip compression and AES data encryption to a piece of data,
//  with a randomly-generated and RSA asymmetrically-encrypted key.
//
//  References:
//  - https://developer.apple.com/library/mac/documentation/security/conceptual/certkeytrustprogguide/CertKeyTrustProgGuide.pdf
//  - https://github.com/xjunior/XRSA/
//  - http://homes.cs.washington.edu/~aczeskis/random/openssl-encrypt-file.html

/*****

INITIAL PROJECT SETUP:

One-time initial setup requires the creation of an asymmetric key pair.  Generate public (DER format) and private (PEM format) keys,
with high security and arbitrarily lengthy expiration.  This is done in two steps since during creation a private key password is mandated
(it does not appear possible to create one sans); the second step strips the password:

    openssl req -x509 -out ./Kashoo_iPad_public_key.der -outform der -new -newkey rsa:2048 -passout pass:Kash00key01nk -keyout /tmp/tmp.pem -days 3650
    openssl rsa -passin pass:Kash00key01nk -in /tmp/tmp.pem -out ./Kashoo_iPad_private_key.pem

Note: DO NOT build the private key into the app bundle!

USAGE (ENCRYPTION):

1. Alloc an instance of DataEncryptor, passing in the public key.
2. Retrieve the randomly-generated asymmetrically-encrypted symmetric key with -encryptedSymmetricKey.
3. Call -encryptData: (and optionally, -compressData: beforehand) on one or more pieces of data.
4. Store the encrypted symmetric key alongside the encrypted data.

HOW TO DECRYPT:

1. Decrypt the symmetric key using the asymmetric private key.  This can be achieved using 'openssl rsautl'.
2. Decrypt the payload using the symmetric key and a zero IV.  This can be achieved using 'openssl enc -d'.
3. Optionally, decompress the payload if required.  This can be achieved using 'gzip -d'.

See the accompanying DataDecryptor.sh for a one-step decoding facility.

*****/


#import "DataEncryptor.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <zlib.h>

@interface DataEncryptor()
{
    SecCertificateRef certificate;
    SecPolicyRef policy;
    SecTrustRef trust;
    SecKeyRef publicKey;
}

@property (nonatomic, readonly) NSData *plaintextSymmetricKey;

@end


@implementation DataEncryptor

- initWithX509URL:(NSURL *)x509url
{
    if ((self = [super init]))
    {
        NSError *error;
        OSStatus status;
        NSData *derKeyData;
        
        // Initialize the asymmetric key system with which we will encrypt a randomly-generated symmetric key.
        
        if (!(derKeyData = [NSData dataWithContentsOfURL:x509url options:0L error:&error]))
        {
            NSLog(@"%s: failed to load X509 from %@", __PRETTY_FUNCTION__, x509url.absoluteString);
            [self cleanup];
            return (self = nil);
        }

        if (!(self->certificate = SecCertificateCreateWithData(kCFAllocatorDefault, (__bridge CFDataRef)derKeyData)))
        {
            NSLog(@"%s: failed to create certificate from data", __PRETTY_FUNCTION__);
            return (self = nil);
        }
        
        self->policy = SecPolicyCreateBasicX509();
        status = SecTrustCreateWithCertificates(self->certificate, self->policy, &self->trust);
        if (status != 0)
        {
            NSLog(@"%s: failed to create trust from certificate and policy (status %d)", __PRETTY_FUNCTION__, (int)status);
            return (self = nil);
        }
        
        if (!(self->publicKey = SecTrustCopyPublicKey(self->trust)))
        {
            NSLog(@"%s: failed to copy public key from trust", __PRETTY_FUNCTION__);
            return (self = nil);
        }

        // Generate a random symmetric key which will be used for AES-encrypting the payload data.

        size_t cipherBlockLen = SecKeyGetBlockSize(self->publicKey);
        void *cipherBlock = malloc(cipherBlockLen);
        
        size_t plainBlockLen = MIN((size_t)kCCKeySizeAES256, cipherBlockLen - 11);
        void *plainBlock = malloc(plainBlockLen);

        if (SecRandomCopyBytes(kSecRandomDefault, plainBlockLen, plainBlock) != noErr)
        {
            NSLog(@"%s: failed to generate random cryptographic key (error %d)", __PRETTY_FUNCTION__, errno);
            free(cipherBlock);
            free(plainBlock);
            [self cleanup];
            return (self = nil);
        }

        status = SecKeyEncrypt(self->publicKey, kSecPaddingPKCS1, plainBlock, plainBlockLen, cipherBlock, &cipherBlockLen);
        if (status != noErr)
        {
            NSLog(@"%s: failed to encrypt the symmetric key (status %d)", __PRETTY_FUNCTION__, (int)status);
            free(cipherBlock);
            free(plainBlock);
            [self cleanup];
            return (self = nil);
        }

        _plaintextSymmetricKey = [[NSData alloc] initWithBytesNoCopy:plainBlock length:plainBlockLen freeWhenDone:YES];
        _encryptedSymmetricKey = [[NSData alloc] initWithBytesNoCopy:cipherBlock length:cipherBlockLen freeWhenDone:YES];
    }

    return self;
}

- (void)dealloc
{
    [self cleanup];
}

- (void)cleanup
{
    if (self->certificate)
    {
        CFRelease(self->certificate);
        self->certificate = nil;
    }
    if (self->trust)
    {
        CFRelease(self->trust);
        self->trust = nil;
    }
    if (self->policy)
    {
        CFRelease(self->policy);
        self->policy = nil;
    }
    if (self->publicKey)
    {
        CFRelease(self->publicKey);
        self->publicKey = nil;
    }
}


- (NSData *)encryptData:(NSData *)plaintextData
{
    size_t cipherBufLen = plaintextData.length + kCCBlockSizeAES128;
    void *cipherBuf = malloc(cipherBufLen);
    
    if (!cipherBuf)
    {
        NSLog(@"%s: failed to malloc output buffer of %ld", __PRETTY_FUNCTION__, cipherBufLen);
        return nil;
    }
    
    // Encrypt the payload using the symmetric key.
    
    CCCryptorStatus status = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                     self.plaintextSymmetricKey.bytes, self.plaintextSymmetricKey.length, NULL,
                                     plaintextData.bytes, plaintextData.length, cipherBuf, cipherBufLen, &cipherBufLen);
    
    if (status != kCCSuccess)
    {
        NSLog(@"%s: encryption failed (status %d)", __PRETTY_FUNCTION__, status);
        free(cipherBuf);
        return nil;
    }

    return [NSData dataWithBytesNoCopy:cipherBuf length:cipherBufLen freeWhenDone:YES];
}



// Gzip deflate based on http://stackoverflow.com/questions/8425012/is-there-a-practical-way-to-compress-nsdata :

- (NSData *)compressData:(NSData *)plaintext
{
    int result;
    z_stream strm;
    
    #define Z_BLOCK_SIZE 16384
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    strm.total_out = 0;
    strm.next_in = (Bytef *)plaintext.bytes;
    strm.avail_in = (uInt)plaintext.length;

    if (plaintext.length == 0)
    {
        return plaintext;
    }
    
    result = deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, (15+16), 8, Z_DEFAULT_STRATEGY);
    if (result != Z_OK)
    {
        NSLog(@"%s: failed to initialize zlib deflate (%d)", __PRETTY_FUNCTION__, result);
        return nil;
    }
    
    NSMutableData *compressed = [NSMutableData dataWithLength:Z_BLOCK_SIZE];
    
    do
    {
        if (strm.total_out >= compressed.length)
        {
            [compressed increaseLengthBy:Z_BLOCK_SIZE];
        }
        
        strm.next_out = compressed.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(compressed.length - strm.total_out);
        
        deflate(&strm, Z_FINISH);
        
    } while (strm.avail_out == 0);
    
    deflateEnd(&strm);
    
    [compressed setLength:strm.total_out];
    
    return compressed;
}

@end
