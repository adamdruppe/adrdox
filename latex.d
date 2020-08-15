module adrdox.latex;

import std.process;
import std.file;

import arsd.dom;

string makeDataUrl(string mimeType, in void[] data) {
    import std.base64;
	auto data64 = Base64.encode(cast(const(ubyte[])) data);
	return "data:" ~ mimeType ~ ";base64," ~ cast(string)(data64);
}

// requires latex and dvipng to be installed on your system already, it just
// calls out to them in the shell
Element mathToImgHtml(string mathCode) {

	string dir = tempDir;

	// FIXME: this should prolly be unique or somethign
	string filebase = "./adrdox";

	std.file.write(dir ~ "/" ~ filebase ~ ".latex", 
`\documentclass{article}
\usepackage{amsmath}
\usepackage{amsfonts}
\usepackage{amssymb}
\pagestyle{empty}
\begin{document}
$ `~mathCode~` $
\end{document}`
	);

	auto tpl = executeShell(
		"latex -interaction=nonstopmode " ~ filebase ~ ".latex"
		~ " && " ~
		"dvipng -T tight -D 200 -o "~filebase~".png -bg Transparent "~filebase~".dvi -z 9",
		null, Config.none, size_t.max, dir
	);

	if(tpl.status != 0)
		return null;


	auto prefix = dir ~ "/" ~ filebase;
	if(exists(prefix ~ ".aux"))
		remove(prefix ~ ".aux");
	if(exists(prefix ~ ".dvi"))
		remove(prefix ~ ".dvi");
	if(exists(prefix ~ ".latex"))
		remove(prefix ~ ".latex");
	if(exists(prefix ~ ".log"))
		remove(prefix ~ ".log");

	if(exists(prefix ~ ".png")) {
		auto file = read(prefix ~ ".png");
		remove(prefix ~ ".png");

		auto img = Element.make("img");
		img.alt = mathCode;
		img.src = makeDataUrl("image/png", file);
		img.className = "rendered-math";
		return img;
	}

	return null;

}
