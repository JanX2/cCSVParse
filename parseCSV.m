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

//char possibleDelimiters[4] = ",;\t\0";
char possibleDelimiters[5] = ",;\t|\0";
NSString *possibleDelimiterNames[] = {
	@"Comma (,)",
	@"Semicolon (;)",
	@"Tab Symbol",
	@"Pipe Symbol (|)"
};
/* For genstrings:
 NSLocalizedString(@"Comma (,)", @"cCSVParseDelimiterNames")
 NSLocalizedString(@"Semicolon (;)", @"cCSVParseDelimiterNames")
 NSLocalizedString(@"Tab Symbol", @"cCSVParseDelimiterNames")
 NSLocalizedString(@"Pipe Symbol (|)" @"cCSVParseDelimiterNames")
 */


NSString *supportedLineEndings[] = {
	@"\n",
	@"\r",
	@"\r\n"
};

NSString *supportedLineEndingNames[] = {
	@"Unix/Mac OS X Line Endings (LF)",
	@"Classic Mac Line Endings (CR)",
	@"Windows Line Endings (CRLF)"
};
/* For genstrings:
 NSLocalizedString(@"Unix/Mac OS X Line Endings (LF)", @"cCSVParseLineEndingNames")
 NSLocalizedString(@"Classic Mac Line Endings (CR)", @"cCSVParseLineEndingNames")
 NSLocalizedString(@"Windows Line Endings (CRLF)", @"cCSVParseLineEndingNames")
 */


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
		delimiter = *cstrstr(possibleDelimiters, *textp);
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
								   options:NSLiteralSearch
									 range:NSMakeRange(0, [tempString length])];
	
	return [tempString autorelease];
}


@implementation CSVParser {
	int _fileHandle;
	char _endOfLine[3];
	BOOL _fileMode;
}

-(id)init {
	self = [super init];
	if (self) {
		// Set default _bufferSize
		_bufferSize = 2048;
		// Set fileHandle to an invalid value
		_fileHandle = 0;
		// Set delimiter to 0
		_delimiter = '\0';
		// Set endOfLine to empty
		_endOfLine[0] = '\0';
		_endOfLine[1] = '\0';
		_endOfLine[2] = '\0';
		// Set default encoding
		_encoding = NSISOLatin1StringEncoding;
		// Set default verbosity
		_verbose = NO;
		
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
	char buffer[_bufferSize];
	size_t bufferCharCount = _bufferSize - 1;
	
	NSInteger n;
	
	if (_fileMode) {
		// Seek to the beginning of the file
		lseek(_fileHandle, 0, SEEK_SET);

		// Fill the buffer
		n = read(_fileHandle, buffer, bufferCharCount);
	}
	else {
		assert(sizeof(uint8_t) == sizeof(char));
		NSInputStream *dataStream = [NSInputStream inputStreamWithData:_data];
		[dataStream open];
		
		n = [dataStream read:(uint8_t *)buffer maxLength:bufferCharCount];
		
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
	size_t lastLineLength = 0;
	NSUInteger lastColumnCount = 0;
	unsigned int quoteCount = 0;
	bool firstLine = true;
	bool addCurrentLineAndStartNew = false;
	size_t bufferSize = _bufferSize;
	size_t blockCharCount = bufferSize - 1;
	char *buffer = malloc(sizeof(char) * bufferSize);
	char *textp = NULL, *lastStop = NULL, *lineStart = NULL, *lastLineBuffer = NULL;
	
	if (_fileMode) {
		lseek(_fileHandle, 0, SEEK_SET);
	}
	else {
		assert(sizeof(uint8_t) == sizeof(char));
		dataStream = [NSInputStream inputStreamWithData:_data];
		[dataStream open];
	}

	while (n > 0) {
		
		if (lastLineBuffer != NULL) {
			lastLineLength = strlen(lastLineBuffer);
			
			// Take care of the quotes in lastLineBuffer!
			textp = lastLineBuffer;
			while (*textp != '\0') {
				if (*textp == '\"')
					quoteCount++;
				textp++;
			}
			
			// Increase the buffer size so that the buffer can hold 
			// both lastLineBuffer and a block of blockCharCount size
			size_t necessaryCapacity = (lastLineLength + blockCharCount) * sizeof(char);
			if (bufferSize < necessaryCapacity) {
				buffer = realloc(buffer, necessaryCapacity);
				if (buffer == NULL) {
					[csvContent removeAllObjects];
					[csvContent addObject:[NSMutableArray arrayWithObject: @"ERROR: Could not allocate bytes for buffer"]];
					return csvContent;
				}
				bufferSize = necessaryCapacity;
			}
			
			// Copy lastLineBuffer to the beginning of the buffer
			strcpy(buffer, lastLineBuffer);
			
			lastLineBuffer = NULL;
			
		} 
		else {
			lastLineLength = 0;
		}
		
		if (_fileMode) {
			n = read(_fileHandle, (buffer + lastLineLength), blockCharCount);
		}
		else {
			n = [dataStream read:(uint8_t *)(buffer + lastLineLength) maxLength:blockCharCount];
		}

		if (n <= 0)
			break;
		
		// Terminate buffer correctly
		if ((lastLineLength + n) <= (lastLineLength + blockCharCount))
			buffer[lastLineLength + n] = '\0';
		
		textp = (char *)buffer;
		
		while (*textp != '\0') {
			// If we don't have a delimiter yet and this is the first line...
			if (firstLine && _delimiter == '\0') {
				//firstLine = false;
				
				// Check if a delimiter was found and set it
				_delimiter = searchDelimiter(textp);
				if (_delimiter != 0) {
					if (_verbose) {
						printf("delim is %c / %d :-)\n", _delimiter, _delimiter);
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
					else if (*textp == _delimiter && (quoteCount % 2) == 0) {
						// This is a delimiter which is not between an unmachted pair of quotes
						[csvLine addObject:parseString(textp, lastStop, _encoding)];
						lastStop = textp + 1;
					}
					
					// Go to the next character
					textp++;
				}
				
				addCurrentLineAndStartNew = false;
				
				if (lastStop == textp && *(textp-1) == _delimiter) {
					[csvLine addObject:@""];
					
					addCurrentLineAndStartNew = true;
				}
				else if (lastStop != textp && (quoteCount % 2) == 0) {
					[csvLine addObject:parseString(textp, lastStop, _encoding)];
					
					addCurrentLineAndStartNew = true;
				} 
				
				if (addCurrentLineAndStartNew) {
					if ((size_t)(buffer + lastLineLength + blockCharCount - textp) > 0) {
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
					_endOfLine[0] = *(lineStart-1);

					if ( EOL(lineStart) ) {
						_endOfLine[1] = *(lineStart);
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

	if (!_fileMode) {
		[dataStream close];
	}

	return csvContent;
}

/*
 * Parses the CSV-file with the given filename and return the result as an
 * NSMutableArray.
 *
 */
-(NSMutableArray*)parseFile {
	if (_fileHandle <= 0)  return [NSMutableArray array];
	
	NSMutableArray *csvContent = [NSMutableArray array];

	return [self parseInto:csvContent];

}

/*
 * Parses the current data as CSV and return the result as an
 * NSMutableArray.
 *
 */
-(NSMutableArray *)parseData
{
	if (_data == nil)  return nil;
	
	NSMutableArray *csvContent = [NSMutableArray array];
	
	_fileMode = NO;
	
	
	[self parseInto:csvContent];
	
	return csvContent;
}

/*
 * Parses the data as CSV and return the result as an
 * NSMutableArray.
 *
 */
-(NSMutableArray *)parseData:(NSData *)data
{
	NSMutableArray *csvContent = [NSMutableArray array];

	_fileMode = NO;
	
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
	_fileMode = YES;
	_fileHandle = open([fileName UTF8String], O_RDONLY);
	return (_fileHandle > 0);
}

-(void)closeFile {
	if (_fileHandle > 0) {
		close(_fileHandle);
		_fileHandle = 0;
	}
}

NSString * stringForDelimiter(char delimiter, NSStringEncoding encoding) {
    char delimiterCString[2] = {'\0', '\0'};
	delimiterCString[0] = delimiter;
    return [NSString stringWithCString:delimiterCString encoding:encoding];
}

-(NSString *)delimiterString {
	return stringForDelimiter(_delimiter, _encoding);
}

-(NSString *)endOfLine {
    return [NSString stringWithCString:_endOfLine encoding:_encoding];
}


+(NSArray *)supportedDelimiters {
	NSMutableArray *delimitersArray = [NSMutableArray array];
	char *delimiter = (char *)possibleDelimiters;
	while (*delimiter != '\0') {
		NSString *delimiterString = stringForDelimiter(*delimiter, NSASCIIStringEncoding);
		[delimitersArray addObject:delimiterString];
		
		delimiter++;
	}
	
	return delimitersArray;
}

+(NSArray *)supportedDelimiterLocalizedNames {
	NSUInteger possibleDelimiterNamesCount = sizeof(possibleDelimiterNames)/sizeof(possibleDelimiterNames[0]);
	NSMutableArray *delimiterNamesArray = [NSMutableArray arrayWithCapacity:possibleDelimiterNamesCount];
	for (NSUInteger i = 0; i < possibleDelimiterNamesCount; i++) {
		NSString *delimiterName = NSLocalizedString(possibleDelimiterNames[i], @"cCSVParseDelimiterNames");
		[delimiterNamesArray addObject:delimiterName];
	}

	return delimiterNamesArray;
}


+(NSArray *)supportedLineEndings {
	NSUInteger supportedLineEndingsCount = sizeof(supportedLineEndings)/sizeof(supportedLineEndings[0]);
	NSMutableArray *lineEndingsArray = [NSMutableArray arrayWithCapacity:supportedLineEndingsCount];
	for (NSUInteger i = 0; i < supportedLineEndingsCount; i++) {
		NSString *lineEnding = supportedLineEndings[i];
		[lineEndingsArray addObject:lineEnding];
	}
	
	return lineEndingsArray;
}

+(NSArray *)supportedLineEndingLocalizedNames {
	NSUInteger supportedLineEndingNamesCount = sizeof(supportedLineEndingNames)/sizeof(supportedLineEndingNames[0]);
	NSMutableArray *lineEndingNamesArray = [NSMutableArray arrayWithCapacity:supportedLineEndingNamesCount];
	for (NSUInteger i = 0; i < supportedLineEndingNamesCount; i++) {
		NSString *lineEndingName = NSLocalizedString(supportedLineEndingNames[i], @"cCSVParseLineEndingNames");
		[lineEndingNamesArray addObject:lineEndingName];
	}
	
	return lineEndingNamesArray;
}

@end
