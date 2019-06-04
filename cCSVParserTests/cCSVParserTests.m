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

#import "XCTestCase+JXDynamicTests.h"

//static NSMutableDictionary *_testCaseToFileBaseNameDict;
static NSMutableDictionary *_testDataDict;
static NSMutableDictionary *_expectedResultsDict;

@implementation cCSVParserTests

+ (void)initialize
{
    if (self == [cCSVParserTests class]) {
		
#define DEBUG_FILE		0
			
#if DEBUG_FILE
		NSString *fileBaseNameForDebugging = @"whitespace only";
#endif
			
		NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
		
		//_testCaseToFileBaseNameDict = [NSMutableDictionary dictionary];
		
		_testDataDict = [NSMutableDictionary dictionary];
		
		NSArray *csvFileURLs = [testBundle URLsForResourcesWithExtension:@"csv"
															subdirectory:nil];
		CSVParser *parser = [CSVParser new];

		for (NSURL *testFileURL in csvFileURLs) {
			NSString *fileName = [testFileURL lastPathComponent];
			NSString *fileBaseName = [fileName stringByDeletingPathExtension];
			
			NSData *testFileData = [NSData dataWithContentsOfURL:testFileURL];
			
			if (testFileData != nil) {
#if DEBUG_FILE
				if (![fileBaseName isEqualToString:fileBaseNameForDebugging]) {
					continue;
				}
#endif
				
				_testDataDict[fileBaseName] = testFileData;
				
				//NSString *selectorName =
				[self addDynamicTestForIdentifier:fileBaseName
							  implementationBlock:^(cCSVParserTests *test) {
					[test internalTestCaseWithParser:parser
										fileBaseName:fileBaseName
											  testFileData:testFileData];
				}];
				
				//_testCaseToFileBaseNameDict[selectorName] = fileBaseName;
			}
			else {
				NSLog(@"Error opening file “%@”", fileName);
			}
		}
		
		_expectedResultsDict = [NSMutableDictionary dictionary];
		
		NSArray *plistFileURLs = [testBundle URLsForResourcesWithExtension:@"plist"
															  subdirectory:nil];
		
		for (NSURL *resultFileURL in plistFileURLs) {
			NSString *fileName = [resultFileURL lastPathComponent];
			NSString *fileBaseName = [fileName stringByDeletingPathExtension];
			
			NSDictionary *resultFileDict = [NSDictionary dictionaryWithContentsOfURL:resultFileURL];
			if (resultFileDict != nil) {
				_expectedResultsDict[fileBaseName] = resultFileDict;
			}
			else {
				NSLog(@"Error opening file “%@”", fileName);
			}
		}
	}
	
	//NSLog(@"%@", _testCaseToFileBaseNameDict);
}

- (void)setUp
{
    [super setUp];
    
}

- (void)tearDown
{
    [super tearDown];
}

- (void)internalTestCaseWithParser:(CSVParser *)parser
					  fileBaseName:(NSString *)fileBaseName
					  testFileData:(NSData *)data;
{
	{
		NSMutableDictionary *expectedProperties = _expectedResultsDict[fileBaseName];
		
		NSStringEncoding encoding = NSUTF8StringEncoding;
		NSString *charsetName = expectedProperties[@"charsetName"];
		if (charsetName != nil) {
			CFStringEncoding cfStringEncoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)charsetName);
			encoding = CFStringConvertEncodingToNSStringEncoding(cfStringEncoding);
		}
		
		[parser setEncoding:encoding];
		[parser setData:data];
		
		char delimiterChar = [parser autodetectDelimiter];
		[parser setDelimiter:delimiterChar];
		
		NSMutableArray *csvContent = [parser parseData];
		
		NSString *endOfLine = [[parser endOfLine] jx_stringByEscapingForCCode];
		NSString *delimiterString = [[parser delimiterString] jx_stringByEscapingForCCode];
		BOOL foundQuotedCell = [parser foundQuotedCell];
        
#define VERIFY_EXPECTATIONS					1
#define VERIFY_EXPECTATIONS_FAILURE_CASE	1
#define DUMP_TO_PLIST						!VERIFY_EXPECTATIONS
		
#if DUMP_TO_PLIST
		NSMutableDictionary *plistDict = nil;
		plistDict = [NSMutableDictionary dictionary];
		[plistDict setObject:csvContent
					   forKey:@"csvContent"];

		// Metadata
		if (endOfLine != nil) { // endOfLine will be `nil` if there are no line breaks in the file we just parsed!
			[plistDict setObject:endOfLine
						   forKey:@"endOfLine"];
		}
		
		if (delimiterString != nil) { // delimiterString will be `nil` if there are no delimiters in the file we just parsed!
			[plistDict setObject:delimiterString
						  forKey:@"delimiterString"];
		}
		
		[plistDict setObject:@(foundQuotedCell)
					  forKey:@"foundQuotedCell"];
		
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
			NSMutableArray *expectedContent = expectedProperties[@"csvContent"];
			NSString *expectedEndOfLine = expectedProperties[@"endOfLine"];
			NSString *expectedDelimiterString = expectedProperties[@"delimiterString"];
			BOOL expectedFoundQuotedCell = [expectedProperties[@"foundQuotedCell"] boolValue];
            
#if !VERIFY_EXPECTATIONS_FAILURE_CASE
			XCTAssertEqualObjects(csvContent, expectedContent, @"Content for “%@” is not as expected.", fileBaseName);
#else
			BOOL contentIsAsExpected = [csvContent isEqualToArray:expectedContent];
			XCTAssertTrue(contentIsAsExpected, @"Content for “%@” is not as expected.", fileBaseName);
			if (contentIsAsExpected == NO) {
				XCTAssertEqual(csvContent.count, expectedContent.count, @"Row counts for “%@” differ.", fileBaseName);
				
				if (csvContent.count == expectedContent.count) {
					for (NSUInteger i = 0; i < csvContent.count; i++) {
						NSArray *colArray = csvContent[i];
						NSArray *expectedColArray = expectedContent[i];
						
						BOOL rowIsAsExpected = [colArray isEqualToArray:expectedColArray];
						XCTAssertTrue(rowIsAsExpected, @"Row %lu for “%@” is not as expected.", (unsigned long)i, fileBaseName);
						if (rowIsAsExpected == NO) {
							XCTAssertEqual(colArray.count, expectedColArray.count, @"Column counts for row %lu of “%@” differ.", (unsigned long)i, fileBaseName);
							
							NSUInteger minColCount = MIN(colArray.count, expectedColArray.count);
							for (NSUInteger j = 0; j < minColCount; j++) {
								NSString *cell = colArray[j];
								NSString *expectedCell = expectedColArray[j];
								
								XCTAssertEqualObjects(cell, expectedCell, @"Cell in row %lu, column %lu of “%@” is not as expected.", (unsigned long)i, (unsigned long)j, fileBaseName);
								if ([cell isEqualToString:expectedCell] == NO)  break; // We stop after the first mismatch.
							}
						}
					}
				}
			}
#endif
			
			if (expectedEndOfLine == nil) {
				XCTAssertNil(endOfLine, @"endOfLine for “%@” is supposed to be nil.", fileBaseName);
			} else {
				XCTAssertEqualObjects(endOfLine, expectedEndOfLine, @"endOfLine for “%@” is not as expected.", fileBaseName);
			}
			
			if (expectedDelimiterString == nil) {
				XCTAssertNil(delimiterString, @"Delimiter for “%@” is supposed to be nil.", fileBaseName);
			} else {
				XCTAssertEqualObjects(delimiterString, expectedDelimiterString, @"Delimiter for “%@” is not as expected.", fileBaseName);
			}
			
			XCTAssertEqual(foundQuotedCell, expectedFoundQuotedCell, @"foundQuotedCell for “%@” is not as expected.", fileBaseName);
		}
#endif
	}
}

- (void)testDelimiterString
{
	CSVParser *parser = [CSVParser new];
	
	NSArray *supportedDelimiters = [CSVParser supportedDelimiters];
	
	for (NSString *thisDelimiters in supportedDelimiters) {
		parser.delimiterString = thisDelimiters;
		NSString *delimiterString = parser.delimiterString;
		
		XCTAssertEqualObjects(thisDelimiters, delimiterString);
	}
}

- (void)testEndOfLineString
{
	CSVParser *parser = [CSVParser new];
	
	NSArray *supportedLineEndings = [CSVParser supportedLineEndings];
	
	for (NSString *thisLineEnding in supportedLineEndings) {
		parser.endOfLine = thisLineEnding;
		NSString *lineEnding = parser.endOfLine;
		
		XCTAssertEqualObjects(thisLineEnding, lineEnding);
	}
}

@end
