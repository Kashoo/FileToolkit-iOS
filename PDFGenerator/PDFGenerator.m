//
//  PDFGenerator.m
//  FileToolkit
//
//  Copyright 2013 Kashoo Cloud Accounting Inc.
//  Copyright 2018 Kashoo Systems Inc.

#import "PDFGenerator.h"

@interface PDFGenerator() <WKNavigationDelegate>

@property (nonatomic, copy) void (^pdfCompletionBlock)(NSData *pdfData);
@property (nonatomic, copy) void (^imageCompletionBlock)(UIImage *image);

@end

@implementation PDFGenerator

- (instancetype)init
{
    if ((self = [super init]))
    {
        _makeClickableLinks = YES;
    }
    
    return self;
}

- (void)generatePDFWithCompletion:(void (^)(NSData *))completionBlock
{
    self.pdfCompletionBlock = completionBlock;
    self.imageCompletionBlock = nil;
    [self generate];
}

- (void)generateImageWithCompletion:(void (^)(UIImage *))completionBlock
{
    self.pdfCompletionBlock = nil;
    self.imageCompletionBlock = completionBlock;
    [self generate];
}

- (void)generate
{
    if (self.sourceHTML)
    {
        if (!self.sourceWebView)
        {
            WKWebView *generatorWebView = [[WKWebView alloc] init];
            generatorWebView.navigationDelegate = self;
            generatorWebView.backgroundColor = [UIColor clearColor];
            generatorWebView.opaque = NO;
            self.sourceWebView = generatorWebView;
        }
        
        [self.sourceWebView loadHTMLString:self.sourceHTML baseURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] resourcePath]]];
    }
    
    else
    {
        [self renderPDFAndComplete];
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    [self renderPDFAndComplete];
}

- (void)renderPDFAndComplete
{
    const CGRect paperRect = CGRectMake(0, 0, 612.0f, 792.0f); // Your choice of paper format, as long as it's US Letter in portrait.
    const CGRect printableRect = CGRectInset(paperRect, 20.0f, 20.0f);

    UIPrintPageRenderer *pageRenderer = [[UIPrintPageRenderer alloc] init];
    [pageRenderer setValue:[NSValue valueWithCGRect:paperRect] forKey:NSStringFromSelector(@selector(paperRect))];
    [pageRenderer setValue:[NSValue valueWithCGRect:printableRect] forKey:NSStringFromSelector(@selector(printableRect))];
    [pageRenderer addPrintFormatter:self.sourceWebView.viewPrintFormatter startingAtPageAtIndex:0];
    [pageRenderer prepareForDrawingPages:NSMakeRange(0, (NSUInteger)pageRenderer.numberOfPages)];

    if (self.pdfCompletionBlock)
    {
        NSMutableData *pdfData = [[NSMutableData alloc] init];
        UIGraphicsBeginPDFContextToData(pdfData, paperRect, nil);
    
        // Get the actually-rendered body size in pixels, and calculate a scaling transform to map DOM coordinates into PDF page space.
        [self.sourceWebView evaluateJavaScript:@"r = document.body.getBoundingClientRect(); rs = '{{'+r.left+','+r.top+'},{'+r.width+','+r.height+'}}';"
                             completionHandler:^(NSString *bodyRectString, NSError *jsEvalError1)
         {
             CGFloat bodyWidth = CGRectFromString(bodyRectString).size.width;
             CGFloat scaleFactor = printableRect.size.width / bodyWidth;
             CGAffineTransform rectTransform = CGAffineTransformMakeTranslation(printableRect.origin.x - paperRect.origin.x, printableRect.origin.y - paperRect.origin.y);
             rectTransform = CGAffineTransformScale(rectTransform, scaleFactor, scaleFactor);
             
             NSString *javascript;
             if (self.makeClickableLinks)
             {
                 // Iterate the links ('A' elements) in the HTML in order to retrieve their URLs and corresponding active link rectangles.
                 NSURL *javascriptURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"PDFGeneratorCollectLinksInHTML" withExtension:@"js"];
                 javascript = [NSString stringWithContentsOfURL:javascriptURL encoding:NSUTF8StringEncoding error:nil];
             }
             else
             {
                 javascript = [NSString string];
             }
             
             [self.sourceWebView evaluateJavaScript:javascript
                                  completionHandler:^(NSArray *linkInfoArray, NSError *jsEvalError2)
              {
                  for (NSInteger i=0; i < pageRenderer.numberOfPages; ++i)
                  {
                      UIGraphicsBeginPDFPage();
                      [pageRenderer drawPageAtIndex:i inRect:paperRect];
                      
                      for (NSDictionary *obj in linkInfoArray) // the collection will be nil if makeClickableLinks == NO.
                      {
                          NSString *url = obj[@"href"];
                          CGRect r = CGRectFromString(obj[@"rect"]);
                          
                          // Apply the transform to put the rect into PDF page space.
                          r = CGRectApplyAffineTransform(r, rectTransform);
                          
                          // Adjust for page offset.
                          r.origin.y -= printableRect.size.height * i;
                          
                          // Invert the rect since the CG coordinate space is flipped.
                          r.origin.y = paperRect.size.height - r.origin.y - r.size.height;
                          
                          if (CGRectIntersectsRect(r, paperRect))
                          {
                              UIGraphicsSetPDFContextURLForRect([NSURL URLWithString:url], r);
                          }
                      }
                  }
                  
                  UIGraphicsEndPDFContext();
                  
                  self.pdfCompletionBlock(pdfData);
              }];
         }];
    }
    
    else if (self.imageCompletionBlock)
    {
        // Render the PDF into an image suitable for display to the current screen (in regard of its scale factor).
        UIGraphicsBeginImageContextWithOptions(paperRect.size, YES, [[UIScreen mainScreen] scale]);
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSaveGState(context);
        
        CGContextSetGrayFillColor(context, 1.0, 1.0);
        CGContextFillRect(context, paperRect);
        
        [pageRenderer prepareForDrawingPages:NSMakeRange(0, 1)];
        [pageRenderer drawPageAtIndex:0 inRect:paperRect];
        
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        
        CGContextRestoreGState(context);
        UIGraphicsEndImageContext();
        
        self.imageCompletionBlock(image);
    }
}

@end
