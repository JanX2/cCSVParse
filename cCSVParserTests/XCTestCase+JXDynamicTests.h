//
//  XCTestCase+JXDynamicTests.h
//  cCSVParser
//
//  Created by Jan on 11.02.15.
//  Copyright (c) 2015 Jan Weiß. All rights reserved.
//

#import <XCTest/XCTest.h>

@interface XCTestCase (JXDynamicTests)

+ (NSString *)addDynamicTestForIdentifier:(NSString *)identifier
					  implementationBlock:(void (^)(id))block;

@end
