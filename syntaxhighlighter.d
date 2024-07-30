module arsd.docgen.syntaxhighlighter;

import arsd.dom;

import std.algorithm.searching;
import std.string;
import std.conv;

Html syntaxHighlightCss(string code) {
	string highlighted;


	int pullPiece(string code, bool includeDot) {
		int i;
		while(i < code.length && (
			(code[i] >= '0' && code[i] <= '9')
			||
			(code[i] >= 'a' && code[i] <= 'z')
			||
			(code[i] >= 'A' && code[i] <= 'Z')
			||
			(includeDot && code[i] == '.') || code[i] == '_' || code[i] == '-' || code[i] == ':' // for css i want to match like :first-letter
		))
		{
			i++;
		}
		return i;
	}



	while(code.length) {
		switch(code[0]) {
			case '\'':
			case '\"':
				// string literal
				char start = code[0];
				size_t i = 1;
				while(i < code.length && code[i] != start && code[i] != '\n') {
					if(code[i] == '\\')
						i++; // skip escaped char too
					i++;
				}

				i++; // skip closer
				highlighted ~= "<span class=\"highlighted-string\">" ~ htmlEntitiesEncode(code[0 .. i]) ~ "</span>";
				code = code[i .. $];
			break;
			case '/':
				// check for comment
				if(code.length > 1 && code[1] == '*') {
					// a star comment
					size_t i;
					while((i+1) < code.length && !(code[i] == '*' && code[i+1] == '/'))
						i++;

					if(i < code.length)
						i+=2; // skip the */

					highlighted ~= "<span class=\"highlighted-comment\">" ~ htmlEntitiesEncode(code[0 .. i]) ~ "</span>";
					code = code[i .. $];
				} else {
					highlighted ~= '/';
					code = code[1 .. $];
				}
			break;
			case '<':
				highlighted ~= "&lt;";
				code = code[1 .. $];
			break;
			case '>':
				highlighted ~= "&gt;";
				code = code[1 .. $];
			break;
			case '&':
				highlighted ~= "&amp;";
				code = code[1 .. $];
			break;
			case '@':
				// @media, @import, @font-face, etc
				auto i = pullPiece(code[1 .. $], false);
				if(i)
					i++;
				else
					goto plain;
				highlighted ~= "<span class=\"highlighted-preprocessor-directive\">" ~ htmlEntitiesEncode(code[0 .. i]) ~ "</span>";
				code = code[i .. $];
			break;
			case '\n', ';':
				// check for a new rule (imprecise since we don't actually parse, but meh
				// will ignore indent, then see if there is a word-like-this followed by :
				int i = 1;
				while(i < code.length && (code[i] == ' ' || code[i] == '\t'))
					i++;
				int start = i;
				while(i < code.length && (code[i] == '-' || (code[i] >= 'a' && code[i] <= 'z')))
					i++;
				if(start == i || i == code.length || code[i] != ':')
					goto plain;

				highlighted ~= code[0 .. start];
				highlighted ~= "<span class=\"highlighted-named-constant\">" ~ htmlEntitiesEncode(code[start .. i]) ~ "</span>";
				code = code[i .. $];
			break;
			case '[':
				// attribute match rule
				auto i = pullPiece(code[1 .. $], false);
				if(i)
					i++;
				else
					goto plain;
				highlighted ~= "<span class=\"highlighted-attribute-name\">" ~ htmlEntitiesEncode(code[0 .. i]) ~ "</span>";
				code = code[i .. $];
			break;
			case '#', '.': // id or class selector
				auto i = pullPiece(code[1 .. $], false);
				if(i)
					i++;
				else
					goto plain;
				highlighted ~= "<span class=\"highlighted-identifier\">" ~ htmlEntitiesEncode(code[0 .. i]) ~ "</span>";
				code = code[i .. $];
			break;
			case ':':
				// pseudoclass
				auto i = pullPiece(code, false);
				highlighted ~= "<span class=\"highlighted-preprocessor-directive\">" ~ htmlEntitiesEncode(code[0 .. i]) ~ "</span>";
				code = code[i .. $];
			break;
			case '(':
				// just skipping stuff in parens...
				int parenCount = 0;
				int pos = 0;
				bool inQuote;
				bool escaped;
				while(pos < code.length) {
					if(code[pos] == '\\')
						escaped = true;
					if(!escaped && code[pos] == '"')
						inQuote = !inQuote;
					if(!inQuote && code[pos] == '(')
						parenCount++;
					if(!inQuote && code[pos] == ')')
						parenCount--;
					pos++;
					if(parenCount == 0)
						break;
				}

				highlighted ~= "<span class=\"highlighted-identifier\">" ~ htmlEntitiesEncode(code[0 .. pos]) ~ "</span>";
				code = code[pos .. $];
			break;
			case '0': .. case '9':
				// number. including text at the end cuz it is probably a unit
				auto i = pullPiece(code, true);
				highlighted ~= "<span class=\"highlighted-number\">" ~ htmlEntitiesEncode(code[0 .. i]) ~ "</span>";
				code = code[i .. $];
			break;
			default:
			plain:
				highlighted ~= code[0];
				code = code[1 .. $];
		}
	}

	return Html(highlighted);
}

string highlightHtmlTag(string tag) {
	string highlighted = "&lt;";

	bool isWhite(char c) {
		return c == ' ' || c == '\t' || c == '\n' || c == '\r';
	}

	tag = tag[1 .. $];

	if(tag[0] == '/') {
		highlighted ~= '/';
		tag = tag[1 .. $];
	}

	int i = 0;
	while(i < tag.length && !isWhite(tag[i]) && tag[i] != '>') {
		i++;
	}

	highlighted ~= "<span class=\"highlighted-tag-name\">" ~ htmlEntitiesEncode(tag[0 .. i]) ~ "</span>";
	tag = tag[i .. $];

	while(tag.length && tag[0] != '>') {
		while(isWhite(tag[0])) {
			highlighted ~= tag[0];
			tag = tag[1 .. $];
		}

		i = 0;
		while(i < tag.length && tag[i] != '=' && tag[i] != '>')
			i++;

		highlighted ~= "<span class=\"highlighted-attribute-name\">" ~ htmlEntitiesEncode(tag[0 .. i]) ~ "</span>";
		tag = tag[i .. $];

		if(tag.length && tag[0] == '=') {
			highlighted ~= '=';
			tag = tag[1 .. $];
			if(tag.length && (tag[0] == '\'' || tag[0] == '"')) {
				char end = tag[0];
				i = 1;
				while(i < tag.length && tag[i] != end)
					i++;
				if(i < tag.length)
					i++;

				highlighted ~= "<span class=\"highlighted-attribute-value\">" ~ htmlEntitiesEncode(tag[0 .. i]) ~ "</span>";
				tag = tag[i .. $];
			} else if(tag.length) {
				i = 0;
				while(i < tag.length && !isWhite(tag[i]))
					i++;

				highlighted ~= "<span class=\"highlighted-attribute-value\">" ~ htmlEntitiesHighlight(tag[0 .. i]) ~ "</span>";
				tag = tag[i .. $];
			}
		}
	}


	highlighted ~= htmlEntitiesEncode(tag);

	return highlighted;
}

string htmlEntitiesHighlight(string code) {
	string highlighted;

	bool isWhite(char c) {
		return c == ' ' || c == '\t' || c == '\n' || c == '\r';
	}

	while(code.length)
	switch(code[0]) {
		case '&':
			// possibly an entity
			int i = 0;
			while(i < code.length && code[i] != ';' && !isWhite(code[i]))
				i++;
			if(i == code.length || isWhite(code[i])) {
				highlighted ~= "&amp;";
				code = code[1 .. $];
			} else {
				i++;
				highlighted ~=
					"<abbr class=\"highlighted-entity\" title=\"Entity: "~code[0 .. i].replace("\"", "&quot;")~"\">" ~
						htmlEntitiesEncode(code[0 .. i]) ~
					"</abbr>";
				code = code[i .. $];
			}
		break;
		case '<':
			highlighted ~= "&lt;";
			code = code[1 .. $];
		break;
		case '"':
			highlighted ~= "&quot;";
			code = code[1 .. $];
		break;
		case '>':
			highlighted ~= "&gt;";
			code = code[1 .. $];
		break;
		default:
			highlighted ~= code[0];
			code = code[1 .. $];
	}

	return highlighted;
}

Html syntaxHighlightRuby(string code) {
	// FIXME this is quite minimal and crappy
	// ruby just needs to be parsed to be lexed!
	// and i didn't implement its myriad of strings

	static immutable string[] rubyKeywords = [
		"BEGIN", "ensure", "self", "when",
		"END", "not", "super", "while",
		"alias", "defined", "for", "or", "then", "yield",
		"and", "do", "if", "redo",
		"begin", "else", "in", "rescue", "undef",
		"break", "elsif", "retry", "unless",
		"case", "end", "next", "return", "until",
	];

	static immutable string[] rubyPreprocessors = [
		"require", "include"
	];

	static immutable string[] rubyTypes = [
		"class", "def", "module"
	];

	static immutable string[] rubyConstants = [
		"nil", "false", "true",
	];

	bool lastWasType;
	char lastChar;
	int indentLevel;
	int[] declarationIndentLevels;

	string highlighted;

	while(code.length) {
		bool thisIterWasType = false;
		auto ch = code[0];
		switch(ch) {
			case '#':
				size_t i;
				while(i < code.length && code[i] != '\n')
					i++;

				highlighted ~= "<span class=\"highlighted-comment\">" ~ htmlEntitiesEncode(code[0 .. i]) ~ "</span>";
				code = code[i .. $];
			break;
			case '<':
				highlighted ~= "&lt;";
				code = code[1 .. $];
			break;
			case '>':
				highlighted ~= "&gt;";
				code = code[1 .. $];
			break;
			case '&':
				highlighted ~= "&amp;";
				code = code[1 .. $];
			break;
			case '0': .. case '9':
				// number literal
				size_t i;
				while(i < code.length && (
					(code[i] >= '0' && code[i] <= '9')
					||
					(code[i] >= 'a' && code[i] <= 'z')
					||
					(code[i] >= 'A' && code[i] <= 'Z')
					||
					code[i] == '.' || code[i] == '_'
				))
				{
					i++;
				}

				highlighted ~= "<span class=\"highlighted-number\">" ~ htmlEntitiesEncode(code[0 .. i]) ~ "</span>";
				code = code[i .. $];
			break;
			case '"', '\'':
				// string
				// check for triple-quoted string
				if(ch == '"') {

					// double quote string
					auto idx = 1;
					bool escaped = false;
					int nestedCount = 0;
					bool justSawHash = false;
					while(!escaped && nestedCount == 0 && code[idx] != '"') {
						if(justSawHash && code[idx] == '{')
							nestedCount++;
						if(nestedCount && code[idx] == '}')
							nestedCount--;

						if(!escaped && code[idx] == '#')
							justSawHash = true;

						if(code[idx] == '\\')
							escaped = true;
						else {
							escaped = false;
						}

						idx++;
					}
					idx++;

					highlighted ~= "<span class=\"highlighted-string\">" ~ htmlEntitiesEncode(code[0 .. idx]) ~ "</span>";
					code = code[idx .. $];
				} else {
					int end = 1;
					bool escaped;
					while(end < code.length && !escaped && code[end] != ch) {
						escaped = (code[end] == '\\');
						end++;
					}

					if(end < code.length)
						end++;

					highlighted ~= "<span class=\"highlighted-string\">" ~ htmlEntitiesEncode(code[0 .. end]) ~ "</span>";
					code = code[end .. $];
				}
			break;
			case '\n':
				indentLevel = 0;
				int i = 1;
				while(i < code.length && (code[i] == ' ' || code[i] == '\t')) {
					i++;
					indentLevel++;
				}
				highlighted ~= ch;
				code = code[1 .. $];
			break;
			case ' ', '\t':
				thisIterWasType = lastWasType; // don't change the last counter on just whitespace
				highlighted ~= ch;
				code = code[1 .. $];
			break;
			case ':':
				// check for ruby symbol
				int nameEnd = 1;
				while(nameEnd < code.length && (
					(code[nameEnd] >= 'a' && code[nameEnd] <= 'z') ||
					(code[nameEnd] >= 'A' && code[nameEnd] <= 'Z') ||
					(code[nameEnd] >= '0' && code[nameEnd] <= '0') ||
					code[nameEnd] == '_'
				))
				{
					nameEnd++;
				}

				if(nameEnd > 1) {
					highlighted ~= "<span class=\"highlighted-string\">" ~ htmlEntitiesEncode(code[0 .. nameEnd]) ~ "</span>";
					code = code[nameEnd .. $];
				} else {
					highlighted ~= ch;
					code = code[1 .. $];
				}
			break;
			default:
				// check for names
				int nameEnd = 0;
				while(nameEnd < code.length && (
					(code[nameEnd] >= 'a' && code[nameEnd] <= 'z') ||
					(code[nameEnd] >= 'A' && code[nameEnd] <= 'Z') ||
					(code[nameEnd] >= '0' && code[nameEnd] <= '0') ||
					code[nameEnd] == '_'
				))
				{
					nameEnd++;
				}

				if(nameEnd) {
					auto name = code[0 .. nameEnd];
					code = code[nameEnd .. $];

					if(rubyTypes.canFind(name)) {
						highlighted ~= "<span class=\"highlighted-type\">" ~ name ~ "</span>";
						thisIterWasType = true;
						declarationIndentLevels ~= indentLevel;
					} else if(rubyConstants.canFind(name)) {
						highlighted ~= "<span class=\"highlighted-number\">" ~ name ~ "</span>";
					} else if(rubyPreprocessors.canFind(name)) {
						highlighted ~= "<span class=\"highlighted-preprocessor-directive\">" ~ name ~ "</span>";
					} else if(rubyKeywords.canFind(name)) {
						if(name == "end") {
							if(declarationIndentLevels.length && indentLevel == declarationIndentLevels[$-1]) {
								// cheating on matching ends with declarations: if indentation matches...
								highlighted ~= "<span class=\"highlighted-type\">" ~ name ~ "</span>";
								declarationIndentLevels = declarationIndentLevels[0 .. $-1];
							} else {
								highlighted ~= "<span class=\"highlighted-keyword\">" ~ name ~ "</span>";
							}
						} else {
							highlighted ~= "<span class=\"highlighted-keyword\">" ~ name ~ "</span>";
						}
					} else {
						if(lastWasType) {
							highlighted ~= "<span class=\"highlighted-identifier\">" ~ name ~ "</span>";
						} else {
							if(name.length && name[0] >= 'A' && name[0] <= 'Z')
								highlighted ~= "<span class=\"highlighted-named-constant\">" ~ name ~ "</span>";
							else
								highlighted ~= name;
						}
					}
				} else {
					highlighted ~= ch;
					code = code[1 .. $];
				}
			break;
		}
		lastChar = ch;
		lastWasType = thisIterWasType;
	}

	return Html(highlighted);
}

Html syntaxHighlightPython(string code) {
	/*
		I just want to support:
			numbers
				anything starting with 0, then going alphanumeric
			keywords
				from and import are "preprocessor"
				None, True, and False are number literal colored
			name
				an identifier after the "def" keyword, possibly including : if in there. my vim does it light blue
			comments
				only # .. \n is allowed.
			strings
				single quote must end on the same line
				triple quote span multiple line.


			Extracting python definitions:
				class foo:
					# method baz, arg: bar, doc string attached
					def baz(bar):
						""" this is the doc string """

				will just have to follow indentation (BARF)

			Note: python has default arguments.


			Python implicitly does line continuation if parens, brackets, or braces open
			you can also explicitly extend with \ at the end
			in these cases, the indentation doesn't count.

			If there's only comments on a line, the indentation is also exempt.
	*/
	static immutable string[] pythonKeywords = [
		"and", "del", "not", "while",
		"as", "elif", "global", "or", "with",
		"assert", "else", "if", "pass", "yield",
		"break", "except", "print",
		"exec", "in", "raise",
		"continue", "finally", "is", "return",
		"for", "lambda", "try",
	];

	static immutable string[] pythonPreprocessors = [
		"from", "import"
	];

	static immutable string[] pythonTypes = [
		"class", "def"
	];

	static immutable string[] pythonConstants = [
		"True", "False", "None"
	];

	string[] indentStack;
	int openParenCount = 0;
	int openBraceCount = 0;
	int openBracketCount = 0;
	char lastChar;
	bool lastWasType;

	string highlighted;

	// ensure there is one and exactly one new line at the end
	// the highlighter uses the final \n as a chance to clean up the
	// indent divs
	code = code.stripRight;
	code ~= "\n";

	int lineCountSpace = 5; // if python is > 1000 lines it can slightly throw off the indent highlight... but meh.

	while(code.length) {
		bool thisIterWasType = false;
		auto ch = code[0];
		switch(ch) {
			case '#':
				size_t i;
				while(i < code.length && code[i] != '\n')
					i++;

				highlighted ~= "<span class=\"highlighted-comment\">" ~ htmlEntitiesEncode(code[0 .. i]) ~ "</span>";
				code = code[i .. $];
			break;
			case '(':
				openParenCount++;
				highlighted ~= ch;
				code = code[1 .. $];
			break;
			case '[':
				openBracketCount++;
				highlighted ~= ch;
				code = code[1 .. $];
			break;
			case '{':
				openBraceCount++;
				highlighted ~= ch;
				code = code[1 .. $];
			break;
			case ')':
				openParenCount--;
				highlighted ~= ch;
				code = code[1 .. $];
			break;
			case ']':
				openBracketCount--;
				highlighted ~= ch;
				code = code[1 .. $];
			break;
			case '}':
				openBraceCount--;
				highlighted ~= ch;
				code = code[1 .. $];
			break;
			case '<':
				highlighted ~= "&lt;";
				code = code[1 .. $];
			break;
			case '>':
				highlighted ~= "&gt;";
				code = code[1 .. $];
			break;
			case '&':
				highlighted ~= "&amp;";
				code = code[1 .. $];
			break;
			case '0': .. case '9':
				// number literal
				size_t i;
				while(i < code.length && (
					(code[i] >= '0' && code[i] <= '9')
					||
					(code[i] >= 'a' && code[i] <= 'z')
					||
					(code[i] >= 'A' && code[i] <= 'Z')
					||
					code[i] == '.' || code[i] == '_'
				))
				{
					i++;
				}

				highlighted ~= "<span class=\"highlighted-number\">" ~ htmlEntitiesEncode(code[0 .. i]) ~ "</span>";
				code = code[i .. $];
			break;
			case '"', '\'':
				// string
				// check for triple-quoted string
				if(ch == '"' && code.length > 2 && code[1] == '"' && code[2] == '"') {
					int end = 3;
					bool escaped;
					while(end + 3 < code.length && !escaped && code[end .. end+ 3] != `"""`) {
						escaped = (code[end] == '\\');
						end++;
					}

					if(end < code.length)
						end+= 3;

					highlighted ~= "<span class=\"highlighted-string\">" ~ htmlEntitiesEncode(code[0 .. end]) ~ "</span>";
					code = code[end .. $];
				} else {
					// otherwise these are limited to one line, though since we
					// assume the program is well-formed, I'm not going to bother;
					// no need to check for Python errors here, just highlight
					int end = 1;
					bool escaped;
					while(end < code.length && !escaped && code[end] != ch) {
						escaped = (code[end] == '\\');
						end++;
					}

					if(end < code.length)
						end++;

					highlighted ~= "<span class=\"highlighted-string\">" ~ htmlEntitiesEncode(code[0 .. end]) ~ "</span>";
					code = code[end .. $];
				}
			break;
			case '\n':
				string thisIndent = null;
				int thisIndentLength = lineCountSpace;
				// figure out indentation and stuff...
				if(lastChar == '\\' || openParenCount || openBracketCount || openBraceCount) {
					// line continuation, no special processing
				} else {
					if(code.length == 1) {
						// last line in the file, clean up the indentation
						int remove;
						foreach_reverse(i; indentStack) {
							// this isn't actually following the python rule which
							// is more like .startsWith but meh
							if(i.length <= thisIndent.length)
								break;
							highlighted ~= "</div>";
							remove++;
						}
						indentStack = indentStack[0 .. $ - remove];
						// NOT appending the final \n cuz that leads dead space in rendered doc

						code = code[1 .. $];
						break;
					} else
					foreach(idx, cha; code[1 .. $]) {
						if(cha == '\n')
							break;
						if(cha == '#') // comments exempt from indent processing too
							break;
						if(cha == ' ')
							thisIndentLength++;
						if(cha == '\t')
							thisIndentLength += 8 - (thisIndentLength % 8);
						if(cha != ' ' && cha != '\t') {
							thisIndent = code[1 .. idx + 1];
							break;
						}
					}
				}

				bool changedDiv = false;

				if(thisIndent !is null) { // !is null rather than .length is important here. null means skip, "" may need processing
					// close open indents if necessary
					int remove;
					foreach_reverse(i; indentStack) {
						// this isn't actually following the python rule which
						// is more like .startsWith but meh
						if(i.length <= thisIndent.length)
							break;
						highlighted ~= "</div>";
						changedDiv = true;
						remove++;
					}
					indentStack = indentStack[0 .. $ - remove];
				}

				if(thisIndent.length) { // but we only ever open a new one if there was non-zero indent
					// open a new one if appropriate
					if(indentStack.length == 0 || thisIndent.length > indentStack[$-1].length) {
						changedDiv = true;
						highlighted ~= "<div class=\"highlighted-python-indent\" style=\"background-position: calc("~to!string(thisIndentLength)~"ch - 2px);\">";
						indentStack ~= thisIndent;
					}
				}

				if(changedDiv)
					highlighted ~= "<span style=\"white-space: normal;\">";

				highlighted ~= ch;

				if(changedDiv)
					highlighted ~= "</span>";

				code = code[1 .. $];
			break;
			case ' ', '\t':
				thisIterWasType = lastWasType; // don't change the last counter on just whitespace
				highlighted ~= ch;
				code = code[1 .. $];
			break;
			default:
				// check for names
				int nameEnd = 0;
				while(nameEnd < code.length && (
					(code[nameEnd] >= 'a' && code[nameEnd] <= 'z') ||
					(code[nameEnd] >= 'A' && code[nameEnd] <= 'Z') ||
					(code[nameEnd] >= '0' && code[nameEnd] <= '0') ||
					code[nameEnd] == '_'
				))
				{
					nameEnd++;
				}

				if(nameEnd) {
					auto name = code[0 .. nameEnd];
					code = code[nameEnd .. $];

					if(pythonTypes.canFind(name)) {
						highlighted ~= "<span class=\"highlighted-type\">" ~ name ~ "</span>";
						thisIterWasType = true;
					} else if(pythonConstants.canFind(name)) {
						highlighted ~= "<span class=\"highlighted-number\">" ~ name ~ "</span>";
					} else if(pythonPreprocessors.canFind(name)) {
						highlighted ~= "<span class=\"highlighted-preprocessor-directive\">" ~ name ~ "</span>";
					} else if(pythonKeywords.canFind(name)) {
						highlighted ~= "<span class=\"highlighted-keyword\">" ~ name ~ "</span>";
					} else {
						if(lastWasType) {
							highlighted ~= "<span class=\"highlighted-identifier\">" ~ name ~ "</span>";
						} else {
							highlighted ~= name;
						}
					}
				} else {
					highlighted ~= ch;
					code = code[1 .. $];
				}
			break;
		}
		lastChar = ch;
		lastWasType = thisIterWasType;
	}

	return Html(highlighted);
}

Html syntaxHighlightHtml(string code, string language) {
	string highlighted;

	bool isWhite(char c) {
		return c == ' ' || c == '\t' || c == '\n' || c == '\r';
	}

	while(code.length) {
		switch(code[0]) {
			case '<':
				if(code.length > 1 && code[1] == '!') {
					// comment or processing instruction

					int i = 0;
					while(i < code.length && code[i] != '>') {
						i++;
					}
					if(i < code.length)
						i++;

					highlighted ~= "<span class=\"highlighted-comment\">" ~ htmlEntitiesEncode(code[0 .. i]) ~ "</span>";
					code = code[i .. $];
					continue;
				} else if(code.length > 1 && (code[1] == '/' || (code[1] >= 'a' && code[1] <= 'z') || (code[1] >= 'A' && code[1] <= 'Z'))) {
					// possibly a tag
					int i = 1;
					while(i < code.length && code[i] != '>' && code[i] != '<')
						i++;
					if(i == code.length || code[i] == '<')
						goto plain_lt;

					auto tag = code[0 .. i + 1];
					code = code[i + 1 .. $];

					highlighted ~= "<span class=\"highlighted-tag\">" ~ highlightHtmlTag(tag) ~ "</span>";

					if(language == "html" && tag.startsWith("<script")) {
						auto end = code.indexOf("</script>");
						if(end == -1)
							continue;

						auto sCode = code[0 .. end];
						highlighted ~= syntaxHighlightCFamily(sCode, "javascript").source;
						code = code[end .. $];
					} else if(language == "html" && tag.startsWith("<style")) {
						auto end = code.indexOf("</style>");
						if(end == -1)
							continue;
						auto sCode = code[0 .. end];
						highlighted ~= syntaxHighlightCss(sCode).source;
						code = code[end .. $];
					}

					continue;
				}

				plain_lt:
				highlighted ~= "&lt;";
				code = code[1 .. $];
			break;
			case '"':
				highlighted ~= "&quot;";
				code = code[1 .. $];
			break;
			case '>':
				highlighted ~= "&gt;";
				code = code[1 .. $];
			break;
			case '&':
				// possibly an entity

				int i = 0;
				while(i < code.length && code[i] != ';' && !isWhite(code[i]))
					i++;
				if(i == code.length || isWhite(code[i])) {
					highlighted ~= "&amp;";
					code = code[1 .. $];
				} else {
					i++;
					highlighted ~= htmlEntitiesHighlight(code[0 .. i]);
					code = code[i .. $];
				}
			break;

			default:
				highlighted ~= code[0];
				code = code[1 .. $];
		}
	}

	return Html(highlighted);
}

Html syntaxHighlightSdlang(string jsCode) {
	string highlighted;

	bool isIdentifierChar(char c) {
		return
			(c >= 'a' && c <= 'z') ||
			(c >= 'A' && c <= 'Z') ||
			(c >= '0' && c <= '9') ||
			(c == '$' || c == '_');
	}

	bool startOfLine = true;

	while(jsCode.length) {
		switch(jsCode[0]) {
			case '\'':
			case '\"':
				// string literal
				char start = jsCode[0];
				size_t i = 1;
				while(i < jsCode.length && jsCode[i] != start && jsCode[i] != '\n') {
					if(jsCode[i] == '\\')
						i++; // skip escaped char too
					i++;
				}

				i++; // skip closer
				highlighted ~= "<span class=\"highlighted-string\">" ~ htmlEntitiesEncode(jsCode[0 .. i]) ~ "</span>";
				jsCode = jsCode[i .. $];
				startOfLine = false;
			break;
			case '-':
				if(jsCode.length > 1 && jsCode[1] == '-') {
					int i = 0;
					while(i < jsCode.length && jsCode[i] != '\n')
						i++;
					highlighted ~= "<span class=\"highlighted-comment\">" ~ htmlEntitiesEncode(jsCode[0 .. i]) ~ "</span>";
					jsCode = jsCode[i .. $];
				} else {
					highlighted ~= '-';
					jsCode = jsCode[1 .. $];
				}
			break;
			case '#':
				int i = 0;
				while(i < jsCode.length && jsCode[i] != '\n')
					i++;

				highlighted ~= "<span class=\"highlighted-comment\">" ~ htmlEntitiesEncode(jsCode[0 .. i]) ~ "</span>";
				jsCode = jsCode[i .. $];
			break;
			case '/':
				if(jsCode.length > 1 && (jsCode[1] == '*' || jsCode[1] == '/')) {
					// it is a comment
					if(jsCode[1] == '/') {
						size_t i;
						while(i < jsCode.length && jsCode[i] != '\n')
							i++;

						highlighted ~= "<span class=\"highlighted-comment\">" ~ htmlEntitiesEncode(jsCode[0 .. i]) ~ "</span>";
						jsCode = jsCode[i .. $];
					} else {
						// a star comment
						size_t i;
						while((i+1) < jsCode.length && !(jsCode[i] == '*' && jsCode[i+1] == '/'))
							i++;

						if(i < jsCode.length)
							i+=2; // skip the */

						highlighted ~= "<span class=\"highlighted-comment\">" ~ htmlEntitiesEncode(jsCode[0 .. i]) ~ "</span>";
						jsCode = jsCode[i .. $];
					}
				} else {
					highlighted ~= '/';
					jsCode = jsCode[1 .. $];
				}
			break;
			case '0': .. case '9':
				// number literal
				size_t i;
				while(i < jsCode.length && (
					(jsCode[i] >= '0' && jsCode[i] <= '9')
					||
					// really fuzzy but this is meant to highlight hex and exponents too
					jsCode[i] == '.' || jsCode[i] == 'e' || jsCode[i] == 'x' ||
					(jsCode[i] >= 'a' && jsCode[i] <= 'f') ||
					(jsCode[i] >= 'A' && jsCode[i] <= 'F')
				))
					i++;

				highlighted ~= "<span class=\"highlighted-number\">" ~ jsCode[0 .. i] ~ "</span>";
				jsCode = jsCode[i .. $];
				startOfLine = false;
			break;
			case '\t', ' ', '\r':
				highlighted ~= jsCode[0];
				jsCode = jsCode[1 .. $];
			break;
			case '\n':
				startOfLine = true;
				highlighted ~= jsCode[0];
				jsCode = jsCode[1 .. $];
			break;
			case '\\':
				if(jsCode.length > 1 && jsCode[1] == '\n') {
					highlighted ~= jsCode[0 .. 1];
					jsCode = jsCode[2 .. $];
				}
			break;
			case ';':
				startOfLine = true;
			break;
			// escape html chars
			case '<':
				highlighted ~= "&lt;";
				jsCode = jsCode[1 .. $];
				startOfLine = false;
			break;
			case '>':
				highlighted ~= "&gt;";
				jsCode = jsCode[1 .. $];
				startOfLine = false;
			break;
			case '&':
				highlighted ~= "&amp;";
				jsCode = jsCode[1 .. $];
				startOfLine = false;
			break;
			default:
				if(isIdentifierChar(jsCode[0])) {
					size_t i;
					while(i < jsCode.length && isIdentifierChar(jsCode[i]))
						i++;
					auto ident = jsCode[0 .. i];
					jsCode = jsCode[i .. $];

					if(startOfLine)
						highlighted ~= "<span class=\"highlighted-type\">" ~ ident ~ "</span>";
					else if(ident == "true" || ident == "false")
						highlighted ~= "<span class=\"highlighted-number\">" ~ ident ~ "</span>";
					else
						highlighted ~= "<span class=\"highlighted-attribute-name\">" ~ ident ~ "</span>";
				} else {
					highlighted ~= jsCode[0];
					jsCode = jsCode[1 .. $];
				}

				startOfLine = false;
		}
	}

	return Html(highlighted);

}

Html syntaxHighlightCFamily(string jsCode, string language) {
	string highlighted;

	bool isJsIdentifierChar(char c) {
		return
			(c >= 'a' && c <= 'z') ||
			(c >= 'A' && c <= 'Z') ||
			(c >= '0' && c <= '9') ||
			(c == '$' || c == '_');
	}

	while(jsCode.length) {


		switch(jsCode[0]) {
			case '\'':
			case '\"':
				// string literal
				char start = jsCode[0];
				size_t i = 1;
				while(i < jsCode.length && jsCode[i] != start && jsCode[i] != '\n') {
					if(jsCode[i] == '\\')
						i++; // skip escaped char too
					i++;
				}

				i++; // skip closer
				highlighted ~= "<span class=\"highlighted-string\">" ~ htmlEntitiesEncode(jsCode[0 .. i]) ~ "</span>";
				jsCode = jsCode[i .. $];
			break;
			case '#':
				// preprocessor directive / PHP # comment
				size_t i;
				while(i < jsCode.length && jsCode[i] != '\n')
					i++;

				if(language == "php")
					highlighted ~= "<span class=\"highlighted-comment\">" ~ htmlEntitiesEncode(jsCode[0 .. i]) ~ "</span>";
				else
					highlighted ~= "<span class=\"highlighted-preprocessor-directive\">" ~ htmlEntitiesEncode(jsCode[0 .. i]) ~ "</span>";
				jsCode = jsCode[i .. $];

			break;
			case '/':
				// check for comment
				// javascript also has that stupid regex literal, but screw it
				if(jsCode.length > 1 && (jsCode[1] == '*' || jsCode[1] == '/')) {
					// it is a comment
					if(jsCode[1] == '/') {
						size_t i;
						while(i < jsCode.length && jsCode[i] != '\n')
							i++;

						highlighted ~= "<span class=\"highlighted-comment\">" ~ htmlEntitiesEncode(jsCode[0 .. i]) ~ "</span>";
						jsCode = jsCode[i .. $];
					} else {
						// a star comment
						size_t i;
						while((i+1) < jsCode.length && !(jsCode[i] == '*' && jsCode[i+1] == '/'))
							i++;

						if(i < jsCode.length)
							i+=2; // skip the */

						highlighted ~= "<span class=\"highlighted-comment\">" ~ htmlEntitiesEncode(jsCode[0 .. i]) ~ "</span>";
						jsCode = jsCode[i .. $];
					}
				} else {
					highlighted ~= '/';
					jsCode = jsCode[1 .. $];
				}
			break;
			case '0': .. case '9':
				// number literal
				// FIXME: negative exponents are not done here
				// nor are negative numbers, but I think that needs parsing anyway
				// it also doesn't do all things right but the assumption is we're highlighting valid code anyway
				size_t i;
				while(i < jsCode.length && (
					(jsCode[i] >= '0' && jsCode[i] <= '9')
					||
					// really fuzzy but this is meant to highlight hex and exponents too
					jsCode[i] == '.' || jsCode[i] == 'e' || jsCode[i] == 'x' ||
					(jsCode[i] >= 'a' && jsCode[i] <= 'f') ||
					(jsCode[i] >= 'A' && jsCode[i] <= 'F')
				))
					i++;

				highlighted ~= "<span class=\"highlighted-number\">" ~ jsCode[0 .. i] ~ "</span>";
				jsCode = jsCode[i .. $];
			break;
			case '\t', ' ', '\n', '\r':
				highlighted ~= jsCode[0];
				jsCode = jsCode[1 .. $];
			break;
			case '?':
				if(language == "php") {
					if(jsCode.length >= 2 && jsCode[0 .. 2] == "?>") {
						highlighted ~= "<span class=\"highlighted-preprocessor-directive\">?&gt;</span>";
						jsCode = jsCode[2 .. $];
						break;
					}
				}
				highlighted ~= jsCode[0];
				jsCode = jsCode[1 .. $];
			break;
			// escape html chars
			case '<':
				if(language == "php") {
					if(jsCode.length > 5 && jsCode[0 .. 5] == "<?php") {
						highlighted ~= "<span class=\"highlighted-preprocessor-directive\">&lt;?php</span>";
						jsCode = jsCode[5 .. $];
						break;
					}
				}
				highlighted ~= "&lt;";
				jsCode = jsCode[1 .. $];
			break;
			case '>':
				highlighted ~= "&gt;";
				jsCode = jsCode[1 .. $];
			break;
			case '&':
				highlighted ~= "&amp;";
				jsCode = jsCode[1 .. $];
			break;
			case '@':
				// FIXME highlight UDAs
				//goto case;
			//break;
			default:
				if(isJsIdentifierChar(jsCode[0])) {
					size_t i;
					while(i < jsCode.length && isJsIdentifierChar(jsCode[i]))
						i++;
					auto ident = jsCode[0 .. i];
					jsCode = jsCode[i .. $];

					if(["function", "for", "in", "while", "new", "if", "else", "switch", "return", "break", "do", "delete", "this", "super", "continue", "goto"].canFind(ident))
						highlighted ~= "<span class=\"highlighted-keyword\">" ~ ident ~ "</span>";
					else if(["enum", "final", "virtual", "explicit", "var", "void", "const", "let", "int", "short", "unsigned", "char", "class", "struct", "float", "double", "typedef", "public", "protected", "private", "static"].canFind(ident))
						highlighted ~= "<span class=\"highlighted-type\">" ~ ident ~ "</span>";
					else if(language == "java" && ["extends", "implements"].canFind(ident))
						highlighted ~= "<span class=\"highlighted-type\">" ~ ident ~ "</span>";
					// FIXME: do i want to give using this same color?
					else if((language == "c#" || language == "c++") && ["using", "namespace"].canFind(ident))
						highlighted ~= "<span class=\"highlighted-type\">" ~ ident ~ "</span>";
					else if(language == "java" && ["native", "package", "import"].canFind(ident))
						highlighted ~= "<span class=\"highlighted-preprocessor-directive\">" ~ ident ~ "</span>";
					else if(ident[0] == '$')
						highlighted ~= "<span class=\"highlighted-identifier\">" ~ ident ~ "</span>";
					else
						highlighted ~= ident; // "<span>" ~ ident ~ "</span>";

				} else {
					highlighted ~= jsCode[0];
					jsCode = jsCode[1 .. $];
				}
		}
	}

	return Html(highlighted);
}
