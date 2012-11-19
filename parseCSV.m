/*
 * cCSVParse, a small CVS file parser
 *
 * © 2007-2009 Michael Stapelberg and contributors
 * http://michael.stapelberg.de/
 *
 * This source code is BSD-licensed, see LICENSE for the complete license.
 *
 */
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <stdbool.h>
#include <unistd.h>
#include <stdint.h>
#include <assert.h>

#import "parseCSV.h"

/* Macros for determining if the given character is End Of Line or not */
#define EOL(x) ((*(x) == '\r' || *(x) == '\n') && *(x) != '\0')
#define NOT_EOL(x) (*(x) != '\0' && *(x) != '\r' && *(x) != '\n')

char possibleDelimiters[4] = ",;\t\0";
//char possibleDelimiters[5] = ",;|\t\0";

/*
 * replacement for strstr() which does only check every char instead
 * of complete strings
 * Warning: Do not call it with haystack == NULL || needle == NULL!
 *
 */
static char *cstrstr(const char *haystack, const char needle) {
	char *it = (char*)haystack;
	while (*it != '\0') {
		if (*it == needle)
			return it;
		it++;
	}
	return NULL;
}

char searchDelimiter(char *textp) {
	char delimiter = '\n';
	
	// ...we assume that this is the header which also contains the separation character
	while (NOT_EOL(textp) && cstrstr(possibleDelimiters, *textp) == NULL)
		textp++;
	
	// Check if a delimiter was found and set it
	if (NOT_EOL(textp)) {
		delimiter = *cstrstr((const char*)possibleDelimiters, *textp);
		return delimiter;
	}
	else {
		return 0;
	}
}

/*
 * Copies a string without beginning- and end-quotes if there are
 * any and returns a pointer to the string or NULL if malloc() failed
 *
 */
NSString * parseString(char *textp, char *laststop, NSStringEncoding encoding) {
	NSUInteger stringSize = (size_t)(textp - laststop);
	
	if (*laststop == '\"' && *(laststop+1) != '\0' && *(laststop + stringSize - 1) == '\"') {
		laststop++;
		stringSize -= 2;
	}
	
	NSMutableString *tempString = [[NSMutableString alloc] initWithBytes:laststop
																  length:stringSize
																encoding:encoding];
	
	[tempString replaceOccurrencesOfString:@"\"\"" 
								withString:@"\"" 
								   options:0
									 range:NSMakeRange(0, [tempString length])];
	
	return [tempString autorelease];
}


@implementation CSVParser {
	int fileHandle;
	size_t bufferSize;
	char delimiter;
	char endOfLine[3];
	NSStringEncoding encoding;
	BOOL verbose;
	BOOL fileMode;
	NSData *_data;
}

-(void)setData:(NSData *)value {
    if (_data != value) {
        [_data release];
        _data = [value copy];
    }
}

-(id)init {
	self = [super init];
	if (self) {
		// Set default bufferSize
		bufferSize = 2048;
		// Set fileHandle to an invalid value
		fileHandle = 0;
		// Set delimiter to 0
		delimiter = '\0';
		// Set endOfLine to empty
		endOfLine[0] = '\0';
		endOfLine[1] = '\0';
		endOfLine[2] = '\0';
		// Set default encoding
		encoding = NSISOLatin1StringEncoding;
		// Set default verbosity
		verbose = NO;
		
		_data = nil;
	}
	return self;
}

-(void)dealloc {
	[self closeFile];
	
	[self setData:nil]; 
	
	[super dealloc];
}




/*
 * Gets the CSV-delimiter from the given filename using the first line
 * which should be the header-line. Returns 0 on error.
 *
 */
-(char)autodetectDelimiter {
	char buffer[bufferSize+1];

	NSInteger n;
	
	if (fileMode) {
		// Seek to the beginning of the file
		lseek(fileHandle, 0, SEEK_SET);

		// Fill the buffer
		n = read(fileHandle, buffer, bufferSize);
	}
	else {
		assert(sizeof(uint8_t) == sizeof(char));
		NSInputStream *dataStream = [NSInputStream inputStreamWithData:_data];
		[dataStream open];
		
		n = [dataStream read:(uint8_t *)buffer maxLength:bufferSize];
		
		[dataStream close];
	}

	
	if (n > 0) {
		char *textp = buffer;
		return searchDelimiter(textp);
	}

	return 0;
}

-(NSMutableArray *)parseInto:(NSMutableArray *)csvContent
{
	NSMutableArray *csvLine = [NSMutableArray array];
	NSInputStream *dataStream = nil;
	

	ssize_t n = 1;
	size_t diff;
	NSUInteger lastColumnCount = 0;
	unsigned int quoteCount = 0;
	bool firstLine = true;
	bool addCurrentLineStartNew = false;
	size_t bufferCapacity = bufferSize + 1;
	size_t necessaryCapacity = 0;
	char *buffer = malloc(sizeof(char) * bufferCapacity);
	char *textp = NULL, *lastStop = NULL, *lineStart = NULL, *lastLineBuffer = NULL;
	
	if (fileMode) {
		lseek(fileHandle, 0, SEEK_SET);
	}
	else {
		assert(sizeof(uint8_t) == sizeof(char));
		dataStream = [NSInputStream inputStreamWithData:_data];
		[dataStream open];
	}

	while (n > 0) {
		
		if (lastLineBuffer != NULL) {
			
			if (strlen(lastLineBuffer) == bufferSize) {
				// CHANGEME: Recover from this
				[csvContent removeAllObjects];
				[csvContent addObject:[NSMutableArray arrayWithObject: @"ERROR: Buffer too small"]];
				return csvContent;
			}
			
			// Take care of the quotes in lastLineBuffer!
			textp = lastLineBuffer;
			while (*textp != '\0') {
				if (*textp == '\"')
					quoteCount++;
				textp++;
			}
			
			// Copy lastLineBuffer to the beginning of the buffer
			strcpy(buffer, lastLineBuffer);
			diff = strlen(lastLineBuffer);
			
			// Increase the buffer size so that the buffer can hold 
			// both lastLineBuffer and a block of bufferSize
			necessaryCapacity = diff + bufferSize;
			if (bufferCapacity < necessaryCapacity) {
				buffer = realloc(buffer, necessaryCapacity);
				if (buffer == NULL) {
					[csvContent removeAllObjects];
					[csvContent addObject:[NSMutableArray arrayWithObject: @"ERROR: Could not allocate bytes for buffer"]];
					return csvContent;
				}
				bufferCapacity = necessaryCapacity;
			}
			
			lastLineBuffer = NULL;
			
		} 
		else {
			diff = 0;
		}
		
		if (fileMode) {
			n = read(fileHandle, (buffer + diff), bufferSize);
		}
		else {
			n = [dataStream read:(uint8_t *)(buffer + diff) maxLength:bufferSize];
		}

		if (n <= 0)
			break;
		
		// Terminate buffer correctly
		if ((diff+n) <= (bufferSize + diff))
			buffer[diff+n] = '\0';
		
		textp = (char *)buffer;
		
		while (*textp != '\0') {
			// If we don't have a delimiter yet and this is the first line...
			if (firstLine && delimiter == '\0') {
				//firstLine = false;
				
				// Check if a delimiter was found and set it
				delimiter = searchDelimiter(textp);
				if (delimiter != 0) {
					if (verbose) {
						printf("delim is %c / %d :-)\n", delimiter, delimiter);
					}
					//while (NOT_EOL(textp))
					//	textp++;
				}
				
				textp = (char*)buffer;
			} 
			
			if (strlen(textp) > 0) {
				// This is data
				lastStop = textp;
				lineStart = textp;
				
				// Parsing is split into parts till EOL
				while (NOT_EOL(textp) || (*textp != '\0' && (quoteCount % 2) != 0)) {
					// If we got two quotes and a delimiter before and after, this is an empty value
					if (*textp == '\"') { 
						if (*(textp+1) == '\"') {
							// we'll just skip this
							textp++;
						} 
						else {
							quoteCount++;
						}
					} 
					else if (*textp == delimiter && (quoteCount % 2) == 0) {
						// This is a delimiter which is not between an unmachted pair of quotes
						[csvLine addObject:parseString(textp, lastStop, encoding)];
						lastStop = textp + 1;
					}
					
					// Go to the next character
					textp++;
				}
				
				addCurrentLineStartNew = false;
				
				if (lastStop == textp && *(textp-1) == delimiter) {
					[csvLine addObject:@""];
					
					addCurrentLineStartNew = true;
				}
				else if (lastStop != textp && (quoteCount % 2) == 0) {
					[csvLine addObject:parseString(textp, lastStop, encoding)];
					
					addCurrentLineStartNew = true;
				} 
				
				if (addCurrentLineStartNew) {
					if ((int)(buffer + bufferSize + diff - textp) > 0) {
						lineStart = textp + 1;
						[csvContent addObject:csvLine];
						lastColumnCount = [csvLine count];
					}
					csvLine = [NSMutableArray arrayWithCapacity:lastColumnCount]; // convenience methods always autorelease
				}
				
				if ((*textp == '\0' || (quoteCount % 2) != 0) && lineStart != textp) {
					lastLineBuffer = lineStart;
					csvLine = [NSMutableArray arrayWithCapacity:lastColumnCount];
				}
			}
			
			if (firstLine) {
				if ( (lineStart != NULL) && (lineStart-1 >= buffer) && EOL(lineStart-1) ) {
					endOfLine[0] = *(lineStart-1);

					if ( EOL(lineStart) ) {
						endOfLine[1] = *(lineStart);
					}
				}
				
				firstLine = false;
			}
			
			while (EOL(textp))
				textp++;
		}
	}
	
	free(buffer);
	buffer = NULL;

	if (!fileMode) {
		[dataStream close];
	}

	return csvContent;
}

/*
 * Parses the CSV-file with the given filename and stores the result in a
 * NSMutableArray.
 *
 */
-(NSMutableArray*)parseFile {
	NSMutableArray *csvContent = [NSMutableArray array];

	if (fileHandle <= 0)
		return [NSMutableArray array];
	
	return [self parseInto:csvContent];

}

/*
 * Parses the CSV-file with the given filename and stores the result in a
 * NSMutableArray.
 *
 */
-(NSMutableArray *)parseData:(NSData *)data
{
	NSMutableArray *csvContent = [NSMutableArray array];

	fileMode = NO;
	
	if (data != nil) {
		[self setData:data];

		[self parseInto:csvContent];

		return csvContent;
	}
	else {
		return csvContent;
	}

	
}

-(BOOL)openFile:(NSString*)fileName {
	fileMode = YES;
	fileHandle = open([fileName UTF8String], O_RDONLY);
	return (fileHandle > 0);
}

-(void)closeFile {
	if (fileHandle > 0) {
		close(fileHandle);
		fileHandle = 0;
	}
}

-(char)delimiter {
	return delimiter;
}

-(void)setDelimiter:(char)newDelimiter {
	delimiter = newDelimiter;
}

-(NSString *)delimiterString {
	char delimiterCString[2] = {'\0', '\0'};
	delimiterCString[0] = delimiter;
    return [NSString stringWithCString:delimiterCString encoding:encoding];
}

-(void)setBufferSize:(int)newBufferSize {
	bufferSize = newBufferSize;
}

-(NSString *)endOfLine {
    return [NSString stringWithCString:endOfLine encoding:encoding];
}

-(void)setEncoding:(NSStringEncoding)newEncoding {
	encoding = newEncoding;
}

-(BOOL)verbose {
    return verbose;
}

-(void)setVerbose:(BOOL)value {
    if (verbose != value) {
        verbose = value;
    }
}

@end
