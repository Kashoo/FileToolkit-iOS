# PDFGenerator

PDFGenerator renders an HTML document as a PDF file, optionally with embedded clickable links. It will also produce a PNG representation of the first page.

## Usage

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

## Current limitations

- Page size is fixed at US Letter.
