//
//  XCTestCase+JXDynamicTests.m
//  cCSVParser
//
//  Created by Jan on 11.02.15.
//  Copyright (c) 2015 Jan Weiß. All rights reserved.
//

#import "XCTestCase+JXDynamicTests.h"

#import <objc/runtime.h>

@implementation XCTestCase (JXDynamicTests)

NSString * testCaseNameForName(NSString *name) {
	NSMutableString *testCaseName = [name mutableCopy];
	NSRange fullRange = NSMakeRange(0, testCaseName.length);
	[testCaseName replaceOccurrencesOfString:@"[^a-zA-Z0-9]"
								  withString:@"_"
									 options:NSRegularExpressionSearch
									   range:fullRange];
	
	return testCaseName;
}

+ (BOOL)addInstanceMethodWithSelectorNamed:(NSString *)selectorName
					   implementationBlock:(void (^)(id))block;
{
	NSParameterAssert(selectorName);
	NSParameterAssert(block);
	
	id unretainedBlock = (__bridge id)(__bridge void *)block; // Cast away strong qualifier and back to id.
	IMP blockIMP = imp_implementationWithBlock(unretainedBlock); // Copies block. No need to retain it elsewhere.
	
	SEL selector = NSSelectorFromString(selectorName);
	const char *types = "v@:"; // Method returns void and is called with `self` and its selector. Note: Only `self` is passed on to the block.
	return class_addMethod(self, selector, blockIMP, types);
}

+ (NSString *)addDynamicTestForIdentifier:(NSString *)identifier
					  implementationBlock:(void (^)(id))block;
{
	NSString *selectorName = [@"test_" stringByAppendingString:identifier];
	
	[self addInstanceMethodWithSelectorNamed:selectorName
						 implementationBlock:block];
	
	return selectorName;
}

@end
