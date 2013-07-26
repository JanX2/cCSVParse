//
//  cCSVParserTests.m
//  cCSVParserTests
//
//  Created by Jan on 24.07.13.
//  Copyright (c) 2013 Jan Weiß. All rights reserved.
//

#import "cCSVParserTests.h"

#import "parseCSV.h"
#import "NSString+EscapingForCCode.h"

static NSMutableDictionary *_testDataDict;
static NSMutableDictionary *_expectedResultsDict;

@implementation cCSVParserTests

- (void)setUp
{
    [super setUp];
    
	NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
	
	_testDataDict = [[NSMutableDictionary dictionary] retain];
	
	NSArray *csvFileURLs = [testBundle URLsForResourcesWithExtension:@"csv"
														subdirectory:nil];
	
	for (NSURL *testFileURL in csvFileURLs) {
		NSString *fileName = [testFileURL lastPathComponent];
		NSString *fileBaseName = [fileName stringByDeletingPathExtension];
		
		NSData *testFileData = [NSData dataWithContentsOfURL:testFileURL];
		
		if (testFileData != nil) {
			[_testDataDict setObject:testFileData
							  forKey:fileBaseName];
		}
		else {
			NSLog(@"Error opening file “%@”", fileName);
		}
	}
	
	_expectedResultsDict = [[NSMutableDictionary dictionary] retain];
	
	NSArray *plistFileURLs = [testBundle URLsForResourcesWithExtension:@"plist"
														  subdirectory:nil];
	
	for (NSURL *resultFileURL in plistFileURLs) {
		NSString *fileName = [resultFileURL lastPathComponent];
		NSString *fileBaseName = [fileName stringByDeletingPathExtension];
		
		NSData *resultFileDict = [NSDictionary dictionaryWithContentsOfURL:resultFileURL];
		if (resultFileDict != nil) {
			[_expectedResultsDict setObject:resultFileDict
									 forKey:fileBaseName];
		}
		else {
			NSLog(@"Error opening file “%@”", fileName);
		}
	}
}

- (void)tearDown
{
	[_testDataDict release];
	[_expectedResultsDict release];
    
    [super tearDown];
}

- (void)testBundleFiles
{
	CSVParser *parser = [CSVParser new];
	STAssertNotNil(parser, @"CSVParser instance creation failed.");
	
	if (parser == nil)  return;
	
#define DEBUG_FILE		1

#if DEBUG_FILE
	NSString *fileBaseNameForDebugging = @"whitespace only";
#endif
	
	[_testDataDict enumerateKeysAndObjectsUsingBlock:^(NSString *fileBaseName, NSData *data, BOOL *stop) {
		NSMutableDictionary *expectedProperties = [_expectedResultsDict objectForKey:fileBaseName];
		
		NSStringEncoding encoding = NSUTF8StringEncoding;
		NSString *charsetName = [expectedProperties objectForKey:@"charsetName"];
		if (charsetName != nil) {
			CFStringEncoding cfStringEncoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)charsetName);
			encoding = CFStringConvertEncodingToNSStringEncoding(cfStringEncoding);
		}
		
#if DEBUG_FILE
		if ([fileBaseName isEqualToString:fileBaseNameForDebugging]) {
			NSLog(@"%@", fileBaseNameForDebugging);
		}
#endif
		
		[parser setEncoding:encoding];
		[parser setData:data];
		
		char delimiterChar = [parser autodetectDelimiter];
		[parser setDelimiter:delimiterChar];
		
		NSMutableArray *csvContent = [parser parseData];
		
		NSString *endOfLine = [[parser endOfLine] jx_stringByEscapingForCCode];
		NSString *delimiterString = [[parser delimiterString] jx_stringByEscapingForCCode];

#define VERIFY_EXPECTATIONS					1
#define VERIFY_EXPECTATIONS_FAILURE_CASE	1
#define DUMP_TO_PLIST						!VERIFY_EXPECTATIONS
		
#if DUMP_TO_PLIST
		NSMutableDictionary *plistDict = nil;
		plistDict = [NSMutableDictionary dictionary];
		[plistDict setObject:csvContent
					   forKey:@"csvContent"];

		// Metadata
		if (endOfLine != nil) { // endOfLine will be nil if there are no line breaks in the file we just parsed!
			[plistDict setObject:endOfLine
						   forKey:@"endOfLine"];
		}
		
		if (delimiterString != nil) { // delimiterString will be nil if there are no dlimiters in the file we just parsed!
			[plistDict setObject:delimiterString
						  forKey:@"delimiterString"];
		}
		
		CFStringEncoding cfStringEncoding = CFStringConvertNSStringEncodingToEncoding(encoding);
		NSString *encodingName = (NSString *)CFStringConvertEncodingToIANACharSetName(cfStringEncoding);
		[plistDict setObject:encodingName
					   forKey:@"charsetName"];

		NSString *plistFileName = [fileBaseName stringByAppendingPathExtension:@"plist"];
		NSURL *plistFileURL = [NSURL fileURLWithPath:plistFileName];
		
		[plistDict writeToURL:plistFileURL atomically:YES];
#endif

#if VERIFY_EXPECTATIONS
		if (expectedProperties != nil) {
			NSMutableArray *expectedContent = [expectedProperties objectForKey:@"csvContent"];
			NSString *expectedEndOfLine = [expectedProperties objectForKey:@"endOfLine"];
			NSString *expectedDelimiterString = [expectedProperties objectForKey:@"delimiterString"];
			
#if !VERIFY_EXPECTATIONS_FAILURE_CASE
			STAssertEqualObjects(csvContent, expectedContent, @"Content for “%@” is not as expected.", fileBaseName);
#else
			BOOL contentIsAsExpected = [csvContent isEqualToArray:expectedContent];
			STAssertTrue(contentIsAsExpected, @"Content for “%@” is not as expected.", fileBaseName);
			if (contentIsAsExpected == NO) {
				STAssertEquals(csvContent.count, expectedContent.count, @"Row counts for “%@” differ.", fileBaseName);
				
				if (csvContent.count == expectedContent.count) {
					for (NSUInteger i = 0; i < csvContent.count; i++) {
						NSArray *colArray = [csvContent objectAtIndex:i];
						NSArray *expectedColArray = [expectedContent objectAtIndex:i];
						
						BOOL rowIsAsExpected = [colArray isEqualToArray:expectedColArray];
						STAssertTrue(rowIsAsExpected, @"Row %lu for “%@” is not as expected.", (unsigned long)i, fileBaseName);
						if (rowIsAsExpected == NO) {
							STAssertEquals(colArray.count, expectedColArray.count, @"Column counts for row %lu of “%@” differ.", (unsigned long)i, fileBaseName);
							
							NSUInteger minColCount = MIN(colArray.count, expectedColArray.count);
							for (NSUInteger j = 0; j < minColCount; j++) {
								NSString *cell = [colArray objectAtIndex:j];
								NSString *expectedCell = [expectedColArray objectAtIndex:j];
								
								STAssertEqualObjects(cell, expectedCell, @"Cell in row %lu, column %lu of “%@” is not as expected.", (unsigned long)i, (unsigned long)j, fileBaseName);
								if ([cell isEqualToString:expectedCell] == NO)  break; // We stop after the first mismatch.
							}
						}
					}
				}
			}
#endif
			
			if (expectedEndOfLine == nil) {
				STAssertNil(endOfLine, @"endOfLine for “%@” is supposed to be nil.", fileBaseName);
			} else {
				STAssertEqualObjects(endOfLine, expectedEndOfLine, @"endOfLine for “%@” is not as expected.", fileBaseName);
			}
			
			if (expectedDelimiterString == nil) {
				STAssertNil(delimiterString, @"Delimiter for “%@” is supposed to be nil.", fileBaseName);
			} else {
				STAssertEqualObjects(delimiterString, expectedDelimiterString, @"Delimiter for “%@” is not as expected.", fileBaseName);
			}
		}
#endif
	}];
	 
	

	[parser release];
}

@end
