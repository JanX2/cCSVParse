/*
 * CSV Parser
 * (c) 2007 Michael Stapelberg
 * http://michael.stapelberg.de/
 *
 * BSD License
 *
 */

#import <Cocoa/Cocoa.h>

@interface CSVParser:NSObject {
	int fileHandle;
	int bufferSize;
	char delimiter;
	NSStringEncoding encoding;
}
-(id)init;
-(BOOL)openFile:(NSString*)fileName;
-(void)closeFile;
-(char)autodetectDelimiter;
-(char)delimiter;
-(void)setDelimiter:(char)newDelimiter;
-(void)setBufferSize:(int)newBufferSize;
-(NSMutableArray*)parseFile;
-(void)setEncoding:(NSStringEncoding)newEncoding;
@end
