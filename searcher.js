var declById = {};
var termByValue = {};

window.onload = function() {
	var searchXMLRequester = new XMLHttpRequest();
	var indexXMLRequester = new XMLHttpRequest();

	var searchForm = document.getElementById('search');
	searchForm.action = "";
	searchForm.children[1].addEventListener('click', onSearch);
	searchForm.children[1].type = "button";
	
	searchXMLRequester.onreadystatechange = function() {
		if (this.readyState == 4 && this.status == 200) {
			var xml = this.responseXML;
			var node;

			for(var i = 0; i < xml.firstChild.children.length; i += 1) {
				node = xml.firstChild.children[i];
				termByValue[node.attributes['value'].value] = node;
			}
		}
	};
	
	indexXMLRequester.onreadystatechange = function() {
		if (this.readyState == 4 && this.status == 200) {
			var xml = this.responseXML;
			var node;
			
			for(var i = 0; i < xml.firstChild.children.length; i += 1) {
				node = xml.firstChild.children[i];
				declById[node.id] = node;
			}
		}
	};
	
	var loc = window.location.pathname;
	loc = loc.substring(0, loc.lastIndexOf('/'));
	var dir = loc.substring(loc.lastIndexOf('/') + 1);
	
	var prependDir = "";
	if (dir === "source") {
		prependDir = "../";
	}
	
	searchXMLRequester.open("GET", prependDir + "search.xml", true);
	indexXMLRequester.open("GET", prependDir + "index.xml", true);
	searchXMLRequester.send();
	indexXMLRequester.send();
};

function resultsByTerm(term) {
	var t = termByValue[term];
	if (t !== null) {
		return t.querySelectorAll('result');
	}
	return null;
}

function getDecl(i) {
	return declById[i];
}

function onSearch() {
	var newLocation = document.location;
	var search = document.getElementById('search').children[0].value;
	var declScores;
	
	// STUFF here
	
	document.location = newLocation;
}