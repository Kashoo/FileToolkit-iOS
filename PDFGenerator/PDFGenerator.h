//
//  PDFGenerator.h
//  FileToolkit
//
//  Copyright 2013 Kashoo Cloud Accounting Inc.
//  Copyright 2018 Kashoo Systems Inc.

@import Foundation;
@import WebKit;

@interface PDFGenerator : NSObject

@property (nonatomic, strong) NSString *sourceHTML;
@property (nonatomic, strong) WKWebView *sourceWebView;
@property (nonatomic, assign) BOOL makeClickableLinks;

- (void)generatePDFWithCompletion:(void (^)(NSData *pdfData))completionBlock;
- (void)generateImageWithCompletion:(void (^)(UIImage *image))completionBlock;

@end
