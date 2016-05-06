module arsd.docgen.comment;

import adrdox.main;
import arsd.dom;

import dparse.ast;
import dparse.lexer;

import std.string;
import std.algorithm;

import std.conv;

const(char)[] htmlEncode(const(char)[] s) {
	return s.
		replace("&", "&amp;").
		replace("<", "&lt;").
		replace(">", "&gt;");
}


static struct MyOutputRange {
	this(string* output) {
		this.output = output;
	}

	string* output;
	void put(T...)(T s) {
		foreach(i; s)
			putTag(i.htmlEncode);
	}

	void putTag(in char[] s) {
		foreach(ch; s) {
			assert(s);
			assert(s.indexOf("</body>") == -1);
		}
		(*output) ~= s;
	}
}


/*
	Params:

	The line, excluding whitespace, must start with
	identifier = to start a new thing. If a new thing starts,
	it closes the old.

	The description may be formatted however. Whitespace is stripped.
*/

string getIdent(T)(T t) {
	if(t is null)
		return null;
	if(t.identifier == tok!"")
		return null;
	return t.identifier.text;
}

bool hasParam(T)(const T dec, string name) {
	if(dec is null)
		return false;

	if(dec.parameters && dec.parameters.parameters)
	foreach(parameter; dec.parameters.parameters)
		if(parameter.name.text == name)
			return true;
	if(dec.templateParameters && dec.templateParameters.templateParameterList)
	foreach(parameter; dec.templateParameters.templateParameterList.items) {
		if(getIdent(parameter.templateTypeParameter) == name)
			return true;
		if(getIdent(parameter.templateValueParameter) == name)
			return true;
		if(getIdent(parameter.templateAliasParameter) == name)
			return true;
		if(getIdent(parameter.templateTupleParameter) == name)
			return true;
		if(parameter.templateThisParameter && getIdent(parameter.templateThisParameter.templateTypeParameter) == name)
			return true;
	}
	return false;
}

struct DocComment {
	string ddocSummary;
	string synopsis;

	string details;

	string[] params; // stored as ident=txt. You can split on first index of =.
	string returns;
	string examples;
	string diagnostics;
	string throws;
	string bugs;
	string see_alsos;

	string[string] otherSections;

	Decl decl;

	bool synopsisEndedOnDoubleBlank;

	void writeSynopsis(MyOutputRange output) {
		output.putTag("<div class=\"documentation-comment synopsis\">");
			output.putTag(synopsis);
			if(details !is synopsis && details.strip.length && details.strip != "<div></div>")
				output.putTag(` <a id="more-link" href="#details">More...</a>`);
		output.putTag("</div>");
	}

	import std.typecons : Tuple;
	void writeDetails(T = FunctionDeclaration)(MyOutputRange output) {
		writeDetails!T(output, cast(T) null, null);
	}

	void writeDetails(T = FunctionDeclaration)(MyOutputRange output, const T functionDec = null, Tuple!(string, string)[] utInfo = null) {
		auto f = new MyFormatter!(typeof(output))(output, decl);

		if(params.length) {
			output.putTag("<h2 id=\"parameters\">Parameters</h2>");
			output.putTag("<dl class=\"parameter-descriptions\">");
			foreach(param; params) {
				auto split = param.indexOf("=");
				auto paramName = param[0 .. split];

				if(!hasParam(functionDec, paramName))
					continue;

				output.putTag("<dt id=\"param-"~param[0 .. split]~"\">");
				output.putTag("<a href=\"#param-"~param[0 .. split]~"\" class=\"parameter-name\" data-ident=\"");
					output.put(param[0 .. split]);
				output.putTag("\">");
				output.put(param[0 .. split]);
				output.putTag("</a>");
				output.putTag("</dt>");
				output.putTag("<dd>");

				if(functionDec !is null) {
					const(Parameter)* paramAst;
					foreach(ref p; functionDec.parameters.parameters) {
						if(p.name.type != tok!"")
							if(p.name.text == param[0 .. split]) {
								paramAst = &p;
								break;
							}
					}

					if(paramAst) {
						output.putTag("<div class=\"parameter-type-holder\">");
						output.putTag("Type: ");
						output.putTag("<span class=\"parameter-type\">");
							f.format(paramAst.type);
						output.putTag("</span>");
						output.putTag("</div>");
					}
				}


				output.putTag("<div class=\"documentation-comment\">");
				output.putTag(formatDocumentationComment(param[split + 1 .. $], decl));
				output.putTag("</div></dd>");
			}
			output.putTag("</dl>");
		}

		static if(!is(T == Constructor))
		if(returns !is null) {
			output.putTag("<h2 id=\"returns\">Return Value</h2>");
			output.putTag("<div>");
			if(functionDec !is null) {
				output.putTag("<div class=\"return-type-holder\">");
				output.putTag("Type: ");
				output.putTag("<span class=\"return-type\">");
				if(functionDec.hasAuto && functionDec.hasRef)
					output.putTag(`<a class="lang-feature" href="http://dpldocs.info/auto-ref-function-return-prototype">auto ref</a> `);
				else {
					if (functionDec.hasAuto)
						output.putTag(`<a class="lang-feature" href="http://dpldocs.info/auto-function-return-prototype">auto</a> `);
					if (functionDec.hasRef)
						output.putTag(`<a class="lang-feature" href="http://dpldocs.info/ref-function-return-prototype">ref</a> `);
				}

				if (functionDec.returnType !is null)
					f.format(functionDec.returnType);
				output.putTag("</span>");
				output.putTag("</div>");
			}
			output.putTag(formatDocumentationComment(returns, decl));
			output.putTag("</div>");
		}

		if(details.strip.length && details.strip != "<div></div>") {
			output.putTag("<h2 id=\"details\">Detailed Description</h2>");
			output.putTag("<div class=\"documentation-comment detailed-description\">");
				output.putTag(details);
			output.putTag("</div>");
		}

		if(throws.strip.length) {
			output.putTag("<h2 id=\"throws\">Throws</h2>");
			output.putTag("<div class=\"documentation-comment throws-description\">");
				output.putTag(formatDocumentationComment(throws, decl));
			output.putTag("</div>");
		}


		if(diagnostics.strip.length) {
			output.putTag("<h2 id=\"diagnostics\">Common Problems</h2>");
			output.putTag("<div class=\"documentation-comment diagnostics\">");
				output.putTag(formatDocumentationComment(diagnostics, decl));
			output.putTag("</div>");
		}

		if(bugs.strip.length) {
			output.putTag("<h2 id=\"bugs\">Bugs</h2>");
			output.putTag("<div class=\"documentation-comment bugs-description\">");
				output.putTag(formatDocumentationComment(throws, decl));
			output.putTag("</div>");
		}


		if(examples.length || utInfo.length) {
			output.putTag("<h2 id=\"examples\"><a href=\"#examples\" class=\"header-anchor\">Examples</a></h2>");
			output.putTag(formatDocumentationComment(examples, decl));

			foreach(example; utInfo) {
				output.putTag("<div class=\"unittest-example-holder\">");
				output.putTag(formatDocumentationComment(preprocessComment(example[1]), decl));
				output.putTag("</div>");
				output.putTag("<pre class=\"d_code highlighted\">");
				output.putTag(highlight(outdent(example[0])));
				output.putTag("</pre>");
			}
		}

		if(see_alsos.length) {
			output.putTag("<h2 id=\"see-also\">See Also</h2>");
			output.putTag(formatDocumentationComment(see_alsos, decl));
		}

		if(otherSections.keys.length) {
			output.putTag("<h2 id=\"meta\">Meta</h2>");
		}

		foreach(section, content; otherSections) {
			output.putTag("<div class=\"documentation-comment " ~ section ~ "-section other-section\">");
			output.putTag("<h3>");
				output.put(section.capitalize);
			output.putTag("</h3>");
			output.putTag(formatDocumentationComment(content, decl));
			output.putTag("</div>");
		}
	}
}

string preprocessComment(string comment) {
	if(comment.length < 3)
		return comment;

	comment = comment[1 .. $]; // trim off the /

	auto commentType = comment[0];

	while(comment.length && comment[0] == commentType)
		comment = comment[1 .. $]; // trim off other opening spam

	string closingSpam;
	if(commentType == '*' || commentType == '+') {
		comment = comment[0 .. $-1]; // trim off the closing /
		bool closingSpamFound;
		while(comment.length && comment[$-1] == commentType) {
			comment = comment[0 .. $-1]; // trim off other closing spam
			closingSpamFound = true;
		}

		if(closingSpamFound) {
			// if there was closing spam we also want to count the spaces before it
			// to trim off other line spam. The goal here is to clean up
			    /**
			     * Resolve host name.
			     * Returns: false if unable to resolve.
			     */
			// into just "Resolve host name.\n Returns: false if unable to resolve."
			// give or take some irrelevant whitespace.
			while(comment.length && (comment[$-1] == '\t' || comment[$-1] == ' ')) {
				closingSpam = comment[$-1] ~ closingSpam;
				comment = comment[0 .. $-1]; // trim off other closing spam
			}

			if(closingSpam.length == 0)
				closingSpam = " "; // some things use the " *" leader, but still end with "*/" on a line of its own
		}
	}


	string poop;
	if(commentType == '/')
		poop = "///";
	else
		poop = closingSpam ~ commentType ~ " ";

	string newComment;
	foreach(line; comment.splitter("\n")) {
		// check for "  * some text"
		if(line.length >= poop.length && line.startsWith(poop)) {
			if(line.length > poop.length && line[poop.length] == ' ')
				newComment ~= line[poop.length + 1 .. $];
			else
				newComment ~= line[poop.length .. $];
		}
		// check for an empty line with just "  *"
		else if(line.length == poop.length-1 && line[0..poop.length-1] == poop[0..$-1])
			{} // this space is intentionally left blank; it is an empty line
		else
			newComment ~= line;
		newComment ~= "\n";
	}

	comment = newComment;
	return comment;
}

DocComment parseDocumentationComment(string comment, Decl decl) {
	DocComment c;

	if(decl.lineNumber)
		c.otherSections["source"] ~= "$(LINK2 source/"~decl.parentModule.name~".d.html#L"~to!string(decl.lineNumber)~", Annotated source)$(BR)";

	c.decl = decl;

	comment = preprocessComment(comment);

	void parseSections(string comment) {
		string remaining;
		string section;
		bool inSynopsis = true;
		bool justSawBlank = false;
		bool inCode = false;
		bool hasAnySynopsis = false;
		bool inDdocSummary = true;
		bool synopsisEndedOnDoubleBlank = false;
		foreach(line; comment.splitter("\n")) {
			auto maybe = line.strip.toLower;

			if(maybe.startsWith("---")) {
				justSawBlank = false;
				inDdocSummary = false;
				inCode = !inCode;
			}
			if(inCode){ 
				justSawBlank = false;
				goto ss; // sections never change while in a code example
			}

			if(inSynopsis && hasAnySynopsis && maybe.length == 0) {
				// any empty line ends the ddoc summary
				inDdocSummary = false;
				// two blank lines in a row ends the synopsis
				if(justSawBlank) {
					inSynopsis = false;
					// synopsis can also end on the presence of another
					// section, so this is tracked to see how intentional
					// the break looked (Phobos docs aren't written with
					// a double-break in mind)
					synopsisEndedOnDoubleBlank = true;
				}
				justSawBlank = true;
			} else {
				justSawBlank = false;
			}

			if(maybe.startsWith("params:")) {
				section = "params";
				inSynopsis = false;
			} else if(maybe.startsWith("returns:")) {
				section = "returns";
				line = line[line.indexOf(":")+1 .. $];
				inSynopsis = false;
			} else if(maybe.startsWith("throws:")) {
				section = "throws";
				inSynopsis = false;
				line = line[line.indexOf(":")+1 .. $];
			} else if(maybe.startsWith("author:")) {
				section = "authors";
				line = line[line.indexOf(":")+1 .. $];
				inSynopsis = false;
			} else if(maybe.startsWith("authors:")) {
				section = "authors";
				line = line[line.indexOf(":")+1 .. $];
				inSynopsis = false;
			} else if(maybe.startsWith("source:")) {
				section = "source";
				line = line[line.indexOf(":")+1 .. $];
				inSynopsis = false;
			} else if(maybe.startsWith("history:")) {
				section = "history";
				line = line[line.indexOf(":")+1 .. $];
				inSynopsis = false;
			} else if(maybe.startsWith("credits:")) {
				section = "credits";
				line = line[line.indexOf(":")+1 .. $];
				inSynopsis = false;
			} else if(maybe.startsWith("version:")) {
				section = "version";
				line = line[line.indexOf(":")+1 .. $];
				inSynopsis = false;
			} else if(maybe.startsWith("license:")) {
				section = "license";
				line = line[line.indexOf(":")+1 .. $];
				inSynopsis = false;
			} else if(maybe.startsWith("copyright:")) {
				section = "copyright";
				line = line[line.indexOf(":")+1 .. $];
				inSynopsis = false;
			} else if(maybe.startsWith("see_also:")) {
				section = "see_also";
				inSynopsis = false;
				line = line[line.indexOf(":")+1 .. $];
			} else if(maybe.startsWith("diagnostics:")) {
				inSynopsis = false;
				section = "diagnostics";
				line = line[line.indexOf(":")+1 .. $];
			} else if(maybe.startsWith("examples:")) {
				inSynopsis = false;
				section = "examples";
				line = line[line.indexOf(":")+1 .. $];
			} else if(maybe.startsWith("example:")) {
				inSynopsis = false;
				line = line[line.indexOf(":")+1 .. $];
				section = "examples"; // Phobos uses example, the standard is examples.
			} else if(maybe.startsWith("version:")) {
				inSynopsis = false;
				line = line[line.indexOf(":")+1 .. $];
				section = "version";
			} else if(maybe.startsWith("standards:")) {
				inSynopsis = false;
				section = "standards";
			} else if(maybe.startsWith("deprecated:")) {
				inSynopsis = false;
				section = "deprecated";
			} else if(maybe.startsWith("date:")) {
				inSynopsis = false;
				section = "date";
			} else if(maybe.startsWith("bugs:")) {
				inSynopsis = false;
				section = "bugs";
			} else if(maybe.startsWith("macros:")) {
				inSynopsis = false;
				section = "macros";
			} else if(maybe.isDdocSection()) {
				inSynopsis = false;

				auto idx2 = line.indexOf(":");
				auto name = line[0 .. idx2].replace("_", " ");
				line = "$(H3 "~name~")\n\n" ~ line[idx2+1 .. $];
			} else {
				// no change to section
			}

			if(inSynopsis == false)
				inDdocSummary = false;


			ss: switch(section) {
				case "params":
					bool lookingForIdent = true;
					bool inIdent;
					bool skippingSpace;
					size_t space_at;

					auto lol = line.strip;
					foreach(idx, ch; lol) {
						import std.uni, std.ascii : isAlphaNum;
						if(lookingForIdent && !inIdent) {
							if(!isAlpha(ch) && ch != '_')
								continue;
							inIdent = true;
							lookingForIdent = false;
						}

						if(inIdent) {
							if(ch == '_' || isAlphaNum(ch) || isAlpha(ch))
								continue;
							else {
								skippingSpace = true;
								inIdent = false;
								space_at = idx;
							}
						}
						if(skippingSpace) {
							if(!isWhite(ch)) {
								if(ch == '=') {
									// we finally hit a thingy
									c.params ~= lol[0 .. space_at] ~ "=" ~ lol[idx + 1 .. $] ~ "\n";
									break ss;
								} else
									// we are expecting whitespace or = and hit
									// neither.. this can't be ident = desc!
									break;
							}
						}
					}

					if(c.params.length)
						c.params[$-1] ~= line ~ "\n";
				break;
				case "see_also":
					c.see_alsos ~= line ~ "\n";
				break;
				case "macros":
					// ignoring for now
				break;
				case "returns":
					c.returns ~= line ~ "\n";
				break;
				case "diagnostics":
					c.diagnostics ~= line ~ "\n";
				break;
				case "throws":
					c.throws ~= line ~ "\n";
				break;
				case "bugs":
					c.bugs ~= line ~ "\n";
				break;
				case "authors":
				case "license":
				case "source":
				case "history":
				case "credits":
				case "standards":
				case "copyright":
				case "version":
					c.otherSections[section] ~= line ~ "\n";
				break;
				case "examples":
					c.examples ~= line ~ "\n";
				break;
				default:
					if(inSynopsis) {
						if(inDdocSummary)
							c.ddocSummary ~= line ~ "\n";
						c.synopsis ~= line ~ "\n";
						if(line.length)
							hasAnySynopsis = true;
					} else
						remaining ~= line ~ "\n";
			}
		}

		c.ddocSummary = formatDocumentationComment(c.ddocSummary, decl);
		c.synopsis = formatDocumentationComment(c.synopsis, decl);
		c.details = formatDocumentationComment(remaining, decl);
		c.synopsisEndedOnDoubleBlank = synopsisEndedOnDoubleBlank;
	}

	parseSections(comment);

	return c;
}

bool isDdocSection(string s) {
	bool hasUnderscore = false;
	foreach(idx, char c; s) {
		if(c == '_')
			hasUnderscore = true;
		if(!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'))
			return hasUnderscore && c == ':';
	}
	return false;
}

bool isIdentifierChar(size_t idx, dchar ch) {
	import std.uni;
	if(!(isAlpha(ch) || (idx != 0 && isNumber(ch)) || ch == '_'))
		return false;
	return true;
}

bool isIdentifierOrUrl(string text) {
	import std.uri;
	auto l = uriLength(text);

	if(l != -1)
		return true; // is url

	if(text.length && text[0] == '#')
		return true; // is local url link

	import std.uni;
	foreach(idx, dchar ch; text) {
		if(!isIdentifierChar(idx, ch) && ch != '.')
			return false;
	}

	// passed the ident test...
	if(text.length)
		return true;

	return false;

}

Element getReferenceLink(string text, Decl decl, string realText = null) {
	if(realText is null)
		realText = text;

	import std.uri;
	auto l = uriLength(text);
	string hash;

	string className;

	if(l != -1 || text.length && text[0] == '#')
		text = text;
	else {
		auto found = decl.lookupName(text);

		className = "xref";

		if(found is null) {
			auto lastPieceIdx = text.lastIndexOf(".");
			if(lastPieceIdx != -1) {
				found = decl.lookupName(text[0 .. lastPieceIdx]);
				if(found)
					hash = "#" ~ text[lastPieceIdx + 1 .. $];
			}
		}

		if(found !is null)
			text = found.link;
		else
			text ~= ".html";
	}

	auto element = Element.make("a");
	element.className = className;
	element.href = text ~ hash;
	element.innerText = realText;
	return element;
}

struct DocCommentTerminationCondition {
	string[] terminationStrings;
	bool mustBeAtStartOfLine;
	string remaining;
	string terminatedOn;
}

Element formatDocumentationComment2(string comment, Decl decl, string tagName = "div", DocCommentTerminationCondition* termination = null) {
	Element div;
	if(tagName is null)
		div = new DocumentFragment(null);
	else
		div = Element.make(tagName);

	string currentParagraph;
	void putch(char c) {
		currentParagraph ~= c;
	}
	void put(in char[] c) {
		currentParagraph ~= c;
	}

	string currentTag = (tagName is null) ? null : "p";

	void commit() {
		auto cp = currentParagraph.strip;
		if(cp.length) {
			if(currentTag is null)
				div.appendHtml(cp);
			else
				div.addChild(currentTag, Html(cp));
		}
		currentTag = "p";
		currentParagraph = null;
	}

	bool atStartOfLine = true;
	bool earlyTermination;

	main_loop:
	for(size_t idx = 0; idx < comment.length; idx++) {
		auto ch = comment[idx];
		auto remaining = comment[idx .. $];

		if(termination !is null) {
			if((termination.mustBeAtStartOfLine && atStartOfLine) || !termination.mustBeAtStartOfLine) {
				foreach(ts; termination.terminationStrings) {
					if(remaining.startsWith(ts)) {
						termination.remaining = remaining[ts.length .. $];
						earlyTermination = true;
						termination.terminatedOn = ts;
						break main_loop;
					}
				}
			}
		}

		switch(ch) {
			case '\r':
				continue; // don't care even a little about Windows vs Unix line endings
			case ' ', '\t':
				goto useCharWithoutTriggeringStartOfLine;
			case '\n':
				if(atStartOfLine)
					commit();
				atStartOfLine = true;
				goto useCharWithoutTriggeringStartOfLine;
			break;
			// these need to be html encoded
			case '"':
				put("&quot;");
				atStartOfLine = false;
			break;
			case '<':
				// FIXME: support just a wee bit of inline html...
				put("&lt;");
				atStartOfLine = false;
			break;
			case '>':
				put("&gt;");
				atStartOfLine = false;
			break;
			case '&':
				put("&amp;");
				atStartOfLine = false;
			break;
			// special syntax
			case '`':
				// code. ` is inline, ``` is block.
				if(atStartOfLine && remaining.startsWith("```")) {
					idx += 3;
					remaining = remaining[3 .. $];
					bool braced = false;
					if(remaining.length && remaining[0] == '{') {
						braced = true;
						remaining = remaining[1 .. $];
					}

					auto line = remaining.indexOf("\n");
					string language;
					if(line != -1) {
						language = remaining[0 .. line].strip;
						remaining = remaining[line + 1 .. $];
						idx += line + 1;
					}

					size_t ending;
					size_t sliceEnding;
					if(braced) {
						int count = 1;
						while(ending < remaining.length) {
							if(remaining[ending] == '{')
								count++;
							if(remaining[ending] == '}')
								count--;

							if(count == 0)
								break;
							ending++;
						}

						sliceEnding = ending;

						while(ending < remaining.length) {
							if(remaining[ending] == '\n') {
								ending++;
								break;
							}
							ending++;
						}

					} else {
						ending = remaining.indexOf("```\n");
						if(ending != -1) {
							sliceEnding = ending;
							ending += 4; // skip \n
						} else {
							ending = remaining.indexOf("```\r");

							if(ending != -1) {
								sliceEnding = ending;
								ending += 5; // skip \r\n
							} else {
								ending = remaining.length;
								sliceEnding = ending;
							}
						}
					}

					if(currentTag == "p")
						commit();
					// FIXME: we can prolly do more with languages...
					string code = outdent(stripRight(remaining[0 .. sliceEnding]));
					Element ele;
					// all these languages are close enough for hack good enough.
					if(language == "javascript" || language == "c" || language == "c++" || language == "java" || language == "php")
						ele = div.addChild("pre", syntaxHighlightJavascript(code));
					else
						ele = div.addChild("pre", code);
					ele.addClass("block-code");
					ele.dataset.language = language;
					idx += ending;
				} else {
					// check for inline `code` style
					bool foundIt = false;
					size_t foundItWhere = 0;
					foreach(i, scout; remaining[1 .. $]) {
						if(scout == '\n')
							break;
						if(scout == '`') {
							foundIt = true;
							foundItWhere = i;
							break;
						}
					}

					if(!foundIt)
						goto ordinary;

					atStartOfLine = false;
					auto slice = remaining[1 .. foundItWhere + 1];
					idx += 1 + foundItWhere;

					auto ele = Element.make("tt").addClass("inline-code");
					ele.innerText = slice;
					put(ele.toString());
				}
			break;
			case '$':
				// ddoc macro. May be magical.
				auto info = macroInformation(remaining);
				if(info.linesSpanned == 0) {
					goto ordinary;
				}

				atStartOfLine = false;

				auto name = remaining[2 .. info.macroNameEndingOffset];

				auto dzeroAdjustment = (info.textBeginningOffset == info.terminatingOffset) ? 0 : 1;
				auto text = remaining[info.textBeginningOffset .. info.terminatingOffset - dzeroAdjustment];

				if(name in ddocMacroBlocks) {
					commit();

					auto got = expandDdocMacros(remaining, decl);
					div.appendChild(got);
				} else {
					put(expandDdocMacros(remaining, decl).toString());
				}

				idx += info.terminatingOffset - 1;
			break;
			case '-':
				// ddoc style code iff --- at start of line.
				if(!atStartOfLine) {
					goto ordinary;
				}
				if(remaining.startsWith("---")) {
					// a code sample has started
					if(currentTag == "p")
						commit();
					div.addChild("pre", extractDdocCodeExample(remaining, idx)).addClass("d_code highlighted");
					atStartOfLine = true;
				} else
					goto ordinary;
			break;
			case '[':
				// wiki-style reference iff [[text]] or [[text|other text]]
				// text MUST be either a valid D identifier chain or a fully-encoded http url.
				// text may never include ']' or '|' or whitespace or ',' and must always start with '_' or alphabetic (like a D identifier or http url)
				// other text may include anything except the string ']]'
				// it balances [] inside it.

				auto txt = extractBalance(remaining);
				if(txt is null)
					goto ordinary;

				auto fun = txt[1 .. $-1];
				auto rt = fun;
				auto idx2 = fun.indexOf("|");
				if(idx2 != -1) {
					rt = fun[idx2 + 1 .. $].strip;
					fun = fun[0 .. idx2].strip;
				}

				if(!fun.isIdentifierOrUrl())
					goto ordinary;

				//FIXME
				put(getReferenceLink(fun, decl, rt).toString);

				idx += txt.length;
				idx --; // so the ++ in the for loop brings us back to i
			break;
			case 'h':
				// automatically linkify web URLs pasted in
				if(tagName is null)
					goto ordinary;
				import std.uri;
				auto l = uriLength(remaining);
				if(l == -1)
					goto ordinary;
				auto url = remaining[0 .. l];
				put("<a href=\"" ~ url ~ "\">" ~ url ~ "</a>");
				idx += url.length;
				idx --; // so the ++ puts us at the end
			break;
			case '_':
				// is it that stupid ddocism where a PSYMBOL is prefixed with _?
				// still, really, I want to KILL this completely, I hate it a lot
				if(idx && !isIdentifierChar(1, comment[idx-1]) && checkStupidDdocIsm(remaining[1..$], decl))
					break;
				else
					goto ordinary;
			break;
			/*
				/+ I'm just not happy with this yet because it thinks

				Paragraph
					* list item
				After stuff

				the After stuff is part of the list item. Blargh.

				+/
			case '*':
				// potential list item
				if(atStartOfLine) {
					commit();
					currentTag = "li";
					atStartOfLine = false;
					continue;
				} else {
					goto ordinary;
				}
			break;
			*/
			default:
			ordinary:
				atStartOfLine = false;
				useCharWithoutTriggeringStartOfLine:
				putch(ch);
		}
	}

	commit();

	if(termination !is null && !earlyTermination)
		termination.remaining = null;

	return div;
}

bool checkStupidDdocIsm(string remaining, Decl decl) {
	size_t i;
	foreach(idx, dchar ch; remaining) {
		if(!isIdentifierChar(idx, ch)) {
			i = idx;
			break;
		}
	}

	string ident = remaining[0 ..  i];
	import std.stdio; writeln("stupid ddocism: ", ident);
	if(ident.length == 0)
		return false;

	// check this name
	if(ident == decl.name)
		return true;

	if(decl.isModule) {
		auto name = decl.name;
		auto idx = name.lastIndexOf(".");
		if(idx != -1) {
			name = name[idx + 1 .. $];
		}

		if(ident == name)
			return true;
	}

	// check the whole scope too, I think dmd does... maybe
	if(decl.lookupName(ident) !is null)
		return true;

	// FIXME: params?

	return false;
}

string extractBalance(string txt) {
	if(txt.length == 0) return null;
	char starter = txt[0];
	char terminator;
	switch(starter) {
		case '[':
			terminator = ']';
		break;
		case '(':
			terminator = ')';
		break;
		case '{':
			terminator = '}';
		break;
		default:
			return null;
	}

	int count;
	foreach(idx, ch; txt) {
		if(ch == starter)
			count++;
		else if(ch == terminator)
			count--;

		if(count == 0)
			return txt[0 .. idx + 1];
	}

	return null; // unbalanced prolly
}

Html extractDdocCodeExample(string comment, ref size_t idx) {
	assert(comment.startsWith("---"));
	auto i = comment.indexOf("\n");
	if(i == -1)
		return Html(htmlEncode(comment).idup);
	comment = comment[i + 1 .. $];
	idx += i + 1;

	LexerConfig config;
	StringCache stringCache = StringCache(128);

	config.stringBehavior = StringBehavior.source;
	config.whitespaceBehavior = WhitespaceBehavior.include;

	ubyte[] lies = cast(ubyte[]) comment;

	// I'm tokenizing to handle stuff like --- inside strings and
	// comments inside the code. If we hit an "operator" -- followed by -
	// or -- followed by --, right after some whitespace including a line, 
	// we're done.
	bool justSawNewLine = true;
	bool justSawDashDash = false;
	size_t terminatingIndex;
	lexing:
	foreach(token; byToken(lies, config, &stringCache)) {
		if(justSawDashDash) {
			if(token == tok!"--" || token == tok!"-") {
				break lexing;
			}
		}

		if(justSawNewLine) {
			if(token == tok!"--") {
				justSawDashDash = true;
				justSawNewLine = false;
				terminatingIndex = token.index;
				continue lexing;
			}
		}

		if(token == tok!"whitespace") {
			foreach(txt; token.text)
				if(txt == '\n') {
					justSawNewLine = true;
					continue lexing;
				}
		}

		justSawNewLine = false;
	}

	i = comment.indexOf('\n', terminatingIndex);
	if(i == -1)
		i = comment.length;

	idx += i;

	comment = comment[0 .. terminatingIndex];

	return Html(outdent(highlight(comment.stripRight)));
}

string[string] ddocMacros;
int[string] ddocMacroInfo;
int[string] ddocMacroBlocks;

static this() {
	ddocMacroBlocks = [
		"ADRDOX_SAMPLE" : 1,
		"LIST": 1,
		"NUMBERED_LIST": 1,
		"SMALL_TABLE" : 1,
		"TABLE_ROWS" : 1,

		"TIP":1,
		"NOTE":1,
		"WARNING":1,
		"PITFALL":1,
		"SIDEBAR":1,
		"CONSOLE":1,
		"H1":1,
		"H2":1,
		"H3":1,
		"H4":1,
		"H5":1,
		"H5":1,
		"HR":1,
		"BOOKTABLE":1,
		"T2":1,

		"TR" : 1,
		"TH" : 1,
		"TD" : 1,
		"TDNW" : 1,

		"UL" : 1,
		"OL" : 1,
		"LI" : 1,

		"P" : 1,
		"PRE" : 1,
		"BLOCKQUOTE" : 1,
		"DL" : 1,
		"DT" : 1,
		"DD" : 1,
		"POST" : 1,

		"DIVC" : 1,

		// std.regex
		"REG_ROW": 1,
		"REG_TITLE": 1,
		"REG_TABLE": 1,
		"REG_START": 1,
		"SECTION": 1,

		// std.math
		"TABLE_SV" : 1,
		"TABLE_DOMRG": 1,
		"DOMAIN": 1,
		"RANGE": 1,
		"SVH": 1,
		"SV": 1,
	];

	ddocMacros = [
		"FULLY_QUALIFIED_NAME" : "MAGIC", // decl.fullyQualifiedName,
		"MODULE_NAME" : "MAGIC", // decl.parentModule.fullyQualifiedName,
		"D" : "<tt class=\"D\">$0</tt>", // this is magical! D is actually handled in code.
		"REF" : `<a href="$0.html">$0</a>`, // this is magical! Handles ref in code

		"TIP" : "<div class=\"tip\">$0</div>",
		"NOTE" : "<div class=\"note\">$0</div>",
		"WARNING" : "<div class=\"warning\">$0</div>",
		"PITFALL" : "<div class=\"pitfall\">$0</div>",
		"SIDEBAR" : "<div class=\"sidebar\">$0</div>",
		"CONSOLE" : "<pre class=\"console\">$0</pre>",

		// headers have meaning to the table of contents generator
		"H1" : "<h1 class=\"user-header\">$0</h1>",
		"H2" : "<h2 class=\"user-header\">$0</h2>",
		"H3" : "<h3 class=\"user-header\">$0</h3>",
		"H4" : "<h4 class=\"user-header\">$0</h4>",
		"H5" : "<h5 class=\"user-header\">$0</h5>",
		"H6" : "<h6 class=\"user-header\">$0</h6>",

		"HR" : "<hr />",

		// DDoc just expects these.
		"AMP" : "&",
		"LT" : "<",
		"GT" : ">",
		"LPAREN" : "(",
		"RPAREN" : ")",
		"DOLLAR" : "$",
		"BACKTICK" : "`",
		"COMMA": ",",
		"ARGS" : "$0",

		// support for my docs' legacy components, will be removed before too long.
		"DDOC_ANCHOR" : "<a id=\"$0\" href=\"$(FULLY_QUALIFIED_NAME).html#$0\">$0</a>",

		// this is support for the Phobos docs

		// useful parts
		"BOOKTABLE" : "<table class=\"phobos-booktable\"><caption>$1</caption>$+</table>",
		"T2" : "<tr><td>$(LREF $1)</td><td>$+</td></tr>",

		"BIGOH" : "<span class=\"big-o\"><i>O</i>($0)</span>",

		"TR" : "<tr>$0</tr>",
		"TH" : "<th>$0</th>",
		"TD" : "<td>$0</td>",
		"TDNW" : "<td>$0</td>",

		"UL" : "<ul>$0</ul>",
		"OL" : "<ol>$0</ol>",
		"LI" : "<li>$0</li>",

		"BR" : "<br />",
		"I" : "<i>$0</i>",
		"B" : "<b>$0</b>",
		"P" : "<p>$0</p>",
		"PRE" : "<pre>$0</pre>",
		"BLOCKQUOTE" : "<blockquote>$0</blockquote>", // FIXME?
		"DL" : "<dl>$0</dl>",
		"DT" : "<dt>$0</dt>",
		"DD" : "<dd>$0</dd>",
		"LINK2" : "<a href=\"$1\">$2</a>",

		"SCRIPT" : "",

		// Useless crap that should just be replaced
		"D_PARAM" : "$(D $0)",
		"SUBMODULE" : `<a href="$(FULLY_QUALIFIED_NAME).$0.html">$0</a>`,
		"SUBREF" : `<a href="$(FULLY_QUALIFIED_NAME).$1.$2.html">$2</a>`,
		"SHORTXREF" : `<a href="std.$1.$2.html">$2</a>`,
		"SHORTXREF_PACK" : `<a href="std.$1.$2.$3.html">$3</a>`,
		"XREF" : `<a href="std.$1.$2.html">std.$1.$2</a>`,
		"CXREF" : `<a href="core.$1.$2.html">core.$1.$2</a>`,
		"XREF_PACK" : `<a href="std.$1.$2.$3.html">std.$1.$2.$3</a>`,
		"MYREF" : `<a href="$(FULLY_QUALIFIED_NAME).$0.html">$0</a>`,
		"LREF" : `<a class="symbol-reference" href="$(MODULE_NAME).$0.html">$0</a>`,
		"MREF" : `MAGIC`,
		"WEB" : `<a href="http://$1">$2</a>`,
		"XREF_PACK_NAMED" : `<a href="std.$1.$2.$3.html">$4</a>`,

		"RES": `<i>result</i>`,
		"POST": `<div class="postcondition">$0</div>`,
		"COMMENT" : ``,

		"DIVC" : `<div class="$1">$+</div>`,

		// std.regex
		"REG_ROW":`<tr><td><i>$1</i></td><td>$+</td></tr>`,
		"REG_TITLE":`<tr><td><b>$1</b></td><td><b>$2</b></td></tr>`,
		"REG_TABLE":`<table border="1" cellspacing="0" cellpadding="5" > $0 </table>`,
		"REG_START":`<h3><div align="center"> $0 </div></h3>`,
		"SECTION":`<h3><a id="$0">$0</a></h3>`,
		"S_LINK":`<a href="#$1">$+</a>`,

		// std.math

		"TABLE_SV": `<table class="std_math special-values"><caption>Special Values</caption>$0</table>`,
		"SVH" : `<tr><th>$1</th><th>$2</th></tr>`,
		"SV" : `<tr><td>$1</td><td>$2</td></tr>`,
		"TABLE_DOMRG": `<table class="std_math domain-and-range">$0</table>`,
		"DOMAIN": `<tr><th>Domain</th><td>$0</td></tr>`,
		"RANGE": `<tr><th>Range</th><td>$0</td></tr>`,

		"PI": "\u03c0",
		"INFIN": "\u221e",
		"SUB": "<span>$1<sub>$2</sub></span>",
		"SQRT" : "\u221a",
		"SUPERSCRIPT": "<sup>$1</sup>",
		"POWER": "<span>$1<sup>$2</sup></span>",
		"NAN": "<span class=\"nan\">NaN</span>",
		"PLUSMN": "\u00b1",
		"GLOSSARY": `<a href="http://dlang.org/glosary.html#$0">$0</a>`,
		"PHOBOSSRC": `<a href="https://github.com/D-Programming-Language/phobos/blob/master/$0">$0</a>`,
	];

	ddocMacroInfo = [ // number of arguments expected, if needed
		"BOOKTABLE" : 1,
		"T2" : 1,
		"WEB" : 2,
		"XREF_PACK_NAMED" : 4,
		"DIVC" : 1,
		"SUBREF" : 2,
		"LINK2" : 2,
		"XREF" : 2,
		"CXREF" : 2,
		"SHORTXREF" : 2,
		"SHORTXREF_PACK" : 3,
		"XREF_PACK" : 3,
		"MREF" : 1,

		"REG_ROW" : 1,
		"REG_TITLE" : 2,
		"S_LINK" : 1,
		"PI": 1,
		"SUB": 2,
		"SQRT" : 1,
		"SUPERSCRIPT": 1,
		"POWER": 2,
		"NAN": 1,
		"PLUSMN": 1,
		"SVH" : 2,
		"SV": 2,
	];
}

string formatDocumentationComment(string comment, Decl decl) {
	// remove that annoying ddocism to suppress its auto-highlight anti-feature
	// FIXME
	/*
	auto psymbols = fullyQualifiedName[$-1].split(".");
	// also trim off our .# for overload
	import std.uni :isAlpha;
	auto psymbol = (psymbols.length && psymbols[$-1].length) ?
		((psymbols[$-1][0].isAlpha || psymbols[$-1][0] == '_') ? psymbols[$-1] : psymbols[$-2])
		:
		null;
	if(psymbol.length)
		comment = comment.replace("_" ~ psymbol, psymbol);
	*/

	auto data = formatDocumentationComment2(comment, decl).toString();

        return data;
}


// This is kinda deliberately not recursive right now. I might change that later but I want to keep it
// simple to get decent results while keeping the door open to dropping ddoc macros.
Element expandDdocMacros(string txt, Decl decl) {
	auto e = expandDdocMacros2(txt, decl);

	foreach(cmd; e.querySelectorAll("magic-command")) {
		auto subject = cmd.parentNode;
		if(subject is null)
			continue;
		if(subject.tagName == "caption")
			subject = subject.parentNode;
		if(subject is null)
			continue;
		if(cmd.className.length) {
			subject.addClass(cmd.className);
		}
		if(cmd.id.length)
			subject.id = cmd.id;
		cmd.removeFromTree();
	}

	return e;
}

Element expandDdocMacros2(string txt, Decl decl) {
	auto macros = ddocMacros;
	auto numberOfArguments = ddocMacroInfo;

	auto idx = 0;
	if(txt[idx] == '$') {
		auto info = macroInformation(txt[idx .. $]);
		if(info.linesSpanned == 0)
			assert(0);

		if(idx + 2 > txt.length)
			assert(0);
		if(idx + info.macroNameEndingOffset > txt.length)
			assert(0, txt[idx .. $]);
		if(info.macroNameEndingOffset < 2)
			assert(0, txt[idx..$]);

		auto name = txt[idx + 2 .. idx + info.macroNameEndingOffset];

		auto dzeroAdjustment = (info.textBeginningOffset == info.terminatingOffset) ? 0 : 1;
		auto stuff = txt[idx + info.textBeginningOffset .. idx + info.terminatingOffset - dzeroAdjustment];
		auto stuffNonStripped = txt[idx + info.macroNameEndingOffset .. idx + info.terminatingOffset - dzeroAdjustment];
		string replacement;

		if(name == "RAW_HTML") {
			// magic: user-defined html
			auto holder = Element.make("div", "", "user-raw-html");
			holder.innerHTML = stuff;
			return holder;
		}

		if(name == "ID")
			return Element.make("magic-command").setAttribute("id", stuff);
		if(name == "CLASS")
			return Element.make("magic-command").setAttribute("class", stuff);

		if(name == "SMALL_TABLE") {
			return translateSmallTable(stuff, decl);
		}
		if(name == "TABLE_ROWS") {
			return translateListTable(stuff, decl);
		}
		if(name == "LIST") {
			return translateList(stuff, decl, "ul");
		}
		if(name == "NUMBERED_LIST") {
			return translateList(stuff, decl, "ol");
		}

		if(name == "MATH") {
			import adrdox.latex;
			auto got = mathToImgHtml(stuff);
			if(got is null)
				return Element.make("span", stuff, "user-math-render-failed");
			return got;
		}

		if(name == "ADRDOX_SAMPLE") {
			// show the original source as code
			// then render it for display side-by-side
			auto holder = Element.make("div");
			holder.addClass("adrdox-sample");

			auto h = holder.addChild("div");

			h.addChild("pre", outdent(stuffNonStripped));
			h.addChild("div", formatDocumentationComment2(stuff, decl));

			return holder;
		}

		if(name == "D") {
			// this is magic: syntax highlight it
			auto holder = Element.make("tt");
			holder.className = "D highlighted";
			try {
				holder.innerHTML = highlight(stuff);
			} catch(Throwable t) {
				holder.innerText = stuff;
			}
			return holder;
		}

		if(name == "MODULE_NAME") {
			return new TextNode(decl.parentModule.fullyQualifiedName);
		}
		if(name == "FULLY_QUALIFIED_NAME") {
			return new TextNode(decl.fullyQualifiedName);
		}
		if(name == "REF" || name == "MREF" || name == "LREF") {
			// this is magic: do commas to dots then link it
			auto cool = replace(stuff, ",", ".");
			return getReferenceLink(cool, decl);
		}


		if(auto replacementRaw = name in macros) {
			if(auto nargsPtr = name in numberOfArguments) {
				auto nargs = *nargsPtr;
				replacement = *replacementRaw;

				foreach(i; 1 .. nargs + 1) {
					int blargh = -1;

					int parens;
					foreach(cidx, ch; stuff) {
						if(ch == '(')
							parens++;
						if(ch == ')')
							parens--;
						if(parens == 0 && ch == ',') {
							blargh = cast(int) cidx;
							break;
						}
					}
					if(blargh == -1)
						blargh = cast(int) stuff.length;
						//break; // insufficient args
					//blargh = stuff.length - 1; // trims off the closing paren

					auto magic = stuff[0 .. blargh].strip;
					if(blargh < stuff.length)
						stuff = stuff[blargh + 1 .. $];
					else
						stuff = stuff[$..$];
					// FIXME: this should probably not be full replace each time.
					//if(magic.length)
					magic = formatDocumentationComment2(magic, decl, null).innerHTML;

					if(name == "T2" && i == 1)
						replacement = replace(replacement, "$(LREF $1)", getReferenceLink(magic, decl).toString);
					else
						replacement = replace(replacement, "$" ~ cast(char)(i + '0'), magic);
				}

				auto awesome = stuff.strip;
				awesome = formatDocumentationComment2(awesome, decl, null).innerHTML;
				replacement = replace(replacement, "$+", awesome);
			} else {
				// if there is any text, we slice off the ), otherwise, keep the empty string
				auto awesome = txt[idx + info.textBeginningOffset .. idx + info.terminatingOffset - dzeroAdjustment];

				if(name == "CONSOLE") {
					awesome = outdent(txt[idx + info.macroNameEndingOffset .. idx + info.terminatingOffset - dzeroAdjustment]).strip;
				}


				awesome = formatDocumentationComment2(awesome, decl, null).innerHTML;
				replacement = replace(*replacementRaw, "$0", awesome);
			}

			Element element;
			if(replacement != "<" && replacement.strip.startsWith("<")) {
				element = Element.make("placeholder");

				element.innerHTML = replacement;
				element = element.childNodes[0];
				element.parentNode = null;

				foreach(k, v; element.attributes)
					element.attrs[k] = v.replace("$(FULLY_QUALIFIED_NAME)", decl.fullyQualifiedName).replace("$(MODULE_NAME)", decl.parentModule.fullyQualifiedName);
			} else {
				element = new TextNode(replacement);
			}

			return element;
		} else {
			idx = idx + cast(int) info.terminatingOffset;
			auto textContent = txt[0 .. info.terminatingOffset];
			return new TextNode(textContent);
		}
	} else assert(0);


	return null;
}

struct MacroInformation {
	size_t macroNameEndingOffset; // starting is always 2 if it is actually a macro (check linesSpanned > 0)
	size_t textBeginningOffset;
	size_t terminatingOffset;
	int linesSpanned;
}

// Scans the current macro
MacroInformation macroInformation(in char[] str) {
	assert(str[0] == '$');

	MacroInformation info;
	info.terminatingOffset = str.length;

	if (str.length < 2 || str[1] != '(')
		return info;

	bool readingMacroName = true;
	bool readingLeadingWhitespace;
	int parensCount = 0;
	foreach (idx, char ch; str)
	{
		if (readingMacroName && (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n'))
		{
			readingMacroName = false;
			readingLeadingWhitespace = true;
			info.macroNameEndingOffset = idx;
		}

		if (readingLeadingWhitespace && !(ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n'))
		{
			readingLeadingWhitespace = false;
			// This is looking past the macro name
			// so the offset of $(FOO bar) ought to be
			// the index of "bar"
			info.textBeginningOffset = idx;
		}

		if (ch == '\n')
			info.linesSpanned++;
		if (ch == '(')
			parensCount++;
		if (ch == ')')
		{
			parensCount--;
			if (parensCount == 0)
			{
				if(readingMacroName)
					info.macroNameEndingOffset = idx;
				info.linesSpanned++; // counts the first line it is on
				info.terminatingOffset = idx + 1;
				if (info.textBeginningOffset == 0)
					info.textBeginningOffset = info.terminatingOffset;
				break;
			}
		}
	}

	if(parensCount)
		info.linesSpanned = 0; // unterminated macro, tell upstream it is plain text

	return info;
}



string outdent(string s) {
	static import std.string;
	try {
		return join(std.string.outdent(splitLines(s)), "\n");
	} catch(Exception) {
		return s;
	}
}


//      Original code:
//          Copyright Brian Schott (Hackerpilot) 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)
// Adam modified

// http://ethanschoonover.com/solarized
string highlight(string sourceCode)
{
    import std.array;
    import dparse.lexer;
    string ret;

    StringCache cache = StringCache(StringCache.defaultBucketCount);
    LexerConfig config;
    config.stringBehavior = StringBehavior.source;
    auto tokens = byToken(cast(ubyte[]) sourceCode, config, &cache);


    void writeSpan(string cssClass, string value)
    {
        ret ~= `<span class="` ~ cssClass ~ `">` ~ value.replace("&", "&amp;").replace("<", "&lt;") ~ `</span>`;
    }


	while (!tokens.empty)
	{
		auto t = tokens.front;
		tokens.popFront();
		if (isBasicType(t.type))
			writeSpan("type", str(t.type));
		else if(t.text == "string") // string is a de-facto basic type, though it is technically just a user-defined identifier
			writeSpan("type", t.text);
		else if (isKeyword(t.type))
			writeSpan("kwrd", str(t.type));
		else if (t.type == tok!"comment")
			writeSpan("com", t.text);
		else if (isStringLiteral(t.type) || t.type == tok!"characterLiteral")
			writeSpan("str", t.text);
		else if (isNumberLiteral(t.type))
			writeSpan("num", t.text);
		else if (isOperator(t.type))
			writeSpan("op", str(t.type));
		else if (t.type == tok!"specialTokenSequence" || t.type == tok!"scriptLine")
			writeSpan("cons", t.text);
		else
		{
			ret ~= t.text.replace("<", "&lt;");
		}

	}
	return ret;
}




import dparse.formatter;

class MyFormatter(Sink) : Formatter!Sink {
	Decl context;
	this(Sink sink, Decl context = null, bool useTabs = true, IndentStyle style = IndentStyle.otbs, uint indentWidth = 4)
	{
		this.context = context;
		super(sink, useTabs, style, indentWidth);
	}

	void putTag(in char[] s) {
		static if(!__traits(compiles, sink.putTag("")))
			sink.put(s);
		else
			sink.putTag(s);
	}

	override void put(string s1) {
		auto s = cast(const(char)[]) s1;
		static if(!__traits(compiles, sink.putTag("")))
			sink.put(s.htmlEncode);
		else
			sink.put(s);
	}

	override void format(const TemplateParameterList templateParameterList)
	{
		foreach(i, param; templateParameterList.items)
		{
			putTag("<div class=\"template-parameter-item parameter-item\">");
			put("\t");
			format(param);
			putTag("</div>");
		}
	}

	override void format(const InStatement inStatement) {
		putTag("<a href=\"http://dpldocs.info/in-contract\" class=\"lang-feature\">");
		put("in");
		putTag("</a>");
		//put(" ");
		format(inStatement.blockStatement);
	}

	override void format(const OutStatement outStatement) {
		putTag("<a href=\"http://dpldocs.info/out-contract\" class=\"lang-feature\">");
		put("out");
		putTag("</a>");
		if (outStatement.parameter != tok!"")
		{
		    put(" (");
		    format(outStatement.parameter);
		    put(")");
		}

		//put(" ");
		format(outStatement.blockStatement);
	}

	override void format(const AssertExpression assertExpression)
	{
		debug(verbose) writeln("AssertExpression");

		/**
		  AssignExpression assertion;
		  AssignExpression message;
		 **/

		with(assertExpression)
		{
			putTag("<a href=\"http://dpldocs.info/assertion\" class=\"lang-feature\">");
			put("assert");
			putTag("</a> (");
			format(assertion);
			if (message)
			{
				put(", ");
				format(message);
			}
			put(")");
		}
	}


	override void format(const TemplateAliasParameter templateAliasParameter)
	{
		debug(verbose) writeln("TemplateAliasParameter");

		/**
		  Type type;
		  Token identifier;
		  Type colonType;
		  AssignExpression colonExpression;
		  Type assignType;
		  AssignExpression assignExpression;
		 **/

		with(templateAliasParameter)
		{
			putTag("<a href=\"http://dpldocs.info/template-alias-parameter\" class=\"lang-feature\">");
			put("alias");
			putTag("</a>");
			put(" ");
			if (type)
			{
				format(type);
				space();
			}
			format(identifier);
			if (colonType)
			{
				put(" : ");
				format(colonType);
			}
			else if (colonExpression)
			{
				put(" : ");
				format(colonExpression);
			}
			if (assignType)
			{
				put(" = ");
				format(assignType);
			}
			else if (assignExpression)
			{
				put(" = ");
				format(assignExpression);
			}
		}
	}


	override void format(const Constraint constraint)
	{
		debug(verbose) writeln("Constraint");

		if (constraint.expression)
		{
			put(" ");
			putTag("<a href=\"http://dpldocs.info/template-constraints\" class=\"lang-feature\">");
			put("if");
			putTag("</a>");
			put(" (");
			putTag("<div class=\"template-constraint-expression\">");
			format(constraint.expression);
			putTag("</div>");
			put(")");
		}
	}



	override void format(const PrimaryExpression primaryExpression)
	{
		debug(verbose) writeln("PrimaryExpression");

		/**
		  Token dot;
		  Token primary;
		  IdentifierOrTemplateInstance identifierOrTemplateInstance;
		  Token basicType;
		  TypeofExpression typeofExpression;
		  TypeidExpression typeidExpression;
		  ArrayLiteral arrayLiteral;
		  AssocArrayLiteral assocArrayLiteral;
		  Expression expression;
		  IsExpression isExpression;
		  LambdaExpression lambdaExpression;
		  FunctionLiteralExpression functionLiteralExpression;
		  TraitsExpression traitsExpression;
		  MixinExpression mixinExpression;
		  ImportExpression importExpression;
		  Vector vector;
		 **/

		with(primaryExpression)
		{
			if (dot != tok!"") put(".");
			if (basicType != tok!"") format(basicType);
			if (primary != tok!"")
			{
				if (basicType != tok!"") put("."); // i.e. : uint.max
				format(primary);
			}

			if (expression)
			{
				put("(");
				format(expression);
				put(")");
			}
			else if (identifierOrTemplateInstance)
			{
				format(identifierOrTemplateInstance);
			}
			else if (typeofExpression) format(typeofExpression);
			else if (typeidExpression) format(typeidExpression);
			else if (arrayLiteral) format(arrayLiteral);
			else if (assocArrayLiteral) format(assocArrayLiteral);
			else if (isExpression) format(isExpression);
			//else if (lambdaExpression) format(lambdaExpression);
			else if (functionLiteralExpression) format(functionLiteralExpression);
			else if (traitsExpression) format(traitsExpression);
			else if (mixinExpression) format(mixinExpression);
			else if (importExpression) format(importExpression);
			else if (vector) format(vector);
		}
	}

	override void format(const IsExpression isExpression) {
		//Formatter!Sink.format(this);

		with(isExpression) {
			putTag(`<a href="http://dpldocs.info/is-expression" class="lang-feature">is</a>(`);
			if (type) format(type);
			if (identifier != tok!"") {
				space();
				format(identifier);
			}

			if (equalsOrColon) {
				space();
				put(tokenRep(equalsOrColon));
				space();
			}

			if (typeSpecialization) format(typeSpecialization);
			if (templateParameterList) {
				put(", ");
				format(templateParameterList);
			}
			put(")");
		}
	}

	override void format(const TypeofExpression typeofExpr) {
		debug(verbose) writeln("TypeofExpression");

		/**
		Expression expression;
		Token return_;
		**/

		putTag("<a href=\"http://dpldocs.info/typeof-expression\" class=\"lang-feature\">typeof</a>(");
		typeofExpr.expression ? format(typeofExpr.expression) : format(typeofExpr.return_);
		put(")");
	}


	override void format(const Parameter parameter)
	{
		debug(verbose) writeln("Parameter");

		/**
		  IdType[] parameterAttributes;
		  Type type;
		  Token name;
		  bool vararg;
		  AssignExpression default_;
		  TypeSuffix[] cstyle;
		 **/

		putTag("<div class=\"runtime-parameter-item parameter-item\">");

		putTag("<span class=\"parameter-type-holder\">");
		putTag("<span class=\"parameter-type\">");
		foreach (count, attribute; parameter.parameterAttributes)
		{
			if (count) space();
			putTag("<span class=\"storage-class\">");
			put(tokenRep(attribute));
			putTag("</span>");
		}

		if (parameter.parameterAttributes.length > 0)
			space();

		if (parameter.type !is null)
			format(parameter.type);

		putTag(`</span>`);
		putTag(`</span>`);

		if (parameter.name.type != tok!"")
		{
			space();
			putTag(`<span class="parameter-name name" data-ident="`~parameter.name.text~`">`);
			putTag("<a href=\"#param-" ~ parameter.name.text ~ "\">");
			put(parameter.name.text);
			putTag("</a>");
			putTag("</span>");
		}

		foreach(suffix; parameter.cstyle)
			format(suffix);

		if (parameter.default_)
		{
			putTag(`<span class="parameter-default-value">`);
			putTag("&nbsp;=&nbsp;");
			format(parameter.default_);
			putTag(`</span>`);
		}

		if (parameter.vararg) {
			putTag("<a href=\"http://dpldocs.info/typed-variadic-function-arguments\" class=\"lang-feature\">");
			put("...");
			putTag("</a>");
		}

		putTag("</div>");
	}

	override void format(const Type type)
	{
		debug(verbose) writeln("Type(");

		/**
		  IdType[] typeConstructors;
		  TypeSuffix[] typeSuffixes;
		  Type2 type2;
		 **/

		foreach (count, constructor; type.typeConstructors)
		{
			if (count) space();
			put(tokenRep(constructor));
		}

		if (type.typeConstructors.length) space();

		//put(`<span class="name" data-ident="`~tokenRep(token)~`">`);
		format(type.type2);
		//put("</span>");

		foreach (suffix; type.typeSuffixes)
			format(suffix);

		debug(verbose) writeln(")");
	}

	override void format(const Type2 type2)
	{
		debug(verbose) writeln("Type2");

		/**
		  IdType builtinType;
		  Symbol symbol;
		  TypeofExpression typeofExpression;
		  IdentifierOrTemplateChain identifierOrTemplateChain;
		  IdType typeConstructor;
		  Type type;
		 **/

		if (type2.symbol !is null)
		{
			suppressMagic = true;
			scope(exit) suppressMagic = false;

			Decl link;
			if(context)
				link = context.lookupName(type2.symbol);
			if(link !is null) {
				putTag("<a href=\""~link.link~"\" title=\""~link.fullyQualifiedName~"\" class=\"xref\">");
				format(type2.symbol);
				putTag("</a>");
			} else if(toText(type2.symbol) == "string") {
				putTag("<span class=\"builtin-type\">");
				put("string");
				putTag("</span>");
			} else {
				format(type2.symbol);
			}
		}
		else if (type2.typeofExpression !is null)
		{
			format(type2.typeofExpression);
			if (type2.identifierOrTemplateChain)
			{
				put(".");
				format(type2.identifierOrTemplateChain);
			}
			return;
		}
		else if (type2.typeConstructor != tok!"")
		{
			putTag("<span class=\"type-constructor\">");
			put(tokenRep(type2.typeConstructor));
			putTag("</span>");
			put("(");
			format(type2.type);
			put(")");
		}
		else
		{
			putTag("<span class=\"builtin-type\">");
			put(tokenRep(type2.builtinType));
			putTag("</span>");
		}
	}


	override void format(const StorageClass storageClass)
	{
		debug(verbose) writeln("StorageClass");

		/**
		  AtAttribute atAttribute;
		  Deprecated deprecated_;
		  LinkageAttribute linkageAttribute;
		  Token token;
		 **/

		with(storageClass)
		{
			if (atAttribute) format(atAttribute);
			else if (deprecated_) format(deprecated_);
			else if (linkageAttribute) format(linkageAttribute);
			else {
				putTag("<span class=\"storage-class\">");
				format(token);
				putTag("</span>");
			}
		}
	}


	bool noTag;
	override void format(const Token token)
	{
		debug(verbose) writeln("Token ", tokenRep(token));
		if(!noTag && token == tok!"identifier") {
			putTag(`<span class="name" data-ident="`~tokenRep(token)~`">`);
		}
		auto rep = tokenRep(token);
		if(rep == "delegate" || rep == "function") {
			putTag(`<span class="lang-feature">`);
			put(rep);
			putTag(`</span>`);
		} else {
			put(rep);
		}
		if(!noTag && token == tok!"identifier") {
			putTag("</span>");
		}
	}

	bool suppressMagic = false;

	override void format(const IdentifierOrTemplateInstance identifierOrTemplateInstance)
	{
		debug(verbose) writeln("IdentifierOrTemplateInstance");

		if(!suppressMagic)
			putTag("<span class=\"some-ident\">");
		with(identifierOrTemplateInstance)
		{
			format(identifier);
			if (templateInstance)
				format(templateInstance);
		}
		if(!suppressMagic)
			putTag("</span>");
	}

	version(none)
	override void format(const Symbol symbol)
	{
		debug(verbose) writeln("Symbol");

		put("GOOD/");
		if (symbol.dot)
			put(".");
		format(symbol.identifierOrTemplateChain);
		put("/GOOD");
	}

	override void format(const Parameters parameters)
	{
		debug(verbose) writeln("Parameters");

		/**
		  Parameter[] parameters;
		  bool hasVarargs;
		 **/

		put("(");
		putTag("<div class=\"parameters-list\">");
		foreach (count, param; parameters.parameters)
		{
			if (count) put("\n");
			put("\t");
			format(param);
		}
		if (parameters.hasVarargs)
		{
			if (parameters.parameters.length)
				put("\n");
			putTag("<div class=\"runtime-parameter-item parameter-item\">");
			putTag("<a href=\"http://dpldocs.info/variadic-function-arguments\" class=\"lang-feature\">");
			putTag("...");
			putTag("</a>");
			putTag("</div>");
		}
		putTag("</div>");
		put(")");
	}

    	override void format(const IdentifierChain identifierChain)
	{
		//put("IDENT");
		foreach(count, ident; identifierChain.identifiers)
		{
		    if (count) put(".");
		    put(ident.text);
		}
		//put("/IDENT");
	}

	override void format(const AndAndExpression andAndExpression)
	{
		with(andAndExpression)
		{
			putTag("<div class=\"andand-left\">");
			format(left);
			if (right)
			{
				putTag(" &amp;&amp;</div><div class=\"andand-right\">");
				format(right);
			}
			putTag("</div>");
		}
	}

	override void format(const OrOrExpression orOrExpression)
	{
		with(orOrExpression)
		{
			putTag("<div class=\"oror-left\">");
			format(left);
			if (right)
			{
				putTag(" ||</div><div class=\"oror-right\">");
				format(right);
			}
			putTag("</div>");
		}
	}

	alias format = Formatter!Sink.format;
}


/*
	The small table looks like this:


	Caption
	Header | Row
	Data | Row
	Data | Row
*/
Element translateSmallTable(string text, Decl decl) {
	auto holder = Element.make("table");
	holder.addClass("small-table");

	void skipWhitespace() {
		while(text.length && (text[0] == ' ' || text[0] == '\t'))
			text = text[1 .. $];
	}

	string[] extractLine() {
		string[] cells;

		skipWhitespace();
		size_t i;

		while(i < text.length) {
			static string lastText;
			if(text[i .. $] is lastText)
				assert(0, lastText);

			lastText = text[i .. $];
			switch(text[i]) {
				case '|':
					cells ~= text[0 .. i].strip;
					text = text[i + 1 .. $];
					i = 0;
				break;
				case '`':
					i++;
					while(i < text.length && text[i] != '`')
						i++;
					if(i < text.length)
						i++; // skip closing `
				break;
				case '[':
				case '(':
				case '{':
					i++; // FIXME? skip these?
				break;
				case '$':
					auto info = macroInformation(text[i .. $]);
					i += info.terminatingOffset + 1;
				break;
				case '\n':
					cells ~= text[0 .. i].strip;
					text = text[i + 1 .. $];
					return cells;
				break;
				default:
					i++;
			}
		}

		return cells;
	}

	bool isDecorative(string[] row) {
		foreach(s; row)
		foreach(char c; s)
			if(c != '+' && c != '-' && c != '|' && c != '=')
				return false;
		return true;
	}

	Element tbody;
	bool first = true;
	bool twodTable;
	bool firstLine = true;
	string[] headerRow;
	while(text.length) {
		auto row = extractLine();

		if(row.length == 0)
			continue; // should never happen...

		if(row.length == 1 && row[0].length == 0)
			continue; // blank line

		if(isDecorative(row))
			continue; // ascii art is allowed, but ignored

		if(firstLine && row.length == 1 && row[0].length) {
			firstLine = false;
			holder.addChild("caption", row[0]);
			continue;
		}

		firstLine = false;

		// empty first and last rows are just surrounding pipes and can be ignored
		if(row[0].length == 0)
			row = row[1 .. $];
		if(row[$-1].length == 0)
			row = row[0 .. $-1];

		if(first) {
			auto thead = holder.addChild("thead");
			auto tr = thead.addChild("tr");

			headerRow = row;

			if(row[0].length == 0)
				twodTable = true;

			foreach(cell; row)
				tr.addChild("th", formatDocumentationComment2(cell, decl, null));
			first = false;
		} else {
			if(tbody is null)
				tbody = holder.addChild("tbody");
			auto tr = tbody.addChild("tr");

			while(row.length < headerRow.length)
				row ~= "";

			foreach(i, cell; row)
				tr.addChild((twodTable && i == 0) ? "th" : "td", formatDocumentationComment2(cell, decl, null));

		}
	}

	// FIXME: format the cells

	if(twodTable)
		holder.addClass("two-axes");


	return holder;
}

Element translateListTable(string text, Decl decl) {
	auto holder = Element.make("table");
	holder.addClass("user-table");

	DocCommentTerminationCondition termination;
	termination.terminationStrings = ["*", "-", "+"];
	termination.mustBeAtStartOfLine = true;

	string nextTag;

	Element row;

	do {
		auto fmt = formatDocumentationComment2(text, decl, null, &termination);
		if(fmt.toString.strip.length) {
			if(row is null)
				holder.addChild("caption", fmt);
			else
				row.addChild(nextTag, fmt);
		}
		text = termination.remaining;
		if(termination.terminatedOn == "*")
			row = holder.addChild("tr");
		else if(termination.terminatedOn == "+")
			nextTag = "th";
		else if(termination.terminatedOn == "-")
			nextTag = "td";
		else {}
	} while(text.length);

	return holder;
}

Element translateList(string text, Decl decl, string tagName) {
	auto holder = Element.make(tagName);
	holder.addClass("user-list");

	DocCommentTerminationCondition termination;
	termination.terminationStrings = ["*"];
	termination.mustBeAtStartOfLine = true;

	auto opening = formatDocumentationComment2(text, decl, null, &termination);
	text = termination.remaining;

	while(text.length) {
		auto fmt = formatDocumentationComment2(text, decl, null, &termination);
		holder.addChild("li", fmt);
		text = termination.remaining;
	}

	return holder;
}

Html syntaxHighlightJavascript(string jsCode) {
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
			// escape html
			case '<':
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
			default:
				if(isJsIdentifierChar(jsCode[0])) {
					size_t i;
					while(i < jsCode.length && isJsIdentifierChar(jsCode[i]))
						i++;
					auto ident = jsCode[0 .. i];
					jsCode = jsCode[i .. $];

					if(["function", "for", "in", "while", "new", "if", "else", "switch", "return", "break", "do", "delete", "this", "super"].canFind(ident))
						highlighted ~= "<span class=\"highlighted-keyword\">" ~ ident ~ "</span>";
					else if(["var", "const", "let", "int", "char", "class", "struct", "float", "double"].canFind(ident))
						highlighted ~= "<span class=\"highlighted-type\">" ~ ident ~ "</span>";
					else
						highlighted ~= "<span>" ~ ident ~ "</span>";

				} else {
					highlighted ~= jsCode[0];
					jsCode = jsCode[1 .. $];
				}
		}
	}

	return Html(highlighted);
}
