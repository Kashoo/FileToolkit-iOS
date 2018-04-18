/*
 * collectLinksInHTMLDocument.js - created 11 May 2015 by Ben Kennedy.
 *
 * This JS combs all the links in the current HTML document and implicitly returns a constant array describing the links and their bounding rectangles in the rendered document.
 * A fundamental helper component of PDFGenerator.m (q.v.). An elegantly grotesque and somewhat dubious way of achieving the required end? Why yes!
 */

var links = [];

for (var i=0; i < document.links.length; ++i)
{
    var link = document.links[i];
    var r = link.getBoundingClientRect();
    
    var link = {
        'href' : link.href,
        'rect' : '{{'+r.left+','+r.top+'},{'+r.width+','+r.height+'}}',
    };
    
    links[i] = link;
}

links;
