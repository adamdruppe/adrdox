This is my documentation generator, the results of which can be seen on http://dpldocs.info/

You should be able to just clone it and run `make`, everything it needs is included.

After you compile it, open skeleton.html and edit a few things to your liking. You may
want to replace the contents of the `<div id="page-header">` and delete the suggestion
box. You might also want to edit the style.css file. At the top, the first 20 lines or
so define some basic colors. You can choose from the three I set or create your own scheme.

The rest of the css file is a monster, so you probably don't get to get far into it.

Once you are ready, run `./doc2 path/to/your/package` For example, `./doc2 ~/code/arsd`.
The generator will scan it automatically for .d files and generate output in a new `generated-docs`
folder it will create.

Then open one of the resulting files in your browser and you should see the results.

Syntax is currently described here:

http://dpldocs.info/experimental-docs/adrdox.syntax.html

Edit the makefile to build locate.d if you want the search thing. That is currently unsupported
for other people (it just works on my server and is programmed with some assumptions).

This is still pretty rough so don't expect too much yet.

## License
Boost
