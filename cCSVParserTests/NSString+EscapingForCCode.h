//
//  NSString+EscapingForCCode.h
//  cCSVParser
//
//  Created by Jan on 24.07.13.
//  Copyright (c) 2013 Jan Weiß. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (EscapingForCCode)

- (NSString *)jx_stringByEscapingForCCode;

@end
