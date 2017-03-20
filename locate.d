// FIXME: add +proj and -proj to adjust project results

import ps = PorterStemmer;
import arsd.cgi;
import arsd.dom;
import std.stdio;
import std.file;
import std.conv : to;
import std.algorithm : sort;
import std.string : toLower, replace, split;

class ProjectSearcher {
	this(string path, string name, int projectAdjustment) {
		this.projectName = name;
		this.projectAdjustment = projectAdjustment;
		auto index = new Document();
		index.parseUtf8(readText(path), true, true);

		if(auto s = index.querySelector("script#search-index-container")) {
			index = new Document();
			index.parseUtf8(s.innerHTML, true, true);
		}

		foreach(element; index.querySelectorAll("adrdox > listing decl[id]"))
			declById[element.attrs.id] = element;
		foreach(element; index.querySelectorAll("adrdox > index term[value]"))
			termByValue[element.attrs.value] = element;
	}

	string projectName;
	int projectAdjustment = 0;

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


	Element[string] declById;
	Element[string] termByValue;

	static struct Magic {
		string declId;
		int score;
		Element decl;
		ProjectSearcher searcher;
	}

	Magic[] getPossibilities(string search) {
		int[string] declScores;

		int[string] declHits;

		ps.PorterStemmer s;

		auto terms = search.split(" ");// ~ search.split(".");
		// filter empty terms
		for(int i = 0; i < terms.length; i++) {
			if(terms[i].length == 0) {
				terms[i] = terms[$-1];
				terms = terms[0 .. $-1];
				i--;
			}
		}

		void addHit(Element item, size_t idx) {
			if(idx == 0) {
				declScores[item.attrs.decl] += to!int(item.attrs.score);
				return;
			}
			if(item.attrs.decl in declScores) {
				declScores[item.attrs.decl] += 25; // hit both terms
				declScores[item.attrs.decl] += to!int(item.attrs.score);
			} else {
				// only hit one term...
				declScores[item.attrs.decl] += to!int(item.attrs.score) / 2;
			}
		}

		// On each term, we want to check for exact match and fuzzy match / natural language match.
		// FIXME: if something matches both it should be really strong. see time_t vs "time_t std.datetime"
		foreach(idx, term; terms) {
			assert(term.length > 0);

			foreach(item; resultsByTerm(term)) {
				addHit(item, idx);
				declHits[item.attrs.decl] |= 1 << idx;
			}
			auto l = term.toLower;
			if(l != term)
			foreach(item; resultsByTerm(l)) {
				addHit(item, idx);
				declHits[item.attrs.decl] |= 1 << idx;
			}
			auto st = s.stem(term.toLower).idup;
			if(st != l)
			foreach(item; resultsByTerm(st)) {
				addHit(item, idx);
				declHits[item.attrs.decl] |= 1 << idx;
			}
		}

		Magic[] magic;

		foreach(decl, score; declScores) {
			auto hits = declHits[decl];
			foreach(idx, term; terms) {
				if(!(hits & (1 << idx)))
					score /= 2;
			}
			magic ~= Magic(decl, score + projectAdjustment, getDecl(decl), this);
		}

		if(magic.length == 0) {
			foreach(term; terms) {
				term = term.toLower();
				foreach(id, decl; declById) {
					import std.algorithm;
					auto name = decl.requireSelector("> name").innerText.toLower;
					auto dist = cast(int) levenshteinDistance(name, term);
					if(dist <= 2)
						magic ~= Magic(id, projectAdjustment + (3 - dist), decl, this);
				}
			}
		}

		// boosts based on topography
		foreach(ref item; magic) {
			auto decl = item.decl;
			if(decl.attrs.type == "module") {
				// if it is a module, give it moar points
				item.score += 8;
				continue;
			}
			if(decl.parentNode.attrs.type == "module") {
				item.score += 5;
			}
		}

		return magic;
	}

}

ProjectSearcher[] projectSearchers;

static this() {
	projectSearchers ~= new ProjectSearcher("experimental-docs/std.xml", "Standard Library", 5);
	projectSearchers ~= new ProjectSearcher("experimental-docs/arsd.xml", "arsd", 4);
	projectSearchers ~= new ProjectSearcher("experimental-docs/vibe.xml", "Vibe.d", 0);
	projectSearchers ~= new ProjectSearcher("experimental-docs/dmd.xml", "DMD", 0);
}

void searcher(Cgi cgi) {
	auto search = cgi.request("q", cgi.queryString);

	ProjectSearcher.Magic[] magic;
	foreach(searcher; projectSearchers)
		magic ~= searcher.getPossibilities(search);

	sort!((a, b) => a.score > b.score)(magic);

	// adjustments based on previously showing results
	{
		bool[string] alreadyPresent;
		foreach(ref item; magic) {
			auto decl = item.decl;
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
		Element decl = item.decl;
		if(decl is null) continue; // should never happen
		auto link = "http://dpldocs.info/experimental-docs/" ~ decl.requireSelector("link").innerText;
		auto fqn = getFqn(decl);
		if(fqn in alreadyPresent)
			continue;
		alreadyPresent[fqn] = true;
		auto dt = ml.addChild("dt");
		dt.addClass("search-result");
		dt.addChild("span", item.searcher.projectName).addClass("project-name");
		dt.addChild("br");
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

