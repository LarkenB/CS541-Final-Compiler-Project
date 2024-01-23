%{
#include <iostream>
#include "parser.hh"
%}

/* Don't generate yyunput(), since we don't use it. */
%option nounput

/* Named patterns */
int [0-9]+
alpha [a-zA-Z_]
alnum [a-zA-Z0-9_]
/* Exponent part of a float */
exp ([eE][+-]?{int})

/* Mode ("start condition") for C-style comments.  Exclusive, meaning other
 * grammar rules won't be used in this mode, only the <COMMENT> ones.
 */
%x COMMENT

%%

	/* Whitespace */
\n {
	// Not a token, no return.
}

[ \t]+ {
	// Not a token, no return
}

	/* C++-style comments. */
\/\/.* {
	// Not a token, no return.
}

	/* C-style comments.  None of these are tokens, so should not return. */
\/\* {
	BEGIN(COMMENT);
}

<COMMENT>\n {
}

<COMMENT>.  {
}

<COMMENT>\*\/ {
	/* Leave the COMMENT mode. */
	BEGIN(INITIAL);
}


	/* Now the tokens. */

	/* Literals */
[+-]?{int} {
	yylval.code = yytext;
	return INT_LITERAL;
}

	/* Three cases: numbers before the decimal point (and optionally after),
	 * no numbers before the decimal point but some after, and no decimal
	 * point.  In the last case, the exponent is required, since otherwise
	 * this would be an int literal.
	 */
[0-9]+\.[0-9]*{exp}?|\.[0-9]+{exp}?|[0-9]+{exp} {
	yylval.code = yytext;
	return FLOAT_LITERAL;
}

	/* Non-newline, quote, or backslash; or any single backslashed character. */
'[^\n'\\]'|'\\.' {
	yylval.code = yytext;
	return CHAR_LITERAL;
}


	/* Keywords.  These must come before the rule for identifiers! */
"int" {
	return INT;
}

"float" {
	return FLOAT;
}

"char" {
	return CHAR;
}

"return" {
	return RETURN;
}

	/* Identifiers */
{alpha}{alnum}* {
	yylval.code = yytext;
	return IDENTIFIER;
}


	/* Operators */
"="|"+"|"-"|"*"|"/"|"%" {
	// Use the character itself as the token ID.
	return yytext[0];
}


	/* Punctuation */
","|"."|";"|"("|")"|"{"|"}"|"["|"]" {
	// Use the character itself as the token ID.
	return yytext[0];
}

	/* Unrecognized characters.  Must be the last rule! */
. {
	std::cerr << "Unrecognized character: " << yytext << "\n";
}

