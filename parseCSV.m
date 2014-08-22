/*
 * cCSVParse, a small CVS file parser
 *
 * © 2007-2014 Jan Weiß, Michael Stapelberg and contributors
 * https://github.com/JanX2/cCSVParse
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

#import "JXArcCompatibilityMacros.h"

static NSString *cellInvalidLabel = nil;

const ssize_t UTF8BOMSize = 3;
const char UTF8BOM[UTF8BOMSize] = {0xEF, 0xBB, 0xBF};

const ssize_t UTF16BEBOMSize = 2;
const char UTF16BEBOM[UTF16BEBOMSize] = {0xFE, 0xFF};

const ssize_t UTF16LEBOMSize = 2;
const char UTF16LEBOM[UTF16LEBOMSize] = {0xFF, 0xFE};

/* Macros for determining if the given character is End Of Line or not */
#define EOL(x) ((*(x) == '\r' || *(x) == '\n'))
#define NOT_EOL(x) (*(x) != '\r' && *(x) != '\n')

//const char possibleDelimiters[] = ",;\t|. \0"; // FIXME: Needs testing; will probably fail in searchDelimiter()
const char possibleDelimiters[] = ",;\t|\0";
NSString *possibleDelimiterNames[] = {
	@"Comma (,)",
	@"Semicolon (;)",
	@"Tab Symbol (⇥)",
	@"Pipe Symbol (|)"
};
/* For genstrings:
 NSLocalizedString(@"Comma (,)", @"cCSVParseDelimiterNames")
 NSLocalizedString(@"Semicolon (;)", @"cCSVParseDelimiterNames")
 NSLocalizedString(@"Tab Symbol", @"cCSVParseDelimiterNames")
 NSLocalizedString(@"Pipe Symbol (|)" @"cCSVParseDelimiterNames")
 //NSLocalizedString(@"Period (.)" @"cCSVParseDelimiterNames")
 //NSLocalizedString(@"Space ( )" @"cCSVParseDelimiterNames")
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
 * replacement for strstr() that checks every char instead
 * of complete strings
 * Warning: Do not call it with haystack == NULL || needle == '\0'!
 *
 */
static char *cstrstr(const char *haystack_p, const char needle) {
	char *text_p = (char *)haystack_p;
	
	while (*text_p != '\0') {
		if (*text_p == needle) {
			return text_p;
		}
		text_p++;
	}
	
	return NULL;
}

char searchDelimiter(char *text_p) {
	// We check the entire buffer for separation characters. The first one we find wins.
	while ((*text_p != '\0') && cstrstr(possibleDelimiters, *text_p) == NULL) {
		text_p++;
	}
	
	// Check if a delimiter was found and set it.
	if (*text_p != '\0') {
		char delimiter = *cstrstr(possibleDelimiters, *text_p);
		return delimiter;
	}
	else {
		return '\0';
	}
}

/*
 * Copies a string without beginning- and end-quotes if there are
 * any and returns a pointer to the string or NULL if malloc() failed
 * also returns by reference whether we found quotes around the cell
 */
NSString * parseString(char *text_p, char *cellStart_p, BOOL *foundQuotes_p, NSStringEncoding encoding) {
	char *cellEnd_p = text_p;
	
	// Scan backwards until cellEnd_p points to the last NUL in the cell should there be one.
	// In the extreme case of a cell consisting of only NUL bytes
	// previousStop_p == cellEnd_p afterwards.
	while (cellStart_p < cellEnd_p && *(cellEnd_p - 1) == '\0') {
		cellEnd_p--;
	}
	
	NSUInteger stringSize = (size_t)(cellEnd_p - cellStart_p);
	
	if (*cellStart_p == '\"' && *(cellStart_p + 1) != '\0' && *(cellEnd_p - 1) == '\"') {
		cellStart_p++;
		stringSize -= 2;
		*foundQuotes_p = YES;
	}
	else {
		*foundQuotes_p = NO;
	}
	
	if (stringSize == 0) {
		return [NSMutableString stringWithString:@""];
	}
	
	NSMutableString *tempString = nil;
	NSStringEncoding currentEncoding = encoding;
	int retryCount = 0;

	while (tempString == nil) {
		tempString = [[NSMutableString alloc] initWithBytes:cellStart_p
													 length:stringSize
												   encoding:currentEncoding];
		
		// We use fallbacks if the above fails.
		// This can happen in case the bytes are invalid in the selected encoding.
		if (tempString == nil) {
			do {
				// Retry with fallback encodings.
				switch (retryCount) {
					case 0:
						currentEncoding = NSISOLatin1StringEncoding;
						break;
						
					case 1:
						currentEncoding = NSMacOSRomanStringEncoding;
						break;
						
					default:
						// Fail more or less gracefully.
						currentEncoding = 0;
						tempString = [[NSMutableString alloc] initWithString:cellInvalidLabel];
						break;
				}
				
				retryCount++;
			} while (currentEncoding == encoding);
		}
		else if (tempString != nil && retryCount > 0 && retryCount <= 1) {
			// We tried again with one of the fallback encodings.
			// Even if this was successful, we don’t know if the resulting string is valid.
			// It probably is mangled and the user should know.
			[tempString appendFormat:@" (%@)", cellInvalidLabel];
		}
	}
	
	if (*foundQuotes_p == YES) {
		[tempString replaceOccurrencesOfString:@"\"\""
									withString:@"\""
									   options:NSLiteralSearch
										 range:NSMakeRange(0, [tempString length])];
	}
	
	return JX_AUTORELEASE(tempString);
}


@implementation CSVParser {
	int _fileHandle;
	char _endOfLine[3];
	BOOL _fileMode;
}

+ (void)initialize {
	cellInvalidLabel = JX_RETAIN(NSLocalizedString(@"**encoding or data invalid**", @"cell invalid label"));
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
		_encoding = NSUTF8StringEncoding;
		// Set default verbosity
		_verbose = NO;
		
		_data = nil;
	}
	
	return self;
}

-(void)dealloc {
	[self closeFile];
	
#if !JX_HAS_ARC
	[self setData:nil];
	
	[super dealloc];
#endif
}




/*
 * Gets the CSV-delimiter from the given filename using the first line
 * which should be the header line. Returns a NUL byte on error.
 *
 */
-(char)autodetectDelimiter {
	if (_data == nil)  return '\0';
	
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
		buffer[n] = '\0';
		return searchDelimiter(buffer);
	}

	return '\0';
}

-(NSMutableArray *)parseInto:(NSMutableArray *)csvContent
{
	NSMutableArray *csvRow = [NSMutableArray array];
	NSInputStream *dataStream = nil;
	
	_foundQuotedCell = NO;
	
	ssize_t n = 1;
	size_t incompleteRowLength = 0;
	NSUInteger previousColumnCount = 0;
	unsigned int quoteCount = 0;
	bool firstLine = true;
	bool addCurrentRowAndStartNew = false;
	bool cellIsQuoted = false;
	size_t bufferSize = _bufferSize;
	size_t garbageOffset = 0;
	size_t blockCharCount = bufferSize - 1;
	char *buffer_p = malloc(sizeof(char) * bufferSize);
	char *text_p = NULL, *previousStop_p = NULL, *rowStart_p = NULL, *incompleteRow_p = NULL;
	
	_endOfLine[0] = '\0';
	_endOfLine[1] = '\0';

	if (_fileMode) {
		lseek(_fileHandle, 0, SEEK_SET);
	}
	else {
		assert(sizeof(uint8_t) == sizeof(char));
		dataStream = [NSInputStream inputStreamWithData:_data];
		[dataStream open];
	}

	// While there is data to be parsed…
	while (n > 0 || incompleteRow_p != NULL) {
		
		if (incompleteRow_p != NULL) {
			incompleteRowLength = strlen(incompleteRow_p);
			
			// Increase the buffer size so that the buffer can hold
			// both the previous row fragment and a block of blockCharCount size.
			const size_t necessaryCapacity = (incompleteRowLength + blockCharCount + 1) * sizeof(char);
			if (bufferSize < necessaryCapacity) {
				// Preserve previous row fragment.
				char incompleteRow[incompleteRowLength + 1];
				strlcpy(incompleteRow, incompleteRow_p, incompleteRowLength + 1); // null-terminates!
				
				buffer_p = reallocf(buffer_p, necessaryCapacity);
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
				// Move data at incompleteRow_p to the beginning of the buffer.
				memmove(buffer_p, incompleteRow_p, sizeof(char) * incompleteRowLength);
			}
			
			incompleteRow_p = NULL;
		} 
		else {
			incompleteRowLength = 0;
		}
		
		if (_fileMode) {
			n = read(_fileHandle, (buffer_p + incompleteRowLength), sizeof(char) * blockCharCount);
		}
		else {
			n = [dataStream read:(uint8_t *)(buffer_p + incompleteRowLength) maxLength:(sizeof(char) * blockCharCount)];
		}

		if (n < 0) {
			break; // Error while reading.
		}
		else if (n > 0) {
			if ((size_t)n > blockCharCount) {
				assert(false);
				break; // Should not happen: would signify a logic error in this method.
			}
			else {
				// Everything appears to be fine.
			}
		}
		else /* n == 0 */ {
			if (incompleteRowLength == 0) {
				break; // End of file.
			}
			else {
				// We still have data taken from the last incomplete row.
			}
		}
		
		// Terminate buffer correctly.
		char *endChar_p = &(buffer_p[incompleteRowLength + n]);
		*endChar_p = '\0';
		
		const bool readEntireBlock = ((size_t)n == blockCharCount);
		const bool readingComplete = (readEntireBlock == false || n == 0);
		
		// Skip over BOM
		if (firstLine && _encoding == NSUTF8StringEncoding) {
			if (n >= UTF8BOMSize &&
				strncmp(buffer_p, UTF8BOM, UTF8BOMSize) == 0) {
				garbageOffset = UTF8BOMSize;
			} else if (n >= UTF16BEBOMSize &&
					   strncmp(buffer_p, UTF16BEBOM, UTF16BEBOMSize) == 0) {
				garbageOffset = UTF16BEBOMSize;
			} else if (n >= UTF16LEBOMSize &&
					   strncmp(buffer_p, UTF16LEBOM, UTF16LEBOMSize) == 0) {
				garbageOffset = UTF16LEBOMSize;
			}
			else {
				garbageOffset = 0;
			}
		}
		else {
			garbageOffset = 0;
		}
		
		text_p = buffer_p + garbageOffset;
	
#define VALID_QUOTES		(cellIsQuoted && ((quoteCount % 2) == 0))
#define MATCHED_QUOTES		(VALID_QUOTES || !cellIsQuoted)
#define UNMATCHED_QUOTES	((cellIsQuoted && ((quoteCount % 2) != 0)) || (!cellIsQuoted && false))
		
		while (text_p < endChar_p) {
			// If we don't have a delimiter yet and this is the first line...
			if (firstLine && _delimiter == '\0') {
				// Check if a delimiter was found and set it.
				_delimiter = searchDelimiter(text_p);
				if (_delimiter != '\0') {
					if (_verbose) {
						printf("delimiter is %c / %d :-)\n", _delimiter, _delimiter);
					}
				}
				else {
					// Request retry with larger buffer, if there is is more data available.
					if (readingComplete == false) {
						incompleteRow_p = buffer_p;
						break;
					}
				}
				
				// Reset to start.
				text_p = buffer_p + garbageOffset;
			} 
			
			if (text_p < endChar_p) {
				// This is data.
				previousStop_p = text_p;
				rowStart_p = text_p;
				
				cellIsQuoted = (*previousStop_p == '\"');
				
				// Parsing is split into rows.
				// Find the end of the current CSV row.
				// A row may contain end-of-line characters, but within cells only. 
				while (text_p < endChar_p && (NOT_EOL(text_p) || UNMATCHED_QUOTES)) {
					// If we have two quotes and a delimiter before and after, this is an empty value.
					if (cellIsQuoted && *text_p == '\"') { 
						if (*(text_p + 1) == '\"') {
							// We'll just skip empty cells while searching for the end of the row.
							text_p++;
							//quoteCount += 2; // Currently this is unnecessary, but this way the quoteCount is correct.
						} 
						else {
							quoteCount++;
						}
					} 
					else if (*text_p == _delimiter && MATCHED_QUOTES) {
						// This is a delimiter which is not between (an unmachted pair of) quotes.
						BOOL foundQuotes;
						
						NSString *cellString = parseString(text_p, previousStop_p, &foundQuotes, _encoding);
						[csvRow addObject:cellString];
						previousStop_p = text_p + 1;
						
						if (foundQuotes && _foundQuotedCell == NO) {
							_foundQuotedCell = YES;
						}
						
						if (previousStop_p < endChar_p) {
							cellIsQuoted = (*previousStop_p == '\"');
						}
						else {
							cellIsQuoted = false;
						}
					}
					
					// Go to the next character.
					text_p++;
				}
				
				addCurrentRowAndStartNew = false;
				
				if (previousStop_p == text_p && ((buffer_p == text_p) || (buffer_p < text_p && *(text_p - 1) == _delimiter))) { // Last cell of row is empty.
					// Empty cell.
					[csvRow addObject:@""];
					
					addCurrentRowAndStartNew = true;
				} 
				else if ((text_p < endChar_p &&
						  previousStop_p != text_p &&
						  MATCHED_QUOTES) // Non-empty, unquoted or correctly quoted cell that doesn’t end at the buffer boundary.
						 ||
						 (text_p == endChar_p &&
						  readingComplete) // Cell that ends with the end of the file.
						 ) {
					// Non-empty cell that with certainty was not split apart by the buffer size limit.
					BOOL foundQuotes;
					
					NSString *cellString = parseString(text_p, previousStop_p, &foundQuotes, _encoding);
					[csvRow addObject:cellString];
					
					if (foundQuotes && _foundQuotedCell == NO) {
						_foundQuotedCell = YES;
					}
					
					addCurrentRowAndStartNew = true;
				}
				
				if (addCurrentRowAndStartNew) {
					bool addCurrentRow = false;
					
					if (text_p < endChar_p) {
						// There is more data in the buffer. -> Process the next row.
						rowStart_p = text_p + 1;
						addCurrentRow = true;
					}
					else if (readingComplete) {
						addCurrentRow = true;
					}
					
					if (addCurrentRow) {
						[csvContent addObject:csvRow];
						previousColumnCount = [csvRow count];
					}
					
					csvRow = [NSMutableArray arrayWithCapacity:previousColumnCount]; // convenience methods always autorelease
				}
				
				if ((rowStart_p < endChar_p && rowStart_p != text_p) && // Check for valid row start.
					((text_p == endChar_p && !readingComplete) // End of buffer, but not end of file.
					 ||
					 (text_p < endChar_p && UNMATCHED_QUOTES)) // There are still unclosed quotes.
				 ) {
					// Restart row parsing.
					// If we get here when we are at the end of the buffer,
					// it may be too small to contain the entire row.
					quoteCount = 0;
					incompleteRow_p = rowStart_p;
					csvRow = [NSMutableArray arrayWithCapacity:previousColumnCount];
				}
				else {
					incompleteRow_p = NULL;
				}
			}
			
			// EOL detection.
			if (incompleteRow_p == NULL && firstLine) { // We don’t try, if the row is truncated by the buffer size. 
				if ((text_p < endChar_p) && (rowStart_p != NULL) && (rowStart_p-1 >= buffer_p) && EOL(rowStart_p-1)) {
					_endOfLine[0] = *(rowStart_p-1);
					
					if ((text_p < endChar_p) && EOL(rowStart_p) && (*rowStart_p != _endOfLine[0])) { // We ignore repeating EOLs. They signify empty lines.
						_endOfLine[1] = *(rowStart_p);
					}
					else {
						_endOfLine[1] = '\0';
					}
				}
				else {
					// We couldn’t find an EOL.
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
