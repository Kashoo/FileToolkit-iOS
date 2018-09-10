# DataEncryptor

DataEncryptor is a lightweight utility for compressing and encrypting an arbitrary payload. It employs gzip compression and AES data encryption to a piece of data using a randomly-generated and RSA asymmetrically-encrypted key.

## Usage

```objc
DataEncryptor *encryptor = [[DataEncryptor alloc] initWithX509URL:[[NSBundle mainBundle] URLForResource:@"my_public_key.der" withExtension:nil]];
NSData *compressedData = [encryptor compressData:plaintextData];
NSData *encryptedData = [encryptor encryptData:compressedData];
NSString *encryptedSymmetricKey = [encryptor.encryptedSymmetricKey base64EncodedStringWithOptions:0L];
```

See notes atop [DataEncryptor.m](./DataEncryptor/DataEncryptor.m) for key setup and decryption steps.

## Current limitations

Decryption and decompression is achievable using standard Mac OS system tools, but DataEncryptor does not provide related API. This would be an obvious improvement.
