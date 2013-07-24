//
//  NSString+EscapingForCCode.m
//  cCSVParser
//
//  Created by Jan on 24.07.13.
//  Based on Seth Kingsley’s answer at http://stackoverflow.com/a/4094101
//

#import "NSString+EscapingForCCode.h"

#import <vis.h>

@implementation NSString (EscapingForCCode)

- (NSString *)jx_stringByEscapingForCCode;
{
	const char *input = [self UTF8String];
	char *output = calloc(strlen(input) * 4 + 1 /* Worst case */, sizeof(char));
	char ch, *och = output;
	
	while ((ch = *input++)) {
		if ((ch == '\'') || (ch == '\'') || (ch == '\\') || (ch == '"')) {
			*och++ = '\\';
			*och++ = ch;
		}
		else if (isascii(ch)) {
			och = vis(och, ch, VIS_NL | VIS_TAB | VIS_CSTYLE, *input);
		}
		else {
			och += sprintf(och, "\\%03hho", ch); // Encode as octal.
		}
	}
	
	NSString *result = [NSString stringWithUTF8String:output];
	free(output);
	
	return result;
}

@end
