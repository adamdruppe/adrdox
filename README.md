This is my documentation generator, the results of which can be seen on http://dpldocs.info/

You should be able to just clone it and run `make`, everything it needs is included.

After you compile it, you can copy skeleton-default.html to skeleton.html and edit a few things  inside it to your liking (or you can leave it and the generator will copy it automatically on first run). You may
want to replace the contents of the `<div id="page-header">` and delete the suggestion
box. You might also want to edit the style.css file. At the top, the first 20 lines or
so define some basic colors. You can choose from the three I set or create your own scheme.

The rest of the css file is a monster, so you probably don't get to get far into it.

Once you are ready, run `./doc2 -i path/to/your/package` For example, `./doc2 ~/code/arsd`.
The generator will scan it automatically for .d files and generate output in a new `generated-docs`
folder it will create.

NOTE: the `-i` flag means "generate search index". It will create a full-text search index that can be loaded by `locate.d` or by javascript (the default skeleton includes a search form that will work with the JS search). The JS search kinda sucks but can be used offline (just open the file in your browser) or on a static site like github pages.

You may omit the -i if you choose, the file it generates can be quite large so you don't always want it, but then the search form won't work unless you build locate.d and configure your setup to serve it (currently not supported for third parties, but that is what I do on dpldocs.info).

Then open one of the resulting files in your browser and you should see the results.

Syntax is currently described here:

http://dpldocs.info/experimental-docs/adrdox.syntax.html

Edit the makefile to build locate.d if you want the search thing. That is currently unsupported
for other people (it just works on my server and is programmed with some assumptions).

This is still pretty rough so don't expect too much yet.

## License
Boost
