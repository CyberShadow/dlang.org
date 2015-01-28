// D HTML to CHM converter/generator
// By Vladimir Panteleev <vladimir@thecybershadow.net> (2007-2011)
// Placed in the Public Domain
// Written in the D Programming Language, version 2

//import std.algorithm : min, canFind, sort;
//import std.array;
//import std.ascii;
import std.exception;
import std.file;
import std.range;
import std.stdio : stderr;
import std.string;
import std.regex;
import std.path;

//alias std.ascii.newline newline;

enum ROOT = `.`;

// ********************************************************************
/*
string backSlash(string s)
{
	return s.replace(`/`, `\`);
}

bool contains(string s, string sub) { return s.indexOf(sub) >= 0; }

RegexMatch!string match;

bool test(string line, Regex!char re)
{
	match = std.regex.match(line, re);
	return !match.empty;
}

string getAnchor(string s)
{
	int i = s.indexOf('#');
	return i<0 ? "" : s[i..$];
}

string removeAnchor(string s)
{
	int i = s.indexOf('#');
	return i<0 ? s : s[0..i];
}

string absoluteUrl(string base, string url)
{
	if (url.contains("://"))
		return url;

	base = base.backSlash();
	url  = url.backSlash();
	enforce(url.length, "Empty URL");

	if (url[0]=='#')
		return base ~ url;

	auto baseParts = base.split(`\`);
	baseParts = baseParts[0..$-1];

	while (url.startsWith(`..\`))
	{
		url = url[3..$];
		baseParts = baseParts[0..$-1];
	}
	return baseParts.join(`\`) ~ `\` ~ url;
}

string adjustPath(string s)
{
	if (s.startsWith(ROOT ~ `\`))
		s = "chm" ~ s[ROOT.length..$];
	return s;
}
*/
string adjustPath(string s)
{
	enforce(s.startsWith(ROOT ~ `\`));
	return "chm" ~ s[ROOT.length..$];
}
/*
bool ignoreNav(string href)
{
	return
		href=="bugstats.php" ||
		href=="sitemap.html" ||
		href.contains("://");
}
*/
// ********************************************************************

class Nav
{
	string title, url;
	Nav[] children;

	this(string title, string url)
	{
		this.title = title;
		this.url   = url;
	}

	Nav findOrAdd(string title, string url)
	{
		title = title.strip();
		foreach (child; children)
			if (child.title == title)
				return child;
		auto child = new Nav(title, url);
		children ~= child;
		return child;
	}
}

Nav nav;
class Page
{
	string newFileName;
	string title;
	string src;
//	bool[string] anchors;
}
/*
struct KeyLink
{
	string anchor;
	string title;

	this(string anchor, string title)
	{
		this.anchor = anchor.strip();
		this.title  = title.strip();
	}
}
*/
// ********************************************************************
Page[string] pages;
/*
KeyLink[string][string] keywords;   // keywords[keyword][original url w/o anchor] = anchor/title
string[string] keyTable;
*/
/*
void addKeyword(string keyword, string link, string title = null)
{
	keyword = keyword.strip();
	string file = link.removeAnchor();
	file = file.backSlash();
	string anchor = link.getAnchor();

	if (!title && keyword in keywords && file in keywords[keyword])   // when title is present, it overrides any existing anchors/etc.
	{
		if (keywords[keyword][file].anchor > anchor) // "less" is better
			keywords[keyword][file] = KeyLink(anchor, title);
	}
	else
		keywords[keyword][file] = KeyLink(anchor, title);

	if (title && keyword in keyTable)
	{
		if (keyTable[keyword] > keyword) // "less" is better
			keyTable[keyword] = keyword;
	}
	else
		keyTable[keyword] = keyword;
}
*/

Regex!char re(string pattern, alias flags = [])()
{
	static Regex!char r;
	if (r.empty)
		r = regex(pattern, flags);
	return r;
}

void main()
{
	// clean up
	if (exists("chm"))
		rmdirRecurse("chm");
	mkdir("chm");

	enforce(exists(ROOT ~ `\phobos\index.html`),
		"Phobos documentation not present. Please place Phobos documentation HTML files into the \"phobos\" subdirectory.");

	string[] files = chain(
		dirEntries(ROOT            , "*.html", SpanMode.shallow),
		dirEntries(ROOT ~ "/phobos", "*.html", SpanMode.shallow),
		dirEntries(ROOT ~ "/js"              , SpanMode.shallow),
		dirEntries(ROOT ~ "/css"             , SpanMode.shallow),
		dirEntries(ROOT ~ "/images"          , SpanMode.shallow),
		only(ROOT ~ "/favicon.ico")
	).array();

/*
	auto re_title        = regex(`<title>(.*) - (The )?D Programming Language( [0-9]\.[0-9])? - Digital Mars</title>`);
	auto re_title2       = regex(`<title>(Digital Mars - The )?D Programming Language( [0-9]\.[0-9])? - (.*)</title>`);
	auto re_title3       = regex(`<h1>(.*)</h1>`);
	auto re_heading      = regex(`<h2>(.*)</h2>`);
	auto re_heading_link = regex(`<h2><a href="([^"]*)"( title="([^"]*)")?>(.*)</a></h2>`);
	auto re_nav_link     = regex(`<li><a href="([^"]*)"( title="(.*)")?>(.*)</a>`);
	auto re_anchor_1     = regex(`<a name="\.?([^"]*)">(<\w{1,2}>)*([^<]+)<`);
	auto re_anchor_2     = regex(`<a name=([^">]*)>(<\w{1,2}>)*([^<]+)<`);
	auto re_anchor_1h    = regex(`<a name="\.?([^"]*)"`);
	auto re_anchor_2h    = regex(`<a name=([^">]*)>`);
	auto re_link         = regex(`<a href="([^"]*)">(<\w{1,2}>)*([^<]+)<`);
	auto re_link_pl      = regex(`<li><a href="(http://www.digitalmars.com/d)?/?(\d\.\d)?/index.html" title="D Programming Language \d\.\d">`);
	auto re_def          = regex(`<dt><big>(.*)<u>([^<]+)<`);
	auto re_css_margin   = regex(`margin-left:\s*1[35]em;`);
	auto re_res_path     = regex(`<(img|script) src="/([^/])`);
	auto re_extern_js    = regex(`<script src=['"]((https?:)?//[^'"]+)['"]`);
*/
	nav = new Nav(null, null);

	foreach (fileName; files)
		with (pages[fileName] = new Page)
		{
			scope(failure) stderr.writeln("Error while processing file: ", fileName);

			newFileName = fileName.adjustPath();
			newFileName.dirName().mkdirRecurse();

			if (fileName.endsWith(`.html`))
			{
				stderr.writeln("Processing ", fileName);
				src = fileName.readText();
				string[] lines = src.splitLines();
				string[] newlines = null;
//				bool skip, innavblock, intoctop;
//				int dl = 0;
//				anchors[""] = true;

				Nav[] navStack = [nav];
				if (fileName.startsWith(ROOT ~ `\phobos\`))
				{
					navStack ~= navStack[$-1].findOrAdd("Documentation", null);
					navStack ~= navStack[$-1].findOrAdd("Library Reference", `chm\phobos\index.html`);
					navStack ~= navStack[$-1].findOrAdd(null, null);
				}
				else
					navStack ~= null;
				bool foundNav = false;

				foreach (origLine; lines)
				{
					scope(failure) stderr.writeln("Error while processing line: ", origLine);
					string line = origLine;
				//	bool nextSkip = skip;

				//	if (line.test(re_link_pl))
				//		continue; // don't process link as well

				//	if (line.test(re_title))
				//	{
				//		title = strip(/*re_title*/match.captures[1]);
				//		line = line.replace(re_title, `<title>` ~ title ~ `</title>`);
				//	}
				//	if (line.test(re_title2))
				//	{
				//		title = strip(/*re_title2*/match.captures[3]);
				//		line = line.replace(re_title2, `<title>` ~ title ~ `</title>`);
				//	}
				//	if (line.test(re_title3))
				//		if (title=="")
				//			title = strip(/*re_title2*/match.captures[1]);
					RegexMatch!string m;
					if (!!(m = line.match(re!`^<title>.* - D Programming Language</title>$`)))
						title = m.captures[1];

				//	if (line.test(re_anchor_1h))
				//	{
				//		auto anchor = '#' ~ /*re_anchor*/match.captures[1];
				//		anchors[anchor] = true;
				//	}
				//	else
				//	if (line.test(re_anchor_2h))
				//	{
				//		auto anchor = '#' ~ /*re_anchor_2*/match.captures[1];
				//		anchors[anchor] = true;
				//	}

				//	if (line.contains(`<div id="navigation"`))
				//		innavblock = true;
				//	else
				//	if (line.contains(`<!--/navigation-->`))
				//		innavblock = false;
				//	if (line.contains(`<div id="toctop"`))
				//		intoctop = true;
				//	else
				//	if (intoctop && line.contains(`</div>`))
				//		intoctop = false;

				/+
					if (innavblock && !intoctop)
					{
						if (line.contains("<ul>"))
							navStack ~= null;
						else
						if (line.contains("</ul>"))
							navStack = navStack[0..$-1];

						void doLink(string title, string url)
						{
							if (ignoreNav(url))
								return;
							if (url)
							{
								url = absoluteUrl(fileName, url);
								if (url == fileName)
									foundNav = true;
								url = url.adjustPath();
							}
							navStack[$-1] = navStack[$-2].findOrAdd(title, url);
						}

						if (line.test(re_heading_link))
							doLink(match.captures[4], match.captures[1]);
						else
						if (line.test(re_heading))
							doLink(match.captures[1], null);
						else
						if (line.test(re_nav_link))
							doLink(match.captures[4], match.captures[1]);
					}

					if (line.contains(`<dl>`))
						dl++;
					if (dl==1)
					{
						if (line.test(re_def))
						{
							auto anchor = /*re_def*/match.captures[2];
							while ("#"~anchor in anchors) anchor ~= '_';
							anchors["#"~anchor] = true;
							//line = match.pre ~ line.replace(re_def, `<dt><big>$1<u><a name="` ~ anchor ~ `">$2</a><`) ~ match.post;
							line = line.replace(re_def, `<dt><big>$1<u><a name="` ~ anchor ~ `">$2</a><`);
							//writeln("new line: ", line);
							addKeyword(/*re_def*/match.captures[2], fileName ~ "#" ~ anchor);
						}
					}
					if (line.contains(`</dl>`))
						dl--;
				+/

					if (line.test(re_anchor_1))
						addKeyword(/*re_anchor*/match.captures[3], fileName ~ "#" ~ /*re_anchor*/match.captures[1]);
					else
					if (line.test(re_anchor_2))
						addKeyword(/*re_anchor_2*/match.captures[3], fileName ~ "#" ~ /*re_anchor_2*/match.captures[1]);
					else
					if (line.test(re_anchor_1h))
						addKeyword(/*re_anchor*/match.captures[1], fileName ~ "#" ~ /*re_anchor*/match.captures[1]);
					else
					if (line.test(re_anchor_2h))
						addKeyword(/*re_anchor_2*/match.captures[1], fileName ~ "#" ~ /*re_anchor_2*/match.captures[1]);

					if (line.test(re_link))
						if (!/*re_link*/match.captures[1].startsWith("http://"))
							addKeyword(/*re_link*/match.captures[3], absoluteUrl(fileName, /*re_link*/match.captures[1]));

					// skip "digg this"
					if (line.contains(`<script src="http://digg.com/tools/diggthis.js"`))
						skip = true;

					while (!skip && line.test(re_extern_js))
					{
						auto url = match.captures[1].replace(`\`, `/`);
						auto fn = url.split("?")[0].split("/")[$-1];
						auto dst = "chm/js/" ~ fn;

						if (!dst.exists)
						{
							writefln("Downloading %s to %s...", url, dst);
							import std.net.curl, etc.c.curl;
							auto http = HTTP();
							http.handle.set(CurlOption.ssl_verifypeer, false); // curl's default SSL trusted root certificate store is outdated/incomplete
							if (!dst.dirName().exists) dst.dirName().mkdirRecurse();
							std.file.write(dst, get(url, http));
						}

						line = line.replace(url, "/js/" ~ fn);
					}

					while (line.test(re_res_path))
						line = line.replace(match.captures[0], `<` ~ match.captures[1] ~ ` src="` ~ "../".replicate(fileName[ROOT.length+1..$].split(dirSeparator).length-1) ~ match.captures[2]);

					// skip Google ads
					if (line.startsWith(`<!-- Google ad -->`))
						skip = nextSkip = true;
					if (line == `</script>`)
						nextSkip = false;

					// skip header / navigation bar
					if (line.contains(`<body`))
					{
						line = `<body class="chm">`;
						nextSkip = true;
					}
					if (line.contains(`<div id="content"`))
						skip = nextSkip = false;

					if (!skip)
						newlines ~= line;
					skip = nextSkip;

					// Work around JS bug in run.js
					if (line.contains(`<head`))
						newlines ~= `<script>mainPage = [];</script>`;
				}

				if (!foundNav)
					writeln("Warning: Page not found in navigation");

				src = join(newlines, std.ascii.newline[]);
				std.file.write(newFileName, src);
			}
			else
			if (fileName.endsWith(`.css`))
			{
				writeln("Processing "~fileName);
				src = readText(fileName);
				string[] lines = splitLines(src);
				string[] newlines = null;
				foreach (line;lines)
				{
					// skip #div.content positioning
					if (!line.test(re_css_margin))
						newlines ~= line;
				}
				src = join(newlines, std.ascii.newline[]);
				std.file.write(newFileName, src);
			}
			else
			{
				writeln("Copying "~fileName);
				copy(fileName, newFileName);
			}
		}

	// ************************************************************

	// retreive keyword link titles
	foreach (keyNorm, urls; keywords)
		foreach (url, ref link; urls)
			if (url in pages)
				link.title = pages[url].title;

	// ************************************************************

	auto f = File("d.hhp", "wt");
	f.writeln(
`[OPTIONS]
Binary Index=No
Compatibility=1.1 or later
Compiled file=d.chm
Contents file=d.hhc
Default Window=main
Default topic=chm\index.html
Display compile progress=No
Full-text search=Yes
Index file=d.hhk
Language=0x409 English (United States)
Title=D

[WINDOWS]
main="D Programming Language","d.hhc","d.hhk","chm\index.html","chm\index.html",,,,,0x63520,,0x380e,[0,0,800,570],0x918f0000,,,,,,0

[FILES]`);
	string[] htmlList;
	foreach (page;pages)
		if (page.newFileName.endsWith(`.html`))
			htmlList ~= page.newFileName;
	htmlList.sort;
	foreach (s; htmlList)
		f.writeln(s);
	f.writeln(`
[INFOTYPES]`);
	f.close();

	// ************************************************************

	void dumpNav(Nav nav, int level=0)
	{
		if (nav.title && (nav.url || nav.children.length))
		{
			auto t = "\t".replicate(level);
			f.writeln(t,
				`<LI><OBJECT type="text/sitemap">`
				`<param name="Name" value="`, nav.title, `">`
				`<param name="Local" value="`, nav.url, `">`
				`</OBJECT>`);
			if (nav.children.length)
			{
				f.writeln(t, `<UL>`);
				foreach (child; nav.children)
					dumpNav(child, level+1);
				f.writeln(t, `</UL>`);
			}
		}
		else
		foreach (child; nav.children)
			dumpNav(child, level);
	}

	f.open("d.hhc", "wt");
	f.writeln(
`<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN"><HTML><BODY>
<OBJECT type="text/site properties"><param name="Window Styles" value="0x800025"></OBJECT>
<UL>`);
	dumpNav(nav);
	f.writeln(`</UL>
</BODY></HTML>`);
	f.close();

	// ************************************************************

	string[] keywordList;
	foreach (keyNorm,urlList;keywords)
		keywordList ~= keyNorm;
	//keywordList.sort;
	sort!q{icmp(a, b) < 0}(keywordList);

	f.open("d.hhk", "wt");
	f.writeln(
`<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN"><HTML><BODY>
<UL>`);
	foreach (keyNorm;keywordList)
	{
		auto urlList = keywords[keyNorm];
		f.writeln(
`	<LI> <OBJECT type="text/sitemap">
		<param name="Name" value="`, keyTable[keyNorm], `">`);
		foreach (url,link;urlList)
			if (url in pages)
			{
				f.writeln(
`		<param name="Name" value="`, link.title, `">
		<param name="Local" value="`, adjustPath(url), link.anchor, `">`);
			}
		f.writeln(
`		</OBJECT>`);
	}
	f.writeln(
`</UL>
</BODY></HTML>`);
	f.close();
}
