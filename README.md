#  Kashoo FileToolkit

Herein lies a varied collection of file-related utilities all variously employed in the [Kashoo](http://www.kashoo.com) iOS app.

The bulk of this code was originally written by [Ben Kennedy](https://github.com/zygoat/) on behalf (and copyright) of Kashoo Systems Inc., and is offered for general use and enrichment under the [MIT License](./LICENSE.md).

### Table of contents:

- [BlobStore](#BlobStore) — Manages the upload, download, and caching of arbitrary data with a remote file server.
- [BrickUploader](#BrickUploader) — Coordinates the upload of data to [BrickFTP](http://www.brickftp.com) using its REST API.
- [DataEncryptor](#DataEncryptor) — A lightweight utility for compressing and encrypting an arbitrary payload.
- [PDFGenerator](#PDFGenerator) — Renders an HTML document as a PDF file, and produces a PNG of its first page.

The included [xcworkspace](./FileToolkit.xcworkspace) provides unit tests for all projects. [CocoaPods](http://www.cocoapods.org) is required.


<hr>
## <a name="BlobStore"></a>BlobStore

BlobStore provides abstract and concrete interfaces for the upload, download, and caching of arbitrary and named raw data with a remote file server.

Features:

- synchronous and asynchronous API
- local caching, with automatic cache management
- preservation of original filename and MIME type

See [BlobStore.swift](./BlobStore/BlobStore.swift) protocol for overview. Further description forthcoming.


<hr>
## <a name="BrickUploader"></a>BrickUploader

BrickUploader coordinates the upload of data to [BrickFTP](http://www.brickftp.com) using its [REST API](https://developers.brickftp.com/#file-uploading).

### Usage

```swift
let uploader = BrickUploader(with: SessionManager(),
                             baseURL: "https://example.brickftp.com",
                             apiKey: "1234567890")

uploader.progressHandler = { (completed, ofTotal) in
    print("Uploaded \(completed) of \(ofTotal) bytes")
}

let url = URL(fileURLWithPath: "/tmp/source.txt")
let path = ["dir1", "dir2", "destination.txt"]

uploader.upload(file: url, to: path) { completed, error in
    guard error == nil else {
        print("Uh oh: \(error.localizedDescription)")
    }
}
```

<hr>
## <a name="DataEncryptor"></a>DataEncryptor

DataEncryptor is a lightweight utility for compressing and encrypting an arbitrary payload. It employs gzip compression and AES data encryption to a piece of data using a randomly-generated and RSA asymmetrically-encrypted key.

### Usage

```objc
DataEncryptor *encryptor = [[DataEncryptor alloc] initWithX509URL:[[NSBundle mainBundle] URLForResource:@"my_public_key.der" withExtension:nil]];
NSData *compressedData = [encryptor compressData:plaintextData];
NSData *encryptedData = [encryptor encryptData:compressedData];
NSString *encryptedSymmetricKey = [encryptor.encryptedSymmetricKey base64EncodedStringWithOptions:0L];
```

See notes atop [DataEncryptor.m](./DataEncryptor/DataEncryptor.m) for key setup and decryption steps.

### Current limitations

Decryption and decompression is achievable using standard system tools, but DataEncryptor does not provide related API. This would be an obvious improvement.


<hr>
## <a name="PDFGenerator"></a>PDFGenerator

PDFGenerator renders an HTML document as a PDF file, optionally with embedded clickable links. It will also produce a PNG representation of the first page.

### Usage

```objc
PDFGenerator *generator = [[PDFGenerator alloc] init];
generator.sourceHTML = @"<html><body><p>This is a very trivial HTML example</p></body></html>";
generator.makeClickableLinks = YES;

[generator generatePDFWithCompletion:^(NSData *pdfData) {
	if (pdfData) {
		[pdfData writeToURL:[NSURL fileURLWithPath:@"/tmp/output.pdf"] atomically:YES];
	}
}];

[generator generateImageWithCompletion:^(UIImage *image) {
	if (image) {
		self.imageView.image = image;
	}
}];
```

### Current limitations

- Page size is fixed at US Letter.
