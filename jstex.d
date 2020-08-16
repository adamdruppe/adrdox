module adrdox.jstex;

import arsd.dom;

enum auto mathSpanCssClass = "raw-tex-math";

static immutable string[] filesForKaTeX = (){
	string[] files = [];

	static foreach (ext; ["css", "js"]) {
		files ~= "katex.min." ~ ext;
	}
	static foreach (ext; ["ttf", "woff", "woff2"]) {
		static foreach (family; ["AMS-Regular",
														 "Caligraphic-Bold", "Caligraphic-Regular",
														 "Fraktur-Bold", "Fraktur-Regular",
														 "Main-BoldItalic", "Main-Bold", "Main-Italic", "Main-Regular",
														 "Math-BoldItalic", "Math-Italic",
														 "SansSerif-Bold", "SansSerif-Italic", "SansSerif-Regular",
														 "Script-Regular",
														 "Size1-Regular", "Size2-Regular", "Size3-Regular", "Size4-Regular",
														 "Typewriter-Regular"]) {
			files ~= "KaTeX_" ~ family ~ "." ~ ext;
		}
	}
	return files;
}();

void prepareForKaTeX(Document document) {
	auto style = Element.make("link");
	style.rel = "stylesheet";
	style.href = "katex.min.css";

	auto head = document.getFirstElementByTagName("head");
	head.addChild(style);

	auto script = Element.make("script");
	script.type = "text/javascript";
	script.src = "katex.min.js";
	script.attrs.onload = "document.querySelectorAll('span." ~ mathSpanCssClass ~ "').forEach(function(e){e.outerHTML=katex.renderToString(e.innerText)})";

	auto body_ = document.getFirstElementByTagName("body");
	body_.addChild(script);
}

Element mathToKaTeXHtml(string mathCode) {
	return Element.make("span", mathCode, mathSpanCssClass);
}
