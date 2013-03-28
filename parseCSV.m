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
static char *cstrstr(const char *haystack_p, const char needle) {
	char *text_p = (char *)haystack_p;
	while (*text_p != '\0') {
		if (*text_p == needle)
			return text_p;
		text_p++;
	}
	return NULL;
}

char searchDelimiter(char *text_p) {
	char delimiter = '\n';
	
	// ...we assume that this is the header which also contains the separation character
	while (NOT_EOL(text_p) && cstrstr(possibleDelimiters, *text_p) == NULL)
		text_p++;
	
	// Check if a delimiter was found and set it
	if (NOT_EOL(text_p)) {
		delimiter = *cstrstr(possibleDelimiters, *text_p);
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
NSString * parseString(char *text_p, char *previousStop_p, NSStringEncoding encoding) {
	NSUInteger stringSize = (size_t)(text_p - previousStop_p);
	
	if (*previousStop_p == '\"' && *(previousStop_p + 1) != '\0' && *(previousStop_p + stringSize - 1) == '\"') {
		previousStop_p++;
		stringSize -= 2;
	}
	
	NSMutableString *tempString = [[NSMutableString alloc] initWithBytes:previousStop_p
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
		_bufferSize = 2049;
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
 * which should be the header line. Returns 0 on error.
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
		return searchDelimiter(buffer);
	}

	return 0;
}

-(NSMutableArray *)parseInto:(NSMutableArray *)csvContent
{
	NSMutableArray *csvRow = [NSMutableArray array];
	NSInputStream *dataStream = nil;
	
	ssize_t n = 1;
	size_t incompleteRowLength = 0;
	NSUInteger previousColumnCount = 0;
	unsigned int quoteCount = 0;
	bool firstLine = true;
	bool addCurrentRowAndStartNew = false;
	size_t bufferSize = _bufferSize;
	size_t blockCharCount = bufferSize - 1;
	char *buffer_p = malloc(sizeof(char) * bufferSize);
	char *text_p = NULL, *previousStop_p = NULL, *rowStart_p = NULL, *incompleteRow_p = NULL;
	
	if (_fileMode) {
		lseek(_fileHandle, 0, SEEK_SET);
	}
	else {
		assert(sizeof(uint8_t) == sizeof(char));
		dataStream = [NSInputStream inputStreamWithData:_data];
		[dataStream open];
	}

	// While there is data to be parsed…
	while (n > 0) {
		
		if (incompleteRow_p != NULL) {
			incompleteRowLength = strlen(incompleteRow_p);
			
			// Increase the buffer size so that the buffer can hold
			// both the previous row fragment and a block of blockCharCount size.
			size_t necessaryCapacity = (incompleteRowLength + blockCharCount + 1) * sizeof(char);
			if (bufferSize < necessaryCapacity) {
				// Preserve previous row fragment.
				char incompleteRow[incompleteRowLength + 1];
				strncpy(incompleteRow, incompleteRow_p, incompleteRowLength);
				incompleteRow[incompleteRowLength + 1] = '\0';
				
				buffer_p = realloc(buffer_p, necessaryCapacity);
				if (buffer_p == NULL) {
					[csvContent removeAllObjects];
					[csvContent addObject:[NSMutableArray arrayWithObject: @"ERROR: Could not allocate bytes for buffer"]];
					return csvContent;
				}
				bufferSize = necessaryCapacity;
				
				// Copy incompleteRow to the beginning of the buffer.
				strncpy(buffer_p, incompleteRow, incompleteRowLength);
			}
			else {
				// Copy incompleteRow_p to the beginning of the buffer.
				strncpy(buffer_p, incompleteRow_p, incompleteRowLength);
			}
			
			incompleteRow_p = NULL;
		} 
		else {
			incompleteRowLength = 0;
		}
		
		if (_fileMode) {
			n = read(_fileHandle, (buffer_p + incompleteRowLength), blockCharCount);
		}
		else {
			n = [dataStream read:(uint8_t *)(buffer_p + incompleteRowLength) maxLength:blockCharCount];
		}

		if (n <= 0)  break; // End of file or error while reading.
		
		bool readEntireBlock = ((size_t)n == blockCharCount);
		
		// Terminate buffer correctly.
		if ((size_t)n <= blockCharCount) {
			buffer_p[incompleteRowLength + n] = '\0';
		}
		else {
			break; // Should not happen: would signify a logic error in this method.
		}
		
		text_p = buffer_p;
		
		while (*text_p != '\0') {
			// If we don't have a delimiter yet and this is the first line...
			if (firstLine && _delimiter == '\0') {
				// Check if a delimiter was found and set it
				_delimiter = searchDelimiter(text_p);
				if (_delimiter != '\0') {
					if (_verbose) {
						printf("delimiter is %c / %d :-)\n", _delimiter, _delimiter);
					}
				}
				
				// Reset to start.
				text_p = buffer_p;
			} 
			
			if (strlen(text_p) > 0) {
				// This is data.
				previousStop_p = text_p;
				rowStart_p = text_p;
				
				// Parsing is split into rows.
				// Find the end of the current CSV row.
				// A row may contain end-of-line characters, but within cells only. 
				while (NOT_EOL(text_p) || (*text_p != '\0' && (quoteCount % 2) != 0)) {
					// If we have two quotes and a delimiter before and after, this is an empty value.
					if (*text_p == '\"') { 
						if (*(text_p + 1) == '\"') {
							// We'll just skip empty cells while searching for the end of the row.
							text_p++;
						} 
						else {
							quoteCount++;
						}
					} 
					else if (*text_p == _delimiter && (quoteCount % 2) == 0) {
						// This is a delimiter which is not between (an unmachted pair of) quotes.
						[csvRow addObject:parseString(text_p, previousStop_p, _encoding)];
						previousStop_p = text_p + 1;
					}
					
					// Go to the next character.
					text_p++;
				}
				
				addCurrentRowAndStartNew = false;
				
				if (previousStop_p == text_p && *(text_p - 1) == _delimiter) {
					// Empty cell.
					[csvRow addObject:@""];
					
					addCurrentRowAndStartNew = true;
				}
				else if (previousStop_p != text_p &&
						 (quoteCount % 2) == 0 &&
						 (*text_p != '\0' || (*text_p == '\0' && readEntireBlock == false))) {
					// Non-empty cell that with certainty was not split apart by the buffer size limit.
					NSString *cellString = parseString(text_p, previousStop_p, _encoding);
					[csvRow addObject:cellString];
					
					addCurrentRowAndStartNew = true;
				} 
				
				if (addCurrentRowAndStartNew) {
					if ((size_t)(buffer_p + incompleteRowLength + blockCharCount - text_p) > 0) {
						rowStart_p = text_p + 1;
						[csvContent addObject:csvRow];
						previousColumnCount = [csvRow count];
					}
					csvRow = [NSMutableArray arrayWithCapacity:previousColumnCount]; // convenience methods always autorelease
				}
				
				if ((*text_p == '\0' || (quoteCount % 2) != 0) && rowStart_p != text_p) {
					// Restart row parsing.
					incompleteRow_p = rowStart_p;
					csvRow = [NSMutableArray arrayWithCapacity:previousColumnCount];
				}
			}
			
			if (firstLine) {
				if ( (rowStart_p != NULL) && (rowStart_p-1 >= buffer_p) && EOL(rowStart_p-1) ) {
					_endOfLine[0] = *(rowStart_p-1);

					if ( EOL(rowStart_p) ) {
						_endOfLine[1] = *(rowStart_p);
					}
				}
				
				firstLine = false;
			}
			
			// Skip over empty lines.
			while (EOL(text_p)) {
				text_p++;
			}
		}
	}
	
	free(buffer_p);
	buffer_p = NULL;

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
	if (delimiterCString[0] == '\0') {
		return nil;
	} else {
		return [NSString stringWithCString:delimiterCString encoding:encoding];
	}
}

-(NSString *)delimiterString {
	return stringForDelimiter(_delimiter, _encoding);
}

-(NSString *)endOfLine {
	if (_endOfLine[0] == '\0') {
		return nil;
	} else {
		return [NSString stringWithCString:_endOfLine encoding:_encoding];
	}
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
