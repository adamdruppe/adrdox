// <details> html tag
// FIXME: KEY_VALUE like params
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
		if(s.length == 0)
			return;
		//foreach(ch; s) {
			//assert(s.length);
			//assert(s.indexOf("</body>") == -1);
		//}
		(*output) ~= s;
	}
}

enum TexMathOpt {
	LaTeX,
	KaTeX,
}

TexMathOpt parseTexMathOpt(string str) {
	switch (str) with(TexMathOpt) {
		case "latex": return LaTeX;
		case "katex": return KaTeX;
		default: throw new Exception("Unsupported 'tex-math' option");
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

bool hasParam(T)(const T dec, string name, Decl declObject, bool descend = true) {
	if(dec is null)
		return false;

	static if(__traits(compiles, dec.parameters)) {
		if(dec.parameters && dec.parameters.parameters)
		foreach(parameter; dec.parameters.parameters)
			if(parameter.name.text == name)
				return true;
	}
	static if(__traits(compiles, dec.templateParameters)) {
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
	}

	if(!descend)
		return false;

	// need to check parent template parameters in case they are
	// referenced in a child
	if(declObject.parent) {
		bool h;
		if(auto pdec = cast(TemplateDecl) declObject.parent)
			h = hasParam(pdec.astNode, name, pdec, false);
		else
			 {}
		if(h)
			return true;
	}

	// and eponymous ones
	static if(is(T == TemplateDeclaration)) {
		auto decl = cast(TemplateDecl) declObject;
		if(decl) {
			auto e = decl.eponymousMember();
			if(e) {
				if(auto a = cast(ConstructorDecl) e)
					return hasParam(a.astNode, name, a, false);
				if(auto a = cast(FunctionDecl) e)
					return hasParam(a.astNode, name, a, false);
				// FIXME: add more
			}
		}
	}

	return false;
}

struct LinkReferenceInfo {
	enum Type { none, text, link, image }
	Type type;
	bool isFootnote;
	string text; // or alt
	string link; // or src

	string toHtml(string fun, string rt) {
		if(rt is null)
			rt = fun;
		if(rt is fun && text !is null && type != Type.text)
			rt = text;

		string display = isFootnote ? ("[" ~ rt ~ "]") : rt;

		Element element;
		final switch(type) {
			case Type.none:
				return null;
			case Type.text:
			case Type.link:
				element = isFootnote ? Element.make("sup", "", "footnote-ref") : Element.make("span");
				if(type == Type.text) {
					element.addChild("abbr", display).setAttribute("title", text);
				} else {
					element.addChild("a", display, link);
				}
			break;
			case Type.image:
				element = Element.make("img", link, text);
			break;
		}

		return element.toString();
	}
}

__gshared string[string] globalLinkReferences;

void loadGlobalLinkReferences(string text) {
	foreach(line; text.splitLines) {
		line = line.strip;
		if(line.length == 0)
			continue;
		auto idx = line.indexOf("=");
		if(idx == -1)
			continue;
		auto name = line[0 .. idx].strip;
		auto value = line[idx + 1 .. $].strip;
		if(name.length == 0 || value.length == 0)
			continue;
		globalLinkReferences[name] = value;
	}
}

Element getSymbolGroupReference(string name, Decl decl, string rt) {
	auto pm = decl.isModule() ? decl : decl.parentModule;
	if(pm is null)
		return null;
	if(name in pm.parsedDocComment.symbolGroups) {
		return Element.make("a", rt.length ? rt : name, pm.fullyQualifiedName ~ ".html#group-" ~ name);
	}

	return null;
}

LinkReferenceInfo getLinkReference(string name, Decl decl) {
	bool numeric = (name.all!((ch) => ch >= '0' && ch <= '9'));

	bool onGlobal = false;
	auto refs = decl.parsedDocComment.linkReferences;

	try_again:

	if(name in refs) {
		auto txt = refs[name];

		assert(txt.length);

		LinkReferenceInfo lri;

		import std.uri;
		auto l = uriLength(txt);
		if(l != -1) {
			lri.link = txt;
			lri.type = LinkReferenceInfo.Type.link;
		} else if(txt[0] == '$') {
			// should be an image or plain text
			if(txt.length > 5 && txt[0 .. 6] == "$(IMG " && txt[$-1] == ')') {
				txt = txt[6 .. $-1];
				auto idx = txt.indexOf(",");
				if(idx == -1) {
					lri.link = txt.strip;
				} else {
					lri.text = txt[idx + 1 .. $].strip;
					lri.link = txt[0 .. idx].strip;
				}
				lri.type = LinkReferenceInfo.Type.image;
			} else goto plain_text;
		} else if(txt[0] == '[' && txt[$-1] == ']') {
			txt = txt[1 .. $-1];
			auto idx = txt.indexOf("|");
			if(idx == -1) {
				lri.link = txt;
			} else {
				lri.link = txt[0 .. idx].strip;
				lri.text = txt[idx + 1 .. $].strip;
			}

			lri.link = getReferenceLink(lri.link, decl).href;

			lri.type = LinkReferenceInfo.Type.link;
		} else {
			plain_text:
			lri.type = LinkReferenceInfo.Type.text;
			lri.link = null;
			lri.text = txt;
		}

		lri.isFootnote = numeric;
		return lri;
	} else if(!onGlobal && !numeric) {
		if(decl.parent !is null)
			decl = decl.parent;
		else {
			onGlobal = true;
			refs = globalLinkReferences;
			// decl = null; // so I kinda want it to be null, but that breaks like everything so I can't.
		}
		goto try_again;
	}

	return LinkReferenceInfo.init;
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

	string[string] symbolGroups; // stored as "name" : "raw text"
	string[] symbolGroupsOrder;
	string group; // the group this belongs to, if any

	string[string] otherSections;

	string[string] linkReferences;

	string[string] userDefinedMacros;

	Decl decl;

	bool synopsisEndedOnDoubleBlank;

	void writeSynopsis(MyOutputRange output) {
		output.putTag("<div class=\"documentation-comment synopsis\">");
			output.putTag(formatDocumentationComment(synopsis, decl));
			if(details !is synopsis && details.strip.length && details.strip != "<div></div>")
				output.putTag(` <a id="more-link" href="#details">More...</a>`);
		output.putTag("</div>");
	}

	void writeDetails(T = FunctionDeclaration)(MyOutputRange output) {
		writeDetails!T(output, cast(T) null, null);
	}

	void writeDetails(T = FunctionDeclaration)(MyOutputRange output, const T functionDec = null, Decl.ProcessedUnittest[] utInfo = null) {
		auto f = new MyFormatter!(typeof(output))(output, decl);

		string[] params = this.params;


		static if(is(T == FunctionDeclaration) || is(T == Constructor)) {
		if(functionDec !is null) {
			auto dec = functionDec;
			if(dec.templateParameters && dec.templateParameters.templateParameterList)
			foreach(parameter; dec.templateParameters.templateParameterList.items) {
				if(auto name = getIdent(parameter.templateTypeParameter))
					if(name.length && parameter.comment.length) params ~= name ~ "=" ~ preprocessComment(parameter.comment, decl);
				if(auto name = getIdent(parameter.templateValueParameter))
					if(name.length && parameter.comment.length) params ~= name ~ "=" ~ preprocessComment(parameter.comment, decl);
				if(auto name = getIdent(parameter.templateAliasParameter))
					if(name.length && parameter.comment.length) params ~= name ~ "=" ~ preprocessComment(parameter.comment, decl);
				if(auto name = getIdent(parameter.templateTupleParameter))
					if(name.length && parameter.comment.length) params ~= name ~ "=" ~ preprocessComment(parameter.comment, decl);
				if(parameter.templateThisParameter)
				if(auto name = getIdent(parameter.templateThisParameter.templateTypeParameter))
					if(name.length && parameter.comment.length) params ~= name ~ "=" ~ preprocessComment(parameter.comment, decl);
			}
			foreach(p; functionDec.parameters.parameters) {
				auto name = p.name.text;
				if(name.length && p.comment.length)
					params ~= name ~ "=" ~ preprocessComment(p.comment, decl);
			}
		}
		}

		if(params.length) {
			int count = 0;
			foreach(param; params) {
				auto split = param.indexOf("=");
				auto paramName = param[0 .. split];

				if(!hasParam(functionDec, paramName, decl)) {
				//import std.stdio; writeln("no param " ~ paramName, " ", functionDec);
					continue;
				}
				count++;
			}

			if(count) {
				output.putTag("<h2 id=\"parameters\">Parameters</h2>");
				output.putTag("<dl class=\"parameter-descriptions\">");
				foreach(param; params) {
					auto split = param.indexOf("=");
					auto paramName = param[0 .. split];

					if(!hasParam(functionDec, paramName, decl))
						continue;

					output.putTag("<dt id=\"param-"~param[0 .. split]~"\">");
					output.putTag("<a href=\"#param-"~param[0 .. split]~"\" class=\"parameter-name\" data-ident=\"");
						output.put(param[0 .. split]);
					output.putTag("\">");
					output.put(param[0 .. split]);
					output.putTag("</a>");

					static if(is(T == FunctionDeclaration) || is(T == Constructor))
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
							output.putTag(" <span class=\"parameter-type\">");
								f.format(paramAst.type);
							output.putTag("</span>");
						}


						if(paramAst && paramAst.atAttributes.length) {
							output.putTag("<div class=\"parameter-attributes\">");
							output.put("Attributes:");
							foreach (attribute; paramAst.atAttributes) {
								output.putTag("<div class=\"parameter-attribute\">");
								f.format(attribute);
								output.putTag("</div>");
							}

							output.putTag("</div>");
						}


					}

					output.putTag("</dt>");
					output.putTag("<dd>");

					output.putTag("<div class=\"documentation-comment\">");
					output.putTag(formatDocumentationComment(param[split + 1 .. $], decl));
					output.putTag("</div></dd>");
				}
				output.putTag("</dl>");
			}
		}

		if(returns !is null) {
			output.putTag("<h2 id=\"returns\">Return Value</h2>");
			output.putTag("<div>");
			static if(is(T == FunctionDeclaration))
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
			output.putTag("<div class=\"documentation-comment returns-description\">");
			output.putTag(formatDocumentationComment(returns, decl));
			output.putTag("</div>");
			output.putTag("</div>");
		}

		if(details.strip.length && details.strip != "<div></div>") {
			output.putTag("<h2 id=\"details\">Detailed Description</h2>");
			output.putTag("<div class=\"documentation-comment detailed-description\">");
				output.putTag(formatDocumentationComment(details, decl));
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
				output.putTag(formatDocumentationComment(bugs, decl));
			output.putTag("</div>");
		}

		bool hasUt;
		foreach(ut; utInfo) if(ut.embedded == false){hasUt = true; break;}

		if(examples.length || hasUt) {
			output.putTag("<h2 id=\"examples\"><a href=\"#examples\" class=\"header-anchor\">Examples</a></h2>");
			output.putTag("<div class=\"documentation-comment\">");
			output.putTag(formatDocumentationComment(examples, decl));
			output.putTag("</div>");

			foreach(example; utInfo) {
				if(example.embedded) continue;
				output.putTag(formatUnittestDocTuple(example, decl).toString());
			}
		}

		if(group)
			see_alsos ~= "\n\n[" ~ group ~ "]";

		if(see_alsos.length) {
			output.putTag("<h2 id=\"see-also\">See Also</h2>");
			output.putTag("<div class=\"documentation-comment see-also-section\">");
			output.putTag(formatDocumentationComment(see_alsos, decl));
			output.putTag("</div>");
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

Element formatUnittestDocTuple(Decl.ProcessedUnittest example, Decl decl) {
	auto holder = Element.make("div").addClass("unittest-example-holder");

	holder.addChild(formatDocumentationComment2(preprocessComment(example.comment, decl), decl).addClass("documentation-comment"));
	auto pre = holder.addChild("pre").addClass("d_code highlighted");

	// trim off leading/trailing newlines since they just clutter output
	auto codeToWrite = example.code;
	while(codeToWrite.length && (codeToWrite[0] == '\n' || codeToWrite[0] == '\r'))
		codeToWrite = codeToWrite[1 .. $];
	while(codeToWrite.length && (codeToWrite[$-1] == '\n' || codeToWrite[$-1] == '\r'))
		codeToWrite = codeToWrite[0 .. $ - 1];

	pre.innerHTML = highlight(outdent(codeToWrite));

	return holder;
}

string preprocessComment(string comment, Decl decl) {
	if(comment.length < 3)
		return comment;

	comment = comment.replace("\r\n", "\n");

	comment = comment[1 .. $]; // trim off the /

	auto commentType = comment[0];

	while(comment.length && comment[0] == commentType)
		comment = comment[1 .. $]; // trim off other opening spam

	string closingSpam;
	if(commentType == '*' || commentType == '+') {
		comment = comment[0 .. $-1]; // trim off the closing /
		bool closingSpamFound;
		auto tidx = 0;
		while(comment.length && comment[$-1 - tidx] == commentType) {
			//comment = comment[0 .. $-1]; // trim off other closing spam
			tidx++;
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


			// new algorithm in response to github issue # 36

			auto li = lastIndexOf(comment, "\n");
			if(li != -1) {
				// the closing line must be only whitespace and the marker to consider this
				size_t spot = size_t.max;
				foreach(idx, ch; comment[li + 1 .. $]) {
					if(!(ch == ' ' || ch == '\t' || ch == commentType)) {
						spot = size_t.max;
						// "foo +/" on the end
						// need to cut off the + from the end
						// since the final / was already cut
						comment = comment[0 .. $-1];
						break;
					} else {
						if(spot == size_t.max && ch == commentType)
							spot = idx + 1;
					}
				}

				if(spot != size_t.max) {
					closingSpam = comment[li + 1 .. li + 1 + spot];
					comment = comment[0 .. li];
				}
			} else {
				// single liner, strip off the closing spam
				// need to cut off the + from the end
				// since the final / was already cut
				comment = comment[0 .. $-1];

			}

			// old algorithm
			/+
			while(comment.length && (comment[$-1] == '\t' || comment[$-1] == ' ')) {
				closingSpam = comment[$-1] ~ closingSpam;
				comment = comment[0 .. $-1]; // trim off other closing spam
			}
			+/

			if(closingSpam.length == 0)
				closingSpam = " "; // some things use the " *" leader, but still end with "*/" on a line of its own
		}
	}


	string poop;
	if(commentType == '/')
		poop = "///";
	else
		poop = closingSpam;//closingSpam ~ commentType ~ " ";

	string newComment;
	foreach(line; comment.splitter("\n")) {
		// check for "  * some text"
		if(line.length >= poop.length && line.startsWith(poop)) {
			if(line.length > poop.length && line[poop.length] == ' ')
				newComment ~= line[poop.length + 1 .. $];
			else if(line.length > poop.length && line[poop.length] == '/' && poop != "/")
				newComment ~= line;
			else
				newComment ~= line[poop.length .. $];
		}
		// check for an empty line with just "  *"
		else if(line.length == poop.length-1 && line[0..poop.length-1] == poop[0..$-1])
			{} // this space is intentionally left blank; it is an empty line
		else if(line.length > 1 && commentType != '/' && line[0] == commentType && line[1] == ' ')
			newComment ~= line[1 .. $]; // cut off stupid leading * with no space before too
		else
			newComment ~= line;
		newComment ~= "\n";
	}

	comment = newComment;
	return specialPreprocess(comment, decl);
}

DocComment parseDocumentationComment(string comment, Decl decl) {
	DocComment c;

	if(generatingSource) {
		if(decl.lineNumber)
			c.otherSections["source"] ~= "$(LINK2 source/"~decl.parentModule.name~".d.html#L"~to!string(decl.lineNumber)~", See Implementation)$(BR)";
		else if(!decl.fakeDecl)
			c.otherSections["source"] ~= "$(LINK2 source/"~decl.parentModule.name~".d.html, See Source File)$(BR)";
	}
	// FIXME: add links to ddoc and ddox iff std.* or core.*

	c.decl = decl;

	comment = preprocessComment(comment, decl);

	void parseSections(string comment) {
		string remaining;
		string section;
		bool inSynopsis = true;
		bool justSawBlank = false;
		bool inCode = false;
		string inCodeStyle;
		bool hasAnySynopsis = false;
		bool inDdocSummary = true;
		bool synopsisEndedOnDoubleBlank = false;

		string currentMacroName;

		// for symbol_groups
		string* currentValue;

		bool maybeGroupLine = true;


		auto lastLineHelper = comment.strip;
		auto lastLine = lastLineHelper.lastIndexOf("\n");
		if(lastLine != -1) {
			auto lastLineText = lastLineHelper[lastLine .. $].strip;
			if(lastLineText.startsWith("Group: ") || lastLineText.startsWith("group: ")) {
				c.group = lastLineText["Group: ".length .. $];
				maybeGroupLine = false;

				comment = lastLineHelper[0 .. lastLine].strip;
			}
		}

		foreach(line; comment.splitter("\n")) {

			if(maybeGroupLine) {
				maybeGroupLine = false;
				if(line.strip.startsWith("Group: ") || line.strip.startsWith("group: ")) {
					c.group = line.strip["Group: ".length .. $]; // cut off closing paren
					continue;
				}
			}

			auto maybe = line.strip.toLower;

			if(maybe.startsWith("---") || maybe.startsWith("```")) {
				justSawBlank = false;

				if(inCode && inCodeStyle == maybe[0 .. 3]) {
					inCode = false;
					inCodeStyle = null;
				} else if(inCode)
					goto ss; // just still inside code section
				else {
					inCodeStyle = maybe[0 .. 3];
					inDdocSummary = false;
					inCode = !inCode;
				}
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
			} else if(maybe.startsWith("parameters:")) {
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
			} else if(maybe.startsWith("details:")) {
				section = "details";
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
			} else if(maybe.startsWith("since:")) {
				section = "since";
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
			} else if(maybe.startsWith("standards:")) {
				line = line[line.indexOf(":")+1 .. $];
				inSynopsis = false;
				section = "standards";
			} else if(maybe.startsWith("deprecated:")) {
				inSynopsis = false;
				section = "deprecated";
			} else if(maybe.startsWith("date:")) {
				inSynopsis = false;
				section = "date";
			} else if(maybe.startsWith("bugs:")) {
				line = line[line.indexOf(":")+1 .. $];
				inSynopsis = false;
				section = "bugs";
			} else if(maybe.startsWith("macros:")) {
				inSynopsis = false;
				section = "macros";
				currentMacroName = null;
			} else if(maybe.startsWith("symbol_groups:")) {
				section = "symbol_groups";
				line = line[line.indexOf(":")+1 .. $];
				inSynopsis = false;
			} else if(maybe.startsWith("link_references:")) {
				inSynopsis = false;
				section = "link_references";
				line = line[line.indexOf(":")+1 .. $].strip;
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
				case "symbol_groups":
					// basically a copy/paste of Params but it is coincidental
					// they might not always share syntax.
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
									auto currentName = lol[0 .. space_at];

									c.symbolGroups[currentName] = lol[idx + 1 .. $] ~ "\n";
									c.symbolGroupsOrder ~= currentName;
									currentValue = currentName in c.symbolGroups;
									break ss;
								} else
									// we are expecting whitespace or = and hit
									// neither.. this can't be ident = desc!
									break;
							}
						}
					}

					if(currentValue !is null) {
						*currentValue ~= line ~ "\n";
					}
				break;
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
									currentMacroName = lol[0 .. space_at].strip;
									auto currentMacroBody = lol[idx + 1 .. $] ~ "\n";

									c.userDefinedMacros[currentMacroName] = currentMacroBody;
									break ss;
								} else
									// we are expecting whitespace or = and hit
									// neither.. this can't be ident = desc!
									break;
							}
						} else {
							if(currentMacroName.length)
								c.userDefinedMacros[currentMacroName] ~= lol;
						}
					}
				break;
				case "link_references":
					auto eql = line.indexOf("=");
					if(eql != -1) {
						string name = line[0 .. eql].strip;
						string value = line[eql + 1 .. $].strip;
						c.linkReferences[name] = value;
					} else if(line.strip.length) {
						section = null;
						goto case_default;
					}
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
				case "since":
				case "date":
					c.otherSections[section] ~= line ~ "\n";
				break;
				case "details":
					c.details ~= line ~ "\n";
				break;
				case "examples":
					c.examples ~= line ~ "\n";
				break;
				default:
				case_default:
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

		c.details ~= remaining;
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
	if(text.length && text[0] == '/')
		return true; // is schema-relative url link

	bool seenHash;

	import std.uni;
	foreach(idx, dchar ch; text) {
		if(!isIdentifierChar(idx, ch) && ch != '.') {
			if(!seenHash && ch == '#') {
				seenHash = true;
				continue;
			} else if(seenHash && ch == '-') {
				continue;
			}
			return false;
		}
	}

	// passed the ident test...
	if(text.length)
		return true;

	return false;

}

Element getReferenceLink(string text, Decl decl, string realText = null) {
	import std.uri;
	auto l = uriLength(text);
	string hash;

	string className;

	if(l != -1) { // a url
		text = text;
		if(realText is null)
			realText = text;
	} else if(text.length && text[0] == '#') {
		// an anchor. add the link so it works when this is copy/pasted on other pages too (such as in search results)
		hash = text;
		text = decl.link;

		if(realText is null) {
			realText = hash[1 .. $].replace("-", " ");
		}
	} else {
		if(realText is null)
			realText = text;

		auto hashIdx = text.indexOf("#");
		if(hashIdx != -1) {
			hash = text[hashIdx .. $];
			text = text[0 .. hashIdx];
		}

		auto found = decl.lookupName(text);

		className = "xref";

		if(found is null) {
			auto lastPieceIdx = text.lastIndexOf(".");
			if(lastPieceIdx != -1) {
				found = decl.lookupName(text[0 .. lastPieceIdx]);
				if(found && hash is null)
					hash = "#" ~ text[lastPieceIdx + 1 .. $];
			}
		}

		if(found !is null)
			text = found.link;
		else if(auto c = text in allClasses) {
			// classes may be thrown and as such can be referenced externally without import
			// doing this as kinda a hack.
			text = (*c).link;
		} else {
			text = text.handleCaseSensitivity ~ ".html";
		}
	}

	auto element = Element.make("a");
	element.className = className;
	element.href = getDirectoryForPackage(text) ~ text ~ hash;
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
	currentParagraph.reserve(2048);
	void putch(char c) {
		currentParagraph ~= c;
	}
	void put(in char[] c) {
		currentParagraph ~= c;
	}

	string currentTag = (tagName is null) ? null : "p";
	string currentClass = null;

	void commit() {
		auto cp = currentParagraph.strip;
		if(cp.length) {
			if(currentTag is null)
				div.appendHtml(cp);
			else {
				if(currentTag == "p") {
					// check for a markdown style header
					auto test = cp.strip;
					auto lines = test.splitLines();
					if(lines.length == 2) {
						auto hdr = lines[0].strip;
						auto equals = lines[1].strip;
						if(equals.length >= 4) {
							foreach(ch; equals)
								if(ch != '=')
									goto not_special;
						} else {
							goto not_special;
						}

						if(hdr.length == 0)
							goto not_special;

						// passed tests, I'll allow it:
						currentTag = "h3";
						currentClass = "user-header";
						cp = hdr;
					} else if(lines.length == 1) {
						int hashCount = 0;
						foreach(idx, ch; test) {
							if(ch == '#')
								hashCount++;
							else if(ch == ' ' && hashCount > 0) {
								// it was special!
								// there must be text after btw or else strip would have cut the space too
								currentTag = "h" ~ to!string(hashCount);
								currentClass = "user-header";
								cp = test[idx + 1 .. $];

								break;
							} else
								break; // not special
						}
					}
				}

				not_special:
				div.addChild(currentTag, Html(cp), currentClass);
			}
		}
		currentTag = "p";
		currentParagraph = null;
		currentParagraph.reserve(2048);
		currentClass = null;
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
					if(language == "javascript" || language == "c" || language == "c++" || language == "java" || language == "php" || language == "c#" || language == "d" || language == "adrscript" || language == "json")
						ele = div.addChild("pre", syntaxHighlightCFamily(code, language));
					else if(language == "css")
						ele = div.addChild("pre", syntaxHighlightCss(code));
					else if(language == "html" || language == "xml")
						ele = div.addChild("pre", syntaxHighlightHtml(code, language));
					else if(language == "python")
						ele = div.addChild("pre", syntaxHighlightPython(code));
					else if(language == "ruby")
						ele = div.addChild("pre", syntaxHighlightRuby(code));
					else if(language == "sdlang")
						ele = div.addChild("pre", syntaxHighlightSdlang(code));
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

					if(slice.length == 0) {
						// empty code block is `` - doubled backtick. Just
						// treat that as a literal (escaped) backtick.
						putch('`');
					} else {
						auto ele = Element.make("tt").addClass("inline-code");
						ele.innerText = slice;
						put(ele.toString());
					}
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
			case '!':
				// possible markdown-style image
				if(remaining.length > 1 && remaining[1] == '[') {
					auto inside = remaining[1 .. $];
					auto txt = extractBalanceOnSingleLine(inside);
					if(txt is null)
						goto ordinary;
					if(txt.length < inside.length && inside[txt.length] == '(') {
						// possible markdown image
						auto parens = extractBalanceOnSingleLine(inside[txt.length .. $]);
						if(parens.length) {
							auto a = Element.make("img");
							a.alt = txt[1 .. $-1];
							a.src = parens[1 .. $-1];
							put(a.toString());

							idx ++; // skip the !
							idx += parens.length;
							idx += txt.length;
							idx --; // so the ++ in the for loop brings us back to i
							break;
						}
					}
				}
				goto ordinary;
			break;
			case '[':
				// wiki-style reference iff [text] or [text|other text]
				// or possibly markdown style link: [text](url)
				// text MUST be either a valid D identifier chain, optionally with a section hash,
				// or a fully-encoded http url.
				// text may never include ']' or '|' or whitespace or ',' and must always start with '_' or alphabetic (like a D identifier or http url)
				// other text may include anything except the string ']'
				// it balances [] inside it.

				auto txt = extractBalanceOnSingleLine(remaining);
				if(txt is null)
					goto ordinary;
				if(txt.length < remaining.length && remaining[txt.length] == '(') {
					// possible markdown link
					auto parens = extractBalanceOnSingleLine(remaining[txt.length .. $]);
					if(parens.length) {
						auto a = Element.make("a", txt[1 .. $-1], parens[1 .. $-1]);
						put(a.toString());

						idx += parens.length;
						idx += txt.length;
						idx --; // so the ++ in the for loop brings us back to i
						break;
					}
				}

				auto fun = txt[1 .. $-1];
				string rt;
				auto idx2 = fun.indexOf("|");
				if(idx2 != -1) {
					rt = fun[idx2 + 1 .. $].strip;
					fun = fun[0 .. idx2].strip;
				}

				if(fun.all!((ch) => ch >= '0' && ch <= '9')) {
					// footnote reference
					auto lri = getLinkReference(fun, decl);
					if(lri.type == LinkReferenceInfo.Type.none)
						goto ordinary;
					put(lri.toHtml(fun, rt));
				} else if(!fun.isIdentifierOrUrl()) {
					goto ordinary;
				} else {
					auto lri = getLinkReference(fun, decl);
					if(lri.type == LinkReferenceInfo.Type.none) {
						if(auto l = getSymbolGroupReference(fun, decl, rt)) {
							put(l.toString());
						} else {
							put(getReferenceLink(fun, decl, rt).toString);
						}
					} else
						put(lri.toHtml(fun, rt));
				}

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

	/*
	if(div.firstChild !is null && div.firstChild.nodeType == NodeType.Text
	   && div.firstChild.nextSibling !is null && div.firstChild.nextSibling.tagName == "p")
	     div.firstChild.wrapIn(Element.make("p"));
	*/

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
	if(ident.length == 0)
		return false;

	// check this name
	if(ident == decl.name) {
		import std.stdio; writeln("stupid ddocism(1): ", ident);
		return true;
	}

	if(decl.isModule) {
		auto name = decl.name;
		auto idx = name.lastIndexOf(".");
		if(idx != -1) {
			name = name[idx + 1 .. $];
		}

		if(ident == name) {
			import std.stdio; writeln("stupid ddocism(2): ", ident);
			return true;
		}
	}

	// check the whole scope too, I think dmd does... maybe
	if(decl.parentModule && decl.parentModule.lookupName(ident) !is null) {
		import std.stdio; writeln("stupid ddocism(3): ", ident);
		return true;
	}

	if(decl.hasParam(ident)) {
		import std.stdio; writeln("stupid ddocism(4): ", ident);
		return true;
	}

	return false;
}

string extractBalanceOnSingleLine(string txt) {
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
		if(ch == '\n')
			return null;
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
    	scope(exit) stringCache.freeItAll();

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

immutable string[string] ddocMacros;
immutable int[string] ddocMacroInfo;
immutable int[string] ddocMacroBlocks;

shared static this() {
	ddocMacroBlocks = [
		"ADRDOX_SAMPLE" : 1,
		"LIST": 1,
		"NUMBERED_LIST": 1,
		"SMALL_TABLE" : 1,
		"TABLE_ROWS" : 1,
		"EMBED_UNITTEST": 1,
		"UNDOCUMENTED": 1,

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
		"TABLE" : 1,
		"TDNW" : 1,
		"LEADINGROWN" : 1,

		"UL" : 1,
		"OL" : 1,
		"LI" : 1,

		"P" : 1,
		"PRE" : 1,
		"BLOCKQUOTE" : 1,
		"CITE" : 1,
		"DL" : 1,
		"DT" : 1,
		"DD" : 1,
		"POST" : 1,
		"DIV" : 1,
		"SIDE_BY_SIDE" : 1,
		"COLUMN" : 1,

		"DIVC" : 1,

		// std.regex
		"REG_ROW": 1,
		"REG_TITLE": 1,
		"REG_TABLE": 1,
		"REG_START": 1,
		"SECTION": 1,

		// std.math
		"TABLE_SV" : 1,
		"TABLE_DOMRG": 2,
		"DOMAIN": 1,
		"RANGE": 1,
		"SVH": 1,
		"SV": 1,

		"UDA_USES" : 1,
		"UDA_STRING" : 1,
		"C_HEADER_DESCRIPTION": 1,
	];

	ddocMacros = [
		"FULLY_QUALIFIED_NAME" : "MAGIC", // decl.fullyQualifiedName,
		"MODULE_NAME" : "MAGIC", // decl.parentModule.fullyQualifiedName,
		"D" : "<tt class=\"D\">$0</tt>", // this is magical! D is actually handled in code.
		"REF" : `<a href="$0.html">$0</a>`, // this is magical! Handles ref in code

		"ALWAYS_DOCUMENT" : "",

		"UDA_USES" : "",
		"UDA_STRING" : "",

		"TIP" : "<div class=\"tip\">$0</div>",
		"NOTE" : "<div class=\"note\">$0</div>",
		"WARNING" : "<div class=\"warning\">$0</div>",
		"PITFALL" : "<div class=\"pitfall\">$0</div>",
		"SIDEBAR" : "<div class=\"sidebar\"><aside>$0</aside></div>",
		"CONSOLE" : "<pre class=\"console\">$0</pre>",

		// headers have meaning to the table of contents generator
		"H1" : "<h1 class=\"user-header\">$0</h1>",
		"H2" : "<h2 class=\"user-header\">$0</h2>",
		"H3" : "<h3 class=\"user-header\">$0</h3>",
		"H4" : "<h4 class=\"user-header\">$0</h4>",
		"H5" : "<h5 class=\"user-header\">$0</h5>",
		"H6" : "<h6 class=\"user-header\">$0</h6>",

		"BLOCKQUOTE" : "<blockquote>$0</blockquote>", // FIXME?
		"CITE" : "<cite>$0</cite>", // FIXME?

		"HR" : "<hr />",

		"DASH" : "&#45;",
		"NOTHING" : "", // used to escape magic syntax sometimes

		// DDoc just expects these.
		"AMP" : "&",
		"LT" : "<",
		"GT" : ">",
		"LPAREN" : "(",
		"RPAREN" : ")",
		"DOLLAR" : "$",
		"BACKTICK" : "`",
		"COMMA": ",",
		"COLON": ":",
		"ARGS" : "$0",

		// support for my docs' legacy components, will be removed before too long.
		"DDOC_ANCHOR" : "<a id=\"$0\" href=\"$(FULLY_QUALIFIED_NAME).html#$0\">$0</a>",

		"DDOC_COMMENT" : "",

		// this is support for the Phobos docs

		// useful parts
		"BOOKTABLE" : "<table class=\"phobos-booktable\"><caption>$1</caption>$+</table>",
		"T2" : "<tr><td>$(LREF $1)</td><td>$+</td></tr>",

		"BIGOH" : "<span class=\"big-o\"><i>O</i>($0)</span>",

		"TR" : "<tr>$0</tr>",
		"TH" : "<th>$0</th>",
		"TD" : "<td>$0</td>",
		"TABLE": "<table>$0</table>",
		"TDNW" : "<td style=\"white-space: nowrap;\">$0</td>",
		"LEADINGROWN":"<tr class=\"leading-row\"><th colspan=\"$1\">$2</th></tr>",
		"LEADINGROW":"<tr class=\"leading-row\"><th colspan=\"2\">$0</th></tr>",

		"UL" : "<ul>$0</ul>",
		"OL" : "<ol>$0</ol>",
		"LI" : "<li>$0</li>",

		"BR" : "<br />",
		"MDASH": "\&mdash;",
		"COMMA": ",",
		"SECTION3": "<h3>$0</h3>",
		"I" : "<i>$0</i>",
		"EM" : "<em>$0</em>",
		"STRONG" : "<strong>$0</strong>",
		"TT" : "<tt>$0</tt>",
		"B" : "<b>$0</b>",
		"STRIKE" : "<s>$0</s>",
		"P" : "<p>$0</p>",
		"PRE" : "<pre>$0</pre>",
		"DL" : "<dl>$0</dl>",
		"DT" : "<dt>$0</dt>",
		"DD" : "<dd>$0</dd>",
		"LINK2" : "<a href=\"$1\">$2</a>",
		"LINK" : `<a href="$0">$0</a>`,

		"DDLINK": "<a href=\"http://dlang.org/$1\">$3</a>",
		"DDSUBLINK": "<a href=\"http://dlang.org/$1#$2\">$3</a>",

		"IMG": "<img src=\"$1\" alt=\"$2\" />",

		"BLUE" : "<span style=\"color: blue;\">$0</span>",
		"RED" : "<span style=\"color: red;\">$0</span>",

		"SCRIPT" : "",

		"UNDOCUMENTED": "<span class=\"undocumented-note\">$0</span>",

		// Useless crap that should just be replaced
		"REF_SHORT" : `<a href="$2.$3.$1.html">$1</a>`,
		"SHORTREF" : `<a href="$2.$3.$1.html">$1</a>`,
		"SUBMODULE" : `<a href="$(FULLY_QUALIFIED_NAME).$2.html">$1</a>`,
		"SHORTXREF" : `<a href="std.$1.$2.html">$2</a>`,
		"SHORTXREF_PACK" : `<a href="std.$1.$2.$3.html">$3</a>`,
		"XREF" : `<a href="std.$1.$2.html">std.$1.$2</a>`,
		"CXREF" : `<a href="core.$1.$2.html">core.$1.$2</a>`,
		"XREF_PACK" : `<a href="std.$1.$2.$3.html">std.$1.$2.$3</a>`,
		"MYREF" : `<a href="$(FULLY_QUALIFIED_NAME).$0.html">$0</a>`,
		"LREF" : `<a class="symbol-reference" href="$(MODULE_NAME).$0.html">$0</a>`,
		// FIXME: OBJECTREF
		"LREF2" : "MAGIC",
		"MREF" : `MAGIC`,
		"WEB" : `<a href="http://$1">$2</a>`,
		"HTTP" : `<a href="http://$1">$2</a>`,
		"BUGZILLA": `<a href="https://issues.dlang.org/show_bug.cgi?id=$1">https://issues.dlang.org/show_bug.cgi?id=$1</a>`,
		"XREF_PACK_NAMED" : `<a href="std.$1.$2.$3.html">$4</a>`,

		"D_INLINECODE" : `<tt>$1</tt>`,
		"D_STRING" : `<tt>$1</tt>`,
		"D_CODE_STRING" : `<tt>$1</tt>`,
		"D_CODE" : `<pre>$0</pre>`,
		"HIGHLIGHT" : `<span class="specially-highlighted">$0</span>`,
		"HTTPS" : `<a href="https://$1">$2</a>`,

		"RES": `<i>result</i>`,
		"POST": `<div class="postcondition">$0</div>`,
		"COMMENT" : ``,

		"DIV" : `<div>$0</div>`,
		"SIDE_BY_SIDE" : `<table class="side-by-side"><tbody><tr>$0</tr></tbody></table>`,
		"COLUMN" : `<td>$0</td>`,
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
		"TABLE_DOMRG": `<table class="std_math domain-and-range">$1 $2</table>`,
		"DOMAIN": `<tr><th>Domain</th><td>$0</td></tr>`,
		"RANGE": `<tr><th>Range</th><td>$0</td></tr>`,

		"PI": "\u03c0",
		"INFIN": "\u221e",
		"SUB": "<span>$1<sub>$2</sub></span>",
		"SQRT" : "\u221a",
		"SUPERSCRIPT": "<sup>$1</sup>",
		"SUBSCRIPT": "<sub>$1</sub>",
		"POWER": "<span>$1<sup>$2</sup></span>",
		"NAN": "<span class=\"nan\">NaN</span>",
		"PLUSMN": "\u00b1",
		"GLOSSARY": `<a href="http://dlang.org/glosary.html#$0">$0</a>`,
		"PHOBOSSRC": `<a href="https://github.com/dlang/phobos/blob/master/$0">$0</a>`,
		"DRUNTIMESRC": `<a href="https://github.com/dlang/dmd/blob/master/druntime/src/$0">$0</a>`,
		"C_HEADER_DESCRIPTION": `<p>This module contains bindings to selected types and functions from the standard C header <a href="http://$1">&lt;$2&gt;</a>. Note that this is not automatically generated, and may omit some types/functions from the original C header.</p>`,
	];

	ddocMacroInfo = [ // number of arguments expected, if needed
		"EMBED_UNITTEST": 1,
		"UNDOCUMENTED": 1,
		"BOOKTABLE" : 1,
		"T2" : 1,
		"LEADINGROWN" : 2,
		"WEB" : 2,
		"HTTP" : 2,
		"BUGZILLA" : 1,
		"XREF_PACK_NAMED" : 4,
		"D_INLINECODE" : 1,
		"D_STRING" : 1,
		"D_CODE_STRING": 1,
		"D_CODE": 1,
		"HIGHLIGHT": 1,
		"HTTPS": 2,
		"DIVC" : 1,
		"LINK2" : 2,
		"DDLINK" : 3,
		"DDSUBLINK" : 3,
		"IMG" : 2,
		"XREF" : 2,
		"CXREF" : 2,
		"SHORTXREF" : 2,
		"SHORTREF": 3,
		"REF_SHORT": 3,
		"SUBMODULE" : 2,
		"SHORTXREF_PACK" : 3,
		"XREF_PACK" : 3,
		"MREF" : 1,
		"LREF2" : 2,
		"C_HEADER_DESCRIPTION": 2,

		"REG_ROW" : 1,
		"REG_TITLE" : 2,
		"S_LINK" : 1,
		"PI": 1,
		"SUB": 2,
		"SQRT" : 1,
		"SUPERSCRIPT": 1,
		"SUBSCRIPT": 1,
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

	translateMagicCommands(e);

	return e;
}

void translateMagicCommands(Element container, Element applyTo = null) {
	foreach(cmd; container.querySelectorAll("magic-command")) {
		Element subject;
		if(applyTo is null) {
			subject = cmd.parentNode;
			if(subject is null)
				continue;
			if(subject.tagName == "caption")
				subject = subject.parentNode;
			if(subject is null)
				continue;
		} else {
			subject = applyTo;
		}

		if(cmd.className.length) {
			subject.addClass(cmd.className);
		}
		if(cmd.id.length)
			subject.id = cmd.id;
		cmd.removeFromTree();
	}
}

Element expandDdocMacros2(string txt, Decl decl) {
	auto macros = ddocMacros;
	auto numberOfArguments = ddocMacroInfo;

	auto userDefinedMacros = decl.parsedDocComment.userDefinedMacros;

	string[string] availableMacros;
	int[string] availableNumberOfArguments;

	if(userDefinedMacros.length) {
		foreach(name, value; userDefinedMacros) {
			availableMacros[name] = value;
			int count;
			foreach(idx, ch; value) {
				if(ch == '$') {
					if(idx + 1 < value.length) {
						char n = value[idx + 1];
						if(n >= '0' && n <= '9') {
							if(n - '0' > count)
								count = n - '0';
						}
					}
				}
			}
			if(count)
				availableNumberOfArguments[name] = count;
		}

		foreach(name, value; macros)
			availableMacros[name] = value;
		foreach(name, n; numberOfArguments)
			availableNumberOfArguments[name] = n;
	} else {
		availableMacros = cast(string[string]) macros;
		availableNumberOfArguments = cast(int[string]) numberOfArguments;
	}

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

		if(name == "EMBED_UNITTEST") {
			// FIXME: use /// Documents: Foo.bar to move a test over to something else
			auto id = stuff.strip;
			foreach(ref ut; decl.getProcessedUnittests()) {
				if(ut.comment.canFind("$(ID " ~ id ~ ")")) {
					ut.embedded = true;
					return formatUnittestDocTuple(ut, decl);
				}
			}
		}

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
			import adrdox.jstex;

			switch (texMathOpt) with(TexMathOpt) {
				case LaTeX: {
					auto got = mathToImgHtml(stuff);
					if(got is null)
						return Element.make("span", stuff, "user-math-render-failed");
					return got;
				}
				case KaTeX: {
					return mathToKaTeXHtml(stuff);
				}
				default: break;
			}
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

		if(name == "D" || name == "D_PARAM" || name == "D_CODE") {
			// this is magic: syntax highlight it
			auto holder = Element.make(name == "D_CODE" ? "pre" : "tt");
			holder.className = "D highlighted";
			try {
				holder.innerHTML = linkUpHtml(highlight(stuff), decl);
			} catch(Throwable t) {
				holder.innerText = stuff;
			}
			return holder;
		}

		if(name == "UDA_STRING") {
			return new TextNode(decl.getStringUda(stuff));
		}

		if(name == "UDA_USES") {
			Element div = Element.make("dl");
			foreach(d; declsByUda(decl.name, decl.parentModule)) {
				if(!d.docsShouldBeOutputted)
					continue;
				auto dt = div.addChild("dt");
				dt.addChild("a", d.name, d.link);
				div.addChild("dd", Html(formatDocumentationComment(d.parsedDocComment.ddocSummary, d)));
			}
			return div;
		}

		if(name == "MODULE_NAME") {
			return new TextNode(decl.parentModule.fullyQualifiedName);
		}
		if(name == "FULLY_QUALIFIED_NAME") {
			return new TextNode(decl.fullyQualifiedName);
		}
		if(name == "SUBREF") {
			auto cool = stuff.split(",");
			if(cool.length == 2)
				return getReferenceLink(decl.fullyQualifiedName ~ "." ~ cool[0].strip ~ "." ~ cool[1].strip, decl, cool[1].strip);
		}
		if(name == "MREF_ALTTEXT") {
			auto parts = split(stuff, ",");
			string cool;
			foreach(indx, p; parts[1 .. $]) {
				if(indx) cool ~= ".";
				cool ~= p.strip;
			}

			return getReferenceLink(cool, decl, parts[0].strip);
		}
		if(name == "LREF2") {
			auto parts = split(stuff, ",");
			return getReferenceLink(parts[1].strip ~ "." ~ parts[0].strip, decl, parts[0].strip);
		}
		if(name == "REF_ALTTEXT") {
			auto parts = split(stuff, ",");
			string cool;
			foreach(indx, p; parts[2 .. $]) {
				if(indx) cool ~= ".";
				cool ~= p.strip;
			}
			cool ~= "." ~ parts[1].strip;

			return getReferenceLink(cool, decl, parts[0].strip);
		}

		if(name == "NBSP") {
			return new TextNode("\&nbsp;");
		}

		if(name == "REF" || name == "MREF" || name == "LREF" || name == "MYREF") {
			// this is magic: do commas to dots then link it
			string cool;
			if(name == "REF") {
				auto parts = split(stuff, ",");
				parts = parts[1 .. $] ~ parts[0];
				foreach(indx, p; parts) {
					if(indx)
						cool ~= ".";
					cool ~= p.strip;
				}
			} else
				cool = replace(stuff, ",", ".").replace(" ", "");
			return getReferenceLink(cool, decl);
		}


		if(auto replacementRaw = name in availableMacros) {
			if(auto nargsPtr = name in availableNumberOfArguments) {
				auto nargs = *nargsPtr;
				replacement = *replacementRaw;

				auto orig = txt[idx + info.textBeginningOffset .. idx + info.terminatingOffset - dzeroAdjustment];

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

				// FIXME: recursive replacement doesn't work...

				auto awesome = stuff.strip;
				if(replacement.indexOf("$+") != -1) {
					awesome = formatDocumentationComment2(awesome, decl, null).innerHTML;
					replacement = replace(replacement, "$+", awesome);
				}

				if(replacement.indexOf("$0") != -1) {
					awesome = formatDocumentationComment2(orig, decl, null).innerHTML;
					replacement = replace(*replacementRaw, "$0", awesome);
				}
			} else {
				// if there is any text, we slice off the ), otherwise, keep the empty string
				auto awesome = txt[idx + info.textBeginningOffset .. idx + info.terminatingOffset - dzeroAdjustment];

				if(name == "CONSOLE") {
					awesome = outdent(txt[idx + info.macroNameEndingOffset .. idx + info.terminatingOffset - dzeroAdjustment]).strip;
					awesome = awesome.replace("\n---", "\n$(NOTHING)---"); // disable ddoc embedded D code as it breaks for D exception messages
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

	if (str.length < 2 || (str[1] != '(' && str[1] != '{'))
		return info;

	auto open = str[1];
	auto close = str[1] == '(' ? ')' : '}';

	bool readingMacroName = true;
	bool readingLeadingWhitespace;
	int parensCount = 0;
	foreach (idx, char ch; str)
	{
		if (readingMacroName && (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == ','))
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

		// so i want :) and :( not to count
		// also prolly 1) and 2) etc.

		if (ch == '\n')
			info.linesSpanned++;
		if (ch == open)
			parensCount++;
		if (ch == close)
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
    scope(exit) cache.freeItAll();
    LexerConfig config;
    config.stringBehavior = StringBehavior.source;
    auto tokens = byToken(cast(ubyte[]) sourceCode, config, &cache);


    void writeSpan(string cssClass, string value, string dataIdent = "")
    {
        ret ~= `<span class="` ~ cssClass ~ `" `;
	if(dataIdent.length)
		ret ~= "data-ident=\""~dataIdent~"\"";
	ret ~= `>` ~ value.replace("&", "&amp;").replace("<", "&lt;") ~ `</span>`;
    }


	bool inImport;
	while (!tokens.empty)
	{
		auto t = tokens.front;
		tokens.popFront();

		// to fix up the import std.string looking silly bug
		if(!inImport && t.type == tok!"import")
			inImport = true;
		else if(inImport && t.type == tok!";")
			inImport = false;

		if (isBasicType(t.type))
			writeSpan("type", str(t.type));
		else if(!inImport && t.text == "string") // string is a de-facto basic type, though it is technically just a user-defined identifier
			writeSpan("type", t.text);
		else if (isKeyword(t.type))
			writeSpan("kwrd", str(t.type));
		else if (t.type == tok!"comment") {
			auto txt = t.text;
			if(txt == "/* adrdox_highlight{ */")
				ret ~= "<span class=\"specially-highlighted\">";
			else if(txt == "/* }adrdox_highlight */")
				ret ~= "</span>";
			else
				writeSpan("com", t.text);
		} else if (isStringLiteral(t.type) || t.type == tok!"characterLiteral") {
			auto txt = t.text;
			if(txt.startsWith("q{")) {
				ret ~= "<span class=\"token-string-literal\"><span class=\"str\">q{</span>";
				ret ~= highlight(txt[2 .. $ - 1]);
				ret ~= "<span class=\"str\">}</span></span>";
			} else {
				writeSpan("str", txt);
			}
		} else if (isNumberLiteral(t.type))
			writeSpan("num", t.text);
		else if (isOperator(t.type))
			//writeSpan("op", str(t.type));
			ret ~= htmlEncode(str(t.type));
		else if (t.type == tok!"specialTokenSequence" || t.type == tok!"scriptLine")
			writeSpan("cons", t.text);
		else if (t.type == tok!"identifier")
			writeSpan("hid", t.text);
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

	override void format(const AtAttribute atAttribute) {
		if(atAttribute is null || atAttribute.argumentList is null)
			super.format(atAttribute);
		else {
			sink.put("@");
			if(atAttribute.argumentList.items.length == 1) {
				format(atAttribute.argumentList.items[0]);
			} else {
				format(atAttribute.argumentList);
			}
		}
	}

	override void format(const TemplateParameterList templateParameterList)
	{
		putTag("<div class=\"parameters-list\">");
		foreach(i, param; templateParameterList.items)
		{
			putTag("<div class=\"template-parameter-item parameter-item\">");
			put("\t");
			putTag("<span>");
			format(param);
			putTag("</span>");
			putTag("</div>");
		}
		putTag("</div>");
	}

	override void format(const InStatement inStatement) {
		putTag("<a href=\"http://dpldocs.info/in-contract\" class=\"lang-feature\">");
		put("in");
		putTag("</a>");
		//put(" ");
		if(inStatement.blockStatement)
			format(inStatement.blockStatement);
		else if(inStatement.expression) {
			put(" (");
			format(inStatement.expression);
			put(")");
		}
	}

	override void format(const OutStatement outStatement) {
		putTag("<a href=\"http://dpldocs.info/out-contract\" class=\"lang-feature\">");
		put("out");
		putTag("</a>");

		//put(" ");
		if(outStatement.expression) {
			put(" (");
			format(outStatement.parameter);
			put("; ");
			format(outStatement.expression);
			put(")");
		} else {
			if (outStatement.parameter != tok!"")
			{
			    put(" (");
			    format(outStatement.parameter);
			    put(")");
			}

			format(outStatement.blockStatement);
		}
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
				putTag("<span class=\"parenthetical-expression\">(<span class=\"parenthetical-expression-contents\">");
				format(expression);
				putTag("</span>)</span>");
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
			else if (lambdaExpression) { putTag("<span class=\"lambda-expression\">"); format(lambdaExpression); putTag("</span>"); }
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


	bool hadAtAttribute;

		putTag("<span class=\"parameter-type-holder\">");
		putTag("<span class=\"parameter-type\">");
		foreach (count, attribute; parameter.parameterAttributes)
		{
			if (count || hadAtAttribute) space();
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

		bool suppressMagicGoingIn = suppressMagic;

		//if(!suppressMagicGoingIn)
			//putTag("<span class=\"some-ident\">");
		with(identifierOrTemplateInstance)
		{
			format(identifier);
			if (templateInstance)
				format(templateInstance);
		}
		//if(!suppressMagicGoingIn)
			//putTag("</span>");
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

		putTag("<div class=\"parameters-list\">");
		putTag("<span class=\"paren\">(</span>");
		foreach (count, param; parameters.parameters)
		{
			if (count) putTag("<span class=\"comma\">,</span>");
			format(param);
		}
		if (parameters.hasVarargs)
		{
			if (parameters.parameters.length)
				putTag("<span class=\"comma\">,</span>");
			putTag("<div class=\"runtime-parameter-item parameter-item\">");
			putTag("<a href=\"http://dpldocs.info/variadic-function-arguments\" class=\"lang-feature\">");
			putTag("...");
			putTag("</a>");
			putTag("</div>");
		}
		putTag("<span class=\"paren\">)</span>");
		putTag("</div>");
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
				putTag(" &amp;&amp; </div><div class=\"andand-right\">");
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
				putTag(" || </div><div class=\"oror-right\">");
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

	if(holder.querySelector("th:first-child + td"))
		holder.addClass("two-axes");

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

	translateMagicCommands(opening, holder);

	while(text.length) {
		auto fmt = formatDocumentationComment2(text, decl, null, &termination);
		holder.addChild("li", fmt);
		text = termination.remaining;
	}

	return holder;
}

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
