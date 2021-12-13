LIBDPARSE=Dscanner/libdparse/src/dparse/ast.d Dscanner/libdparse/src/dparse/formatter.d Dscanner/libdparse/src/dparse/parser.d Dscanner/libdparse/src/dparse/entities.d  Dscanner/libdparse/src/dparse/lexer.d Dscanner/libdparse/src/std/experimental/lexer.d Dscanner/src/astprinter.d

all:
	#dmd diff.d terminal.d $(LIBDPARSE)
	dmd -m64 doc2.d latex.d jstex.d comment.d stemmer.d dom.d script.d jsvar.d color.d archive.d -J. $(LIBDPARSE) -g # -version=std_parser_verbose 
	# it may pull in script.d and jsvar.d later fyi
	#
	#dmd -of/var/www/dpldocs.info/locate locate.d  dom.d stemmer.d  cgi -J. -version=fastcgi -m64 -debug
pq:
	dmd -m64 doc2.d latex.d jstex.d comment.d stemmer.d dom.d script.d jsvar.d color.d archive.d -version=with_postgres database.d postgres.d -L-L/usr/local/pgsql/lib -L-lpq -J. $(LIBDPARSE) -g # -version=std_parser_verbose 
locate:
	dmd -oflocate locate.d  dom.d stemmer.d  cgi -J. -version=scgi -m64 -debug postgres.d archive.d database.d -L-L/usr/local/pgsql/lib -g

vps_locate:
	ldc2 -oq -O3 -m64 locate.d  dom.d stemmer.d archive.d  cgi -J. -d-version=scgi -d-version=vps -g ~/arsd/database ~/arsd/postgres -L-L/usr/local/pgsql/lib -L-lpq
ldc:
	ldc2 -oq -O3 -m64 doc2.d latex.d jstex.d comment.d archive.d stemmer.d dom.d color.d -J. $(LIBDPARSE) --d-version=with_postgres database.d postgres.d -L-L/usr/local/pgsql/lib -L-lpq -g # -version=std_parser_verbose 

http:
	dmd -debug -ofserver -version=embedded_httpd -version=with_http_server -m64 doc2.d latex.d archive.d jstex.d cgi.d comment.d stemmer.d dom.d script.d jsvar.d color.d -J. $(LIBDPARSE) -g # -version=std_parser_verbose 
