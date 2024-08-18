LIBDPARSE=Dscanner/libdparse/src/dparse/ast.d Dscanner/libdparse/src/dparse/formatter.d Dscanner/libdparse/src/dparse/parser.d Dscanner/libdparse/src/dparse/entities.d  Dscanner/libdparse/src/dparse/lexer.d Dscanner/libdparse/src/std/experimental/lexer.d Dscanner/src/astprinter.d
DMD?=dmd

all:
	#$(DMD) diff.d terminal.d $(LIBDPARSE)
	$(DMD) -debug -m64 doc2.d latex.d jstex.d syntaxhighlighter.d comment.d stemmer.d dom.d script.d jsvar.d color.d archive.d -J. $(LIBDPARSE) -g # -version=std_parser_verbose 
	# it may pull in script.d and jsvar.d later fyi
	#
	#$(DMD) -of/var/www/dpldocs.info/locate locate.d  dom.d stemmer.d  cgi -J. -version=fastcgi -m64 -debug
pq:
	$(DMD) -m64 doc2.d latex.d jstex.d syntaxhighlighter.d comment.d stemmer.d dom.d script.d jsvar.d color.d archive.d -version=with_postgres database.d postgres.d -L-L/usr/local/pgsql/lib -L-lpq -J. $(LIBDPARSE) -g # -version=std_parser_verbose 
locate:
	$(DMD) -oflocate locate.d  dom.d stemmer.d  cgi -J. -version=scgi -m64 -debug postgres.d archive.d database.d -L-L/usr/local/pgsql/lib -g

vps_locate:
	ldc2i -oflocate_vps -oq -O3 -m64 locate.d  stemmer.d -J. -d-version=scgi -d-version=vps -g -L-L/usr/local/pgsql/lib -L-lpq
ldc:
	echo "use make pq instead ldc is broken"
	echo ldc2 -oq -O3 --d-debug -m64 doc2.d latex.d jstex.d syntaxhighlighter.d comment.d archive.d stemmer.d dom.d color.d -J. $(LIBDPARSE) --d-version=with_postgres database.d postgres.d -L-L/usr/local/pgsql/lib -L-lpq -g # -version=std_parser_verbose 

http:
	$(DMD) -debug -ofserver -version=embedded_httpd -version=with_http_server -m64 doc2.d latex.d archive.d jstex.d cgi.d syntaxhighlighter.d comment.d stemmer.d dom.d script.d jsvar.d color.d -J. $(LIBDPARSE) -g # -version=std_parser_verbose 
