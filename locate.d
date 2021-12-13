// FIXME: add +proj and -proj to adjust project results

// dmdi -g -debug -version=vps locate stemmer.d -oflocate_vps -version=scgi

// my local config assumes this will be on port 9653

module adrdox.locate;

import arsd.postgres;

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
	if(db_ is null) {
		db_ = new PostgreSql("dbname=adrdox");
	}
	return db_;
}

TermElement[] resultsByTerm(string term) {
	TermElement[] ret;
	foreach(row; db.query("SELECT d_symbols.id, score FROM hand_written_tags INNER JOIN d_symbols ON d_symbol_fully_qualified_name = fully_qualified_name WHERE tag = ? ORDER BY score DESC LIMIT 35", term))
		ret ~= TermElement(to!int(row[0]), to!int(row[1]));

	foreach(row; db.query("SELECT d_symbols.id, name FROM d_symbols WHERE fully_qualified_name = ? OR name = ? LIMIT 35", term, term)) {
		ret ~= TermElement(to!int(row[0]), row[1] == term ? 25 : 50);
	}

	foreach(row; db.query("
		SELECT
			d_symbols_id, score
		FROM
			auto_generated_tags
		INNER JOIN
			package_version ON package_version_id = package_version.id
		WHERE
			tag = ?
			AND
			is_latest = true
		ORDER BY
			score + (case (dub_package_id = 6 or dub_package_id = 9) when true then 5 else 0 end) DESC
		LIMIT 35", term))
		ret ~= TermElement(to!int(row[0]), to!int(row[1]));
	return ret;
}

DeclElement getDecl(int i) {
	foreach(row; db.query("
		SELECT
			d_symbols.*,
			dub_package.url_name AS package_subdomain
		FROM
			d_symbols
		INNER JOIN
			package_version ON package_version.id = d_symbols.package_version_id
		INNER JOIN
			dub_package ON dub_package.id = package_version.dub_package_id
		WHERE
			d_symbols.id = ?
			AND
			is_latest = true
		", i)) {
		return DeclElement(row["fully_qualified_name"], row["summary"], row["url_name"], row["id"].to!int, "", 0, row["package_subdomain"]);
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
	string packageName;
}

static struct Magic {
	int declId;
	int score;
	DeclElement decl;
}

int getProjectAdjustment(DeclElement details, string preferredProject) {
	int projectAdjustment;
	if(preferredProject.length) {
		if(preferredProject == details.packageName)
			projectAdjustment = 150;
	}
	if(details.packageName == "phobos" || details.packageName == "druntime")
		projectAdjustment += 50;
	if(details.packageName == "arsd-official")
		projectAdjustment += 30;

	return projectAdjustment;
}

Magic[] getPossibilities(string search, string preferredProject) {
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
		auto details = getDecl(decl);
		int projectAdjustment = getProjectAdjustment(details, preferredProject);
		magic ~= Magic(decl, score + projectAdjustment, details);
	}

	if(magic.length == 0) {
		foreach(term; terms) {
			if(term.length == 0) continue;
			//term = term.toLower();
			foreach(row; db.query("SELECT id, fully_qualified_name FROM d_symbols WHERE fully_qualified_name > ? LIMIT 50", term)) {
				string name = row[1];
				int id = row[0].to!int;
				/+
				import std.algorithm;
				name = name.toLower;
				auto dist = cast(int) levenshteinDistance(name, term);
				if(dist <= 2) {
				+/
				int dist = 0;
				{
					auto details = getDecl(id);
					int projectAdjustment = getProjectAdjustment(details, preferredProject);
					magic ~= Magic(id, projectAdjustment + (3 - dist), details);
				}
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

import std.uri;

void searcher(Cgi cgi) {

	auto search = cgi.request("q", cgi.request("searchTerm", cgi.queryString));

	version(vps) {
		string path = cgi.requestUri;

		auto q = path.indexOf("?");
		if(q != -1) {
			path = path[0 .. q];
		}

		if(path.length && path[0] == '/')
			path = path[1 .. $];

                if(path.length == 0 && search.length == 0) {
			import std.file;

			cgi.write(std.file.read("/dpldocs-build/search-home.html"), true);
			return;
                }


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
	} else {
		string path = cgi.requestUri;

		auto q = path.indexOf("?");
		if(q != -1) {
			path = path[0 .. q];
		}

		if(path.length && path[0] == '/')
			path = path[1 .. $];


	}

	alias searchTerm = search;

	if(search.length == 0 && path.length)
		search = path;

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
		case "template-alias-parameter":
			cgi.setResponseLocation("https://dlang.org/spec/template.html#aliasparameters");
			return;
		case "is-expression":
			cgi.setResponseLocation("https://dlang.org/spec/expression.html#IsExpression");
			return;
		case "typeof-expression":
			cgi.setResponseLocation("https://dlang.org/spec/declaration.html#Typeof");
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
			version(vps) { } else {
			/+
			if(std.file.exists("/var/www/dpldocs.info/experimental-docs/" ~ searchTerm ~ ".1.html")) {
				cgi.setResponseLocation("/experimental-docs/" ~ searchTerm ~ ".1.html");
				return;
			}
			if(std.file.exists("/var/www/dpldocs.info/experimental-docs/" ~ searchTerm ~ ".html")) {
				cgi.setResponseLocation("/experimental-docs/" ~ searchTerm ~ ".html");
				return;
			}
			+/
				// redirect to vps
				if("local" !in cgi.get)
				cgi.setResponseLocation("//search.dpldocs.info/?q=" ~ std.uri.encodeComponent(searchTerm));
			}
	}


	Magic[] magic = getPossibilities(search, cgi.request("project"));

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

	string getFqn(DeclElement i) {
		string n;
		while(true) {
			if(n) n = "." ~ n;
			n = i.name ~ n;
			if(i.type == "module")
				break;
			if(i.parent == 0)
				break;
			i = getDecl(i.parent);
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
			auto link = "//"~decl.packageName~".dpldocs.info/" ~ decl.link;
		else
			auto link = "//dpldocs.info/experimental-docs/" ~ decl.link;
		if(decl.link.length && decl.link[0] == '/')
			link = decl.link;
		auto fqn = getFqn(decl);
		if(fqn in alreadyPresent)
			continue;
		alreadyPresent[fqn] = true;
		auto dt = ml.addChild("dt");
		dt.addClass("search-result");
		dt.addChild("span", decl.packageName).addClass("project-name");
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

