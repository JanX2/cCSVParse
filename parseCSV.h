/*
 * cCSVParse, a small CVS file parser
 *
 * © 2007-2015 Jan Weiß, Michael Stapelberg and contributors
 * https://github.com/JanX2/cCSVParse
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

+(NSArray *)supportedDelimiters;
+(NSArray *)supportedDelimiterLocalizedNames;

+(NSArray *)supportedLineEndings;
+(NSArray *)supportedLineEndingLocalizedNames;

-(NSMutableArray*)parseFile;
-(NSMutableArray *)parseData;
-(NSMutableArray *)parseData:(NSData *)data;

@property (nonatomic, copy) NSData *data;

@property (nonatomic, assign) char delimiter;
@property (nonatomic, assign) NSStringEncoding encoding;
@property (nonatomic, assign) BOOL foundQuotedCell;

@property (nonatomic, copy) NSString *delimiterString;
@property (nonatomic, copy) NSString *endOfLine;

@property (nonatomic, assign) size_t bufferSize;

@property (nonatomic, assign) BOOL verbose;

@end
