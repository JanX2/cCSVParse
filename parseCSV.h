/*
 * cCSVParse, a small CVS file parser
 *
 * © 2007-2009 Michael Stapelberg and contributors
 * http://michael.stapelberg.de/
 *
 * This source code is BSD-licensed, see LICENSE for the complete license.
 *
 */

#if TARGET_OS_IPHONE
	#import <UIKit/UIKit.h>
#else
	#import <Cocoa/Cocoa.h>
#endif

@interface CSVParser:NSObject 
-(id)init;
-(BOOL)openFile:(NSString*)fileName;
-(void)closeFile;
-(char)autodetectDelimiter;
-(NSString *)delimiterString;
-(NSString *)endOfLine;
-(NSMutableArray*)parseFile;
-(NSMutableArray *)parseData;
-(NSMutableArray *)parseData:(NSData *)data;

@property (assign) char delimiter;
@property (assign) NSStringEncoding encoding;

@property (assign) size_t bufferSize;

@property (assign) BOOL verbose;

@end
