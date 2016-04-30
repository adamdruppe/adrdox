This is my documentation generator, the results of which can be seen on http://dpldocs.info/

You should be able to just clone it and run `make`, everything it needs is included.

Once it is build, run `./doc2 path/to/your/package --directory where/html/goes`

It works best if you build a whole package at a time. You might want to hack the program
to make the search and index (there are bools in main that enable this) and if you keep
them in the current directory, it will be better at incremental builds.

Copy style.css and script.s into the directory along with the HTML, then open one of
the files in your browser. You should see the result!

Syntax is currently described here:

http://dpldocs.info/experimental-docs/test.html

The skeleton.html file is used to change the page layout, if you want to.

Edit the makefile to build locate.d if you want the search thing. Also edit the doc2.d
to make the listing and search indexes (bools in main) to build them.

This is still pretty rough so don't expect too much yet.
