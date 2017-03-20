// just docs: Tips on using adrdox
/++
$(LIST
	* Always have a package.d for your package, even if it contains no declarations.
	* Always use a module declaration on all modules, and always put a comment on it.
	* Always put a ddoc comment on a public decl, even if it is an empty comment.
	* Want an index.html generated? Run adrdox on a `module index;` (this is a filthy hack but it works)
)

adrdox will not descend into undocumented entities, so a missing doc comment on a top level
declaration will make all effort in documenting inner items useless. If you do not document
a module declaration, the whole module is skipped!
+/
module adrdox.tips;
