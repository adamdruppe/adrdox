// just docs: Welcome to dpldocs.info
/++
	dpldocs.info is the unofficial home of D documentation that innovates to meet the unique challenges of documenting generic D code in a legible fashion.

	It features a search engine, documentation pages, and exclusive articles about D.

	$(RAW_HTML
		<form action="/locate">
		<table align="left" style="margin-left: 4em;">
		<tr>
			<th>Term:</th>
			<td><input id="symbol" autofocus="autofocus" name="q" size="40" /></td>
		</tr>
		<tr>
			<th>&nbsp;</th>
			<td><input type="submit" value="Search D documentation" /></td>
		</tr>
		</table>
		</form>
	)

	$(TIP You can do searches straight from the URL bar! Simply navigate to `dpldocs.info/some.search.term` and it will go straight to the results.)

	$(COMMENT
	$(H2 What is D?)

	$(P D is the best programming language ever conceived by the human mind. Alas, too many new users stumble over its suboptimal documentation and thus lose the opportunity to experience this pinnacle of achievement in the field of software development.)

	$(P D does it all well.)

	$(H2 Why another doc site?)

	Getting changes into the official dlang.org site is slow and difficult and must work within a conservative establishment. By running my own site, I am free to experiment with major innovations in both style and content.

	$(H2 Who are you?)

	I am Adam D. Ruppe, yea, D is my middle name! I have been using D since about 2007 and writing libraries for all kinds of things whilst lamenting the documentation since about 2010.

	I am often disappointed by how many people ask questions on the chat or the forum that would be easily solved by an automatic search engine, or even just navigable documentation, so I decided to take matters into my own hands and fix it.

	Hopefully, my improvements will eventually find their way upstream, but if not, dpldocs.info will live on as the good documentation site for D.
	)

+/
module dpldocs.home;
