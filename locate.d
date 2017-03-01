import ps = PorterStemmer;
import arsd.cgi;
import arsd.dom;
import std.stdio;
import std.file;
import std.conv : to;
import std.algorithm : sort;
import std.string : toLower, replace, split;


Document index;
Document search;

Element[string] declById;
Element[string] termByValue;

static this() {
	index = new Document();
	index.parseUtf8(readText("experimental-docs/index.xml"), true, true);
	search = new Document();
	search.parseUtf8(readText("experimental-docs/search.xml"), true, true);

	foreach(element; index.querySelectorAll("decl[id]"))
		declById[element.attrs.id] = element;
	foreach(element; search.querySelectorAll("term[value]"))
		termByValue[element.attrs.value] = element;
}

Element[] resultsByTerm(string term) {
	if(auto t = term in termByValue) {
		return (*t).querySelectorAll("result");
	} else {
		return null;
	}
}

Element getDecl(string i) {
	if(auto a = i in declById)
		return *a;
	return null;
}

void searcher(Cgi cgi) {
	auto search = cgi.request("q", cgi.queryString);

	int[string] declScores;

	ps.PorterStemmer s;

	// On each term, we want to check for exact match and fuzzy match / natural language match.
	foreach(term; search.split(" ") ~ search.split(".")) {
		if(term.length == 0) continue;
		foreach(item; resultsByTerm(term))
			declScores[item.attrs.decl] += to!int(item.attrs.score);
		auto l = term.toLower;
		if(l != term)
		foreach(item; resultsByTerm(l))
			declScores[item.attrs.decl] += to!int(item.attrs.score);
		auto st = s.stem(term.toLower).idup;
		if(st != l)
		foreach(item; resultsByTerm(st))
			declScores[item.attrs.decl] += to!int(item.attrs.score);
	}

	struct Magic {
		string decl;
		int score;
		Element declElement;
	}
	Magic[] magic;

	foreach(decl, score; declScores)
		magic ~= Magic(decl, score, getDecl(decl));

	// boosts based on topography
	foreach(ref item; magic) {
		auto decl = item.declElement;
		if(decl.attrs.type == "module") {
			// if it is a module, give it moar points
			item.score += 8;
			continue;
		}
		if(decl.parentNode.attrs.type == "module") {
			item.score += 5;
		}
	}

	sort!((a, b) => a.score > b.score)(magic);

	// adjustments based on previously showing results
	{
		bool[string] alreadyPresent;
		foreach(ref item; magic) {
			auto decl = item.declElement;
			if(decl.parentNode.id in alreadyPresent)
				item.score -= 8;
			alreadyPresent[decl.id] = true;
		}
	}

	auto document = new Document();
	document.parseUtf8(import("skeleton.html"), true, true);
	document.title = "Search Results";

	auto form = document.requireElementById!Form("search");
	form.setValue("searchTerm", search);

	auto l = document.requireSelector("link");
	l.href = "/experimental-docs/" ~ l.href;
	l = document.requireSelector("script[src]");
	l.src = "/experimental-docs/" ~ l.src;

	auto pc = document.requireSelector("#page-content");
	pc.addChild("h1", "Search Results");
	auto ml = pc.addChild("dl");
	ml.className = "member-list";

	string getFqn(Element i) {
		string n;
		while(i) {
			if(n) n = "." ~ n;
			n = i.requireSelector("> name").innerText ~ n;
			if(i.attrs.type == "module")
				break;
			i = i.parentNode;
			if(i.tagName != "decl")
				break;
		}
		return n;
	}

	bool[string] alreadyPresent;
	int count = 0;
	foreach(idx, item; magic) {
		Element decl = getDecl(item.decl);
		if(decl is null) continue; // should never happen
		auto link = "http://dpldocs.info/experimental-docs/" ~ decl.requireSelector("link").innerText;
		auto fqn = getFqn(decl);
		if(fqn in alreadyPresent)
			continue;
		alreadyPresent[fqn] = true;
		auto dt = ml.addChild("dt");
		dt.addClass("search-result");
		dt.addChild("a", fqn.replace(".", ".\u200B"), link);
		dt.dataset.score = to!string(item.score);
		auto html = decl.requireSelector("desc").innerText;
		//auto d = new Document(html);
		//writeln(d.root.innerText.replace("\n", " "));
		//writeln();

		ml.addChild("dd", Html(html));
		count++;

		if(count >= 20)
			break;
	}

	cgi.write(document.toString, true);
}

mixin GenericMain!(searcher);

