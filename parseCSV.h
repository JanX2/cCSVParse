/*
 * cCSVParse, a small CVS file parser
 *
 * © 2007-2009 Michael Stapelberg and contributors
 * http://michael.stapelberg.de/
 *
 * This source code is BSD-licensed, see LICENSE for the complete license.
 *
 */
#import <Cocoa/Cocoa.h>

@interface CSVParser:NSObject 
-(id)init;
-(BOOL)openFile:(NSString*)fileName;
-(void)closeFile;
-(char)autodetectDelimiter;
-(char)delimiter;
-(void)setDelimiter:(char)newDelimiter;
-(NSString *)delimiterString;
-(void)setBufferSize:(int)newBufferSize;
-(NSString *)endOfLine;
-(NSMutableArray*)parseFile;
-(NSMutableArray *)parseData:(NSData *)data;
-(void)setEncoding:(NSStringEncoding)newEncoding;
-(BOOL)verbose;
-(void)setVerbose:(BOOL)value;
@end
