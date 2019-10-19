// FIXME: add +proj and -proj to adjust project results

// my local config assumes this will be on port 9653

module adrdox.locate;

import arsd.postgres;

//  # dpldocs: if one request, go right to it. and split camel case and ry rearranging words. File.size returned nothing

import ps = PorterStemmer;
import arsd.cgi;
import arsd.dom;
import std.stdio;
import std.file;
import std.conv : to;
import std.algorithm : sort;
import std.string : toLower, replace, split;

PostgreSql db_;

PostgreSql db() {
	if(db_ is null)
		db_ = new PostgreSql("dbname=dpldocs user=me");
	return db_;
}

class ProjectSearcher {
	int projectId;
	this(string path, string name, int projectAdjustment) {

		//foreach(row; db.query("SELECT id FROM projects WHERE name = ?", name))
			//projectId = to!int(row[0]);

		projectId = 1;

		this.projectName = name;
		this.projectAdjustment = projectAdjustment;
	}

	string projectName;
	int projectAdjustment = 0;

	TermElement[] resultsByTerm(string term) {
		TermElement[] ret;
		// FIXME: project id?!?!?
		foreach(row; db.query("SELECT declId, score FROM terms WHERE term = ?", term))
			ret ~= TermElement(to!int(row[0]), to!int(row[1]));
		return ret;
	}

	DeclElement getDecl(int i) {
		foreach(row; db.query("SELECT * FROM decls WHERE id = ? AND project_id = ?", i, projectId)) {
			return DeclElement(row["name"], row["description"], row["link"], row["id"].to!int, row["type"], row["parent"].length ? row["parent"].to!int : 0);
		}
		return DeclElement.init;
	}

	static struct TermElement {
		int declId;
		int score;
	}

	static struct DeclElement {
		string name;
		string description; // actually HTML
		string link;
		int id;
		string type;
		int parent;
	}

	static struct Magic {
		int declId;
		int score;
		DeclElement decl;
		ProjectSearcher searcher;
	}

	Magic[] getPossibilities(string search) {
		int[int] declScores;

		int[int] declHits;

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

		void addHit(TermElement item, size_t idx) {
			if(idx == 0) {
				declScores[item.declId] += item.score;
				return;
			}
			if(item.declId in declScores) {
				declScores[item.declId] += 25; // hit both terms
				declScores[item.declId] += item.score;
			} else {
				// only hit one term...
				declScores[item.declId] += item.score / 2;
			}
		}

		// On each term, we want to check for exact match and fuzzy match / natural language match.
		// FIXME: if something matches both it should be really strong. see time_t vs "time_t std.datetime"
		foreach(idx, term; terms) {
			assert(term.length > 0);

			foreach(item; resultsByTerm(term)) {
				addHit(item, idx);
				declHits[item.declId] |= 1 << idx;
			}
			auto l = term.toLower;
			if(l != term)
			foreach(item; resultsByTerm(l)) {
				addHit(item, idx);
				declHits[item.declId] |= 1 << idx;
			}
			auto st = s.stem(term.toLower).idup;
			if(st != l)
			foreach(item; resultsByTerm(st)) {
				addHit(item, idx);
				declHits[item.declId] |= 1 << idx;
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
				foreach(row; db.query("SELECT id, term FROM terms")) {
					string name = row[1];
					int id = row[0].to!int;
					import std.algorithm;
					name = name.toLower;
					auto dist = cast(int) levenshteinDistance(name, term);
					if(dist <= 2)
						magic ~= Magic(id, projectAdjustment + (3 - dist), getDecl(id), this);
				}
			}
		}

		// boosts based on topography
		foreach(ref item; magic) {
			auto decl = item.decl;
			if(decl.type == "module") {
				// if it is a module, give it moar points
				item.score += 8;
				continue;
			}
			if(getDecl(decl.id).type == "module") {
				item.score += 5;
			}
		}

		return magic;
	}

}

__gshared ProjectSearcher[] projectSearchers;

shared static this() {
	version(vps) {
		version(embedded_httpd)
			processPoolSize = 2;

		import std.file;

		foreach(dirName; dirEntries("/dpldocs/", SpanMode.shallow)) {
			string filename;
			filename = dirName ~ "/master/adrdox-generated/search-results.html.gz";
			if(!exists(filename)) {
				filename = null;
				foreach(fn; dirEntries(dirName, "search-results.html.gz", SpanMode.depth)) {
					filename = fn;
					break;
				}
			}

			if(filename.length) {
				try {
				projectSearchers ~= new ProjectSearcher(filename, dirName["/dpldocs/".length .. $], 0);
				import std.stdio; writeln("Loading ", filename);
				} catch(Exception e) {
				import std.stdio; writeln("FAILED ", filename, "\n", e);

				}
			}
		}

		import std.stdio;
		writeln("Ready");

	} else {
		projectSearchers ~= new ProjectSearcher("experimental-docs/search-results.html", "", 5);
		//projectSearchers ~= new ProjectSearcher("experimental-docs/std.xml", "Standard Library", 5);
		//projectSearchers ~= new ProjectSearcher("experimental-docs/arsd.xml", "arsd", 4);
		//projectSearchers ~= new ProjectSearcher("experimental-docs/vibe.xml", "Vibe.d", 0);
		//projectSearchers ~= new ProjectSearcher("experimental-docs/dmd.xml", "DMD", 0);
	}
}

import std.uri;

void searcher(Cgi cgi) {

	version(vps) {
		string path = cgi.requestUri;

		auto q = path.indexOf("?");
		if(q != -1) {
			path = path[0 .. q];
		}

		if(path.length && path[0] == '/')
			path = path[1 .. $];



		if(path == "script.js") {
			import std.file;
			cgi.setResponseContentType("text/javascript");
			cgi.write(std.file.read("/dpldocs-build/script.js"), true);
			return;

		}

		if(path == "style.css") {
			import std.file;
			cgi.setResponseContentType("text/css");
			cgi.write(std.file.read("/dpldocs-build/style.css"), true);
			return;
		}
	}

	auto search = cgi.request("q", cgi.request("searchTerm", cgi.queryString));
	alias searchTerm = search;

	if(search.length == 0) {
		cgi.setResponseLocation("/");
		return;
	}
	auto parts = search.split(" ");
	switch(parts[0].toLower()) {
		case "auto-ref-return-function-prototype":
			cgi.setResponseLocation("http://dlang.org/spec/function.html#auto-ref-functions");
			return;
		case "auto-function-return-prototype":
			cgi.setResponseLocation("http://dlang.org/spec/function.html#auto-functions");
			return;
		case "ref-function-return-prototype":
			cgi.setResponseLocation("http://dlang.org/spec/function.html#ref-functions");
			return;
		case "bugzilla":
			auto url = "http://d.puremagic.com/issues/";
			if(parts.length > 1)
				url ~= "show_bug.cgi?id=" ~ parts[1];
			cgi.setResponseLocation(url);
			return;
		case "dip":
			auto url = "http://wiki.dlang.org/DIPs";
			if(parts.length > 1)
				url = "http://wiki.dlang.org/DIP" ~ parts[1];
			cgi.setResponseLocation(url);
			return;
		case "wiki":
			auto url = "http://wiki.dlang.org/";
			if(parts.length > 1)
				url ~= "search="~std.uri.encodeComponent(join(parts[1..$], "
							"))~"&go=Go&title=Special%3ASearch";
			cgi.setResponseLocation(url);
			return;
		case "faqs":
		case "faq":
			cgi.setResponseLocation("http://wiki.dlang.org/FAQs");
			return;
		case "oldwiki":
			auto url = "http://prowiki.org/wiki4d/wiki.cgi";
			if(parts.length > 1)
				url ~= "?formpage=Search&id=Search&search=" ~ std.uri.
					encodeComponent(join(parts[1..$], " "));
			cgi.setResponseLocation(url);
			return;
		default:
			// just continue
			if(std.file.exists("experimental-docs/" ~ searchTerm ~ ".1.html")) {
				cgi.setResponseLocation("/experimental-docs/" ~ searchTerm ~ ".1.html");
				return;
			}
			if(std.file.exists("experimental-docs/" ~ searchTerm ~ ".html")) {
				cgi.setResponseLocation("/experimental-docs/" ~ searchTerm ~ ".html");
				return;
			}
	}


	ProjectSearcher.Magic[] magic;
	foreach(searcher; projectSearchers)
		magic ~= searcher.getPossibilities(search);

	sort!((a, b) => a.score > b.score)(magic);

	// adjustments based on previously showing results
	{
		bool[int] alreadyPresent;
		foreach(ref item; magic) {
			auto decl = item.decl;
			if(decl.parent in alreadyPresent)
				item.score -= 8;
			alreadyPresent[decl.id] = true;
		}
	}

	auto document = new Document();
	version(vps) {
		import std.file;
		document.parseUtf8(readText("/dpldocs-build/skeleton.html"), true, true);
		document.title = "Dub Documentation Search";
	} else
		document.parseUtf8(import("skeleton.html"), true, true);
	document.title = "Search Results";

	auto form = document.requireElementById!Form("search");
	form.setValue("searchTerm", search);

	version(vps) {
		// intentionally blank
	} else {
		auto l = document.requireSelector("link");
		l.href = "/experimental-docs/" ~ l.href;
		l = document.requireSelector("script[src]");
		l.src = "/experimental-docs/" ~ l.src;
	}

	auto pc = document.requireSelector("#page-content");
	pc.addChild("h1", "Search Results");
	auto ml = pc.addChild("dl");
	ml.className = "member-list";

	string getFqn(ProjectSearcher searcher, ProjectSearcher.DeclElement i) {
		string n;
		while(true) {
			if(n) n = "." ~ n;
			n = i.name ~ n;
			if(i.type == "module")
				break;
			if(i.parent == 0)
				break;
			i = searcher.getDecl(i.parent);
			if(i.id == 0)
				break;
		}
		return n;
	}

	bool[string] alreadyPresent;
	int count = 0;
	foreach(idx, item; magic) {
		auto decl = item.decl;
		if(decl.id == 0) continue; // should never happen
		version(vps)
			auto link = "http://"~item.searcher.projectName~".dpldocs.info/" ~ decl.link;
		else
			auto link = "http://dpldocs.info/experimental-docs/" ~ decl.link;
		auto fqn = getFqn(item.searcher, decl);
		if(fqn in alreadyPresent)
			continue;
		alreadyPresent[fqn] = true;
		auto dt = ml.addChild("dt");
		dt.addClass("search-result");
		dt.addChild("span", item.searcher.projectName).addClass("project-name");
		dt.addChild("br");
		dt.addChild("a", fqn.replace(".", ".\u200B"), link);
		dt.dataset.score = to!string(item.score);
		auto html = decl.description;
		//auto d = new Document(html);
		//writeln(d.root.innerText.replace("\n", " "));
		//writeln();

		// FIXME fix relative links from here
		ml.addChild("dd", Html(html));
		count++;

		if(count >= 20)
			break;
	}

	cgi.write(document.toString, true);
}

mixin GenericMain!(searcher);

