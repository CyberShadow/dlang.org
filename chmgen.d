// D HTML to CHM converter/generator
// By Vladimir Panteleev <vladimir@thecybershadow.net> (2007-2011)
// Placed in the Public Domain
// Written in the D Programming Language, version 2

import std.algorithm;
//import std.array;
//import std.ascii;
import std.exception;
import std.file;
import std.range;
import std.stdio : File, stderr;
import std.string;
import std.regex;
import std.path;

//alias std.ascii.newline newline;

enum ROOT = `.`;

// ********************************************************************

string fixSlashes(string s)
{
	return s.replace(`/`, `\`);
}

/*
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

string stripAnchor(string s)
{
	int i = s.indexOf('#');
	return i<0 ? s : s[0..i];
}
*/

string getAnchor(string s)
{
	return s.findSplitBefore("#")[1];
}

string stripAnchor(string s)
{
	return s.findSplit("#")[0];
}

string absoluteUrl(string base, string url)
{
	if (url.canFind("://"))
		return url;

	base = base.fixSlashes();
	url  = url.fixSlashes();
	enforce(url.length, "Empty URL");

	if (url[0]=='#')
		return base ~ url;

	auto pathSegments = base.length ? base.split(`\`)[0..$-1] : null;
	auto urlSegments = url.split(`\`);

	while (urlSegments.startsWith([`..`]))
	{
		urlSegments = urlSegments[1..$];
		pathSegments = pathSegments[0..$-1];
	}
	return (pathSegments ~ urlSegments).join(`\`);
}

/*
string adjustPath(string s)
{
	if (s.startsWith(ROOT ~ `/`))
		s = "chm" ~ s[ROOT.length..$];
	return s;
}
*/
string adjustPath(string s, string prefix)
{
	enforce(s.startsWith(ROOT ~ `\`), "Bad path: " ~ s);
	return prefix ~ s[ROOT.length..$];
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
	string fileName, title, src;
}

struct KeyLink
{
	string anchor, title;

	this(string anchor, string title)
	{
		this.anchor = anchor.strip();
		this.title  = title.strip();
	}
}

Nav loadNav(string fileName, string base)
{
	import std.json;
	auto json = fileName
		.readText()
		.replace("\r", "")
		.replace("\n", "")
		.replaceAll(re!`,\s*\]`, "]")
		.parseJSON();

	Nav parseNav(JSONValue json)
	{
		if (json.type == JSON_TYPE.ARRAY)
		{
			auto nodes = json.array;
			auto root = parseNav(nodes[0]);
			root.children = nodes[1..$].map!parseNav.filter!`a`.array();
			return root;
		}
		else
		{
			auto obj = json.object;
			auto title = obj["t"].str.strip();
			string url;
			if ("a" in obj)
			{
				url = absoluteUrl(base, obj["a"].str.strip());
				if (url.canFind(`://`))
				{
					stderr.writeln("Skipping non-existing navigation item: " ~ url);
					return null;
				}
				else
				{
					if (!exists(`chm\files\` ~ url))
					{
						stderr.writeln("Skipping non-existing navigation item: " ~ url);
						//url = "http://dlang.org/" ~ url;
						return null;
					}
					else
						url = `files\` ~ url;
				}
			}
			return new Nav(title, url);
		}
	}

	return parseNav(json);
}

// ********************************************************************

Page[string] pages;
KeyLink[string][string] keywords;   // keywords[keyword][original url w/o anchor] = anchor/title
string[string] keyTable;

void addKeyword(string keyword, string link, string title = null)
{
	keyword = keyword.strip();
	string file = link.stripAnchor();
	file = file.fixSlashes();
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

Regex!char re(string pattern, alias flags = [])()
{
	static Regex!char r;
	if (r.empty)
		r = regex(pattern, flags);
	return r;
}

void main()
{
	if (exists(`chm`))
		rmdirRecurse(`chm`);
	mkdirRecurse(`chm\files`);

	enforce(exists(ROOT ~ `\phobos\index.html`),
		`Phobos documentation not present. Please place Phobos documentation HTML files into the "phobos" subdirectory.`);

	string[] files = chain(
		dirEntries(ROOT ~ `\`       , "*.html", SpanMode.shallow),
		dirEntries(ROOT ~ `\phobos\`, "*.html", SpanMode.shallow),
	//	dirEntries(ROOT ~ `\js\`              , SpanMode.shallow),
		dirEntries(ROOT ~ `\css\`             , SpanMode.shallow),
		dirEntries(ROOT ~ `\images\`, "*.*"   , SpanMode.shallow),
		only(ROOT ~ `\favicon.ico`)
	).array();

/*
	auto re_title        = regex(`<title>(.*) - (The )?D Programming Language( [0-9]\.[0-9])? - Digital Mars</title>`);
	auto re_title2       = regex(`<title>(Digital Mars - The )?D Programming Language( [0-9]\.[0-9])? - (.*)</title>`);
	auto re_title3       = regex(`<h1>(.*)</h1>`);
	auto re_heading      = regex(`<h2>(.*)</h2>`);
	auto re_heading_link = regex(`<h2><a href="([^"]*)"( title="([^"]*)")?>(.*)</a></h2>`);
	auto re_nav_link     = regex(`<li><a href="([^"]*)"( title="(.*)")?>(.*)</a>`);
	auto re_anchor_1     = regex(`<a name="\.?([^"]*)">(<\w{1,2}>)*([^<]+)<`);
	auto re_anchor_1h    = regex(`<a name="\.?([^"]*)"`);
	auto re_link         = regex(`<a href="([^"]*)">(<\w{1,2}>)*([^<]+)<`);
	auto re_link_pl      = regex(`<li><a href="(http://www.digitalmars.com/d)?/?(\d\.\d)?/index.html" title="D Programming Language \d\.\d">`);
	auto re_def          = regex(`<dt><big>(.*)<u>([^<]+)<`);
	auto re_css_margin   = regex(`margin-left:\s*1[35]em;`);
	auto re_res_path     = regex(`<(img|script) src="/([^/])`);
	auto re_extern_js    = regex(`<script src=['"]((https?:)?//[^'"]+)['"]`);
*/
	foreach (fileName; files)
		//with (pages[fileName] = new Page)
		{
			scope(failure) stderr.writeln("Error while processing file: ", fileName);
			auto page = pages[fileName] = new Page;
			page.fileName = fileName[ROOT.length+1 .. $];

			auto newFileName = fileName.adjustPath(`chm\files`);
			newFileName.dirName().mkdirRecurse();

			if (fileName.endsWith(`.html`))
			{
				stderr.writeln("Processing ", fileName);
				auto lines = fileName.readText().splitLines();
//				string[] newlines = null;
//				bool skip, innavblock, intoctop;
//				int dl = 0;
//				anchors[""] = true;

			//	Nav[] navStack = [nav];
			//	if (fileName.startsWith(ROOT ~ `\phobos\`))
			//	{
			//		navStack ~= navStack[$-1].findOrAdd("Documentation", null);
			//		navStack ~= navStack[$-1].findOrAdd("Library Reference", `files\phobos\index.html`);
			//		navStack ~= navStack[$-1].findOrAdd(null, null);
			//	}
			//	else
			//		navStack ~= null;

				bool foundBody, redirect;

				foreach (ref line; lines)
				{
					scope(failure) stderr.writeln("Error while processing line: ", line);

					// Fix links

					line = line.replace(`<a href="."`, `<a href="index.html"`);
					line = line.replace(`<a href=".."`, `<a href="..\index.html"`);

				//	string line = origLine;
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

					// Find title

					if (!!(m = line.match(re!`^<title>(.*) - D Programming Language</title>$`)))
						page.title = m.captures[1];

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

					// Add document CSS class

					if (!!(m = line.match(re!`^(<body id='.*' class='.*)('>)$`)))
					{
						line = m.captures[1] ~ " chm" ~ m.captures[2];
						foundBody = true;
					}

					if (line.match(re!`^<meta http-equiv="Refresh" content="0; URL=`))
						redirect = true;

					// Find anchors

					if (!!(m = line.match(re!`<a name="(\.?[^"]*)">(<\w{1,2}>)*([^<]+)<`)))
						addKeyword(m.captures[3], fileName ~ "#" ~ m.captures[1]);
					else
					if (!!(m = line.match(re!`<a name="(\.?([^"]*))">`)))
						addKeyword(m.captures[2], fileName ~ "#" ~ m.captures[1]);

					if (!!(m = line.match(re!`<a href="([^"]*)">(<\w{1,2}>)*([^<]+)<`)))
						if (!m.captures[1].canFind("://"))
							addKeyword(m.captures[3], absoluteUrl(fileName, m.captures[1]));

					// Disable scripts

					if (line.match(`<script.*</script>`) || line.match(`<script.*\bsrc=`))
						line = null;

				/+
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
				+/
				}

				enforce(foundBody || redirect, "Body not found");

			//	if (!foundNav)
			//		stderr.writeln("Warning: Page not found in navigation");

			//	src = join(newlines, std.ascii.newline[]);
				page.src = lines.join("\r\n");
				std.file.write(newFileName, page.src);
			}
		/*
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
		*/
			else
			{
				stderr.writeln("Copying ", fileName);
				copy(fileName, newFileName);
			}
		}

	nav = loadNav("chm-nav-doc.json", ``);

	// ************************************************************

	// retreive keyword link titles
	foreach (keyNorm, urls; keywords)
		foreach (url, ref link; urls)
			if (url in pages)
				link.title = pages[url].title;

	// ************************************************************

	auto f = File(`chm\d.hhp`, "wt");
	f.writeln(
`[OPTIONS]
Binary Index=No
Compatibility=1.1 or later
Compiled file=d.chm
Contents file=d.hhc
Default Window=main
Default topic=files\index.html
Display compile progress=No
Full-text search=Yes
Index file=d.hhk
Language=0x409 English (United States)
Title=D

[WINDOWS]
main="D Programming Language","d.hhc","d.hhk","files\index.html","files\index.html",,,,,0x63520,,0x380e,[0,0,800,570],0x918f0000,,,,,,0

[FILES]`);
	string[] htmlList;
	foreach (page;pages)
		if (page.fileName.endsWith(`.html`))
			htmlList ~= `files\` ~ page.fileName;
	htmlList.sort();
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

	f.open(`chm\d.hhc`, "wt");
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
	foreach (keyNorm, urlList; keywords)
		keywordList ~= keyNorm;
	//keywordList.sort;
	keywordList.sort!q{icmp(a, b) < 0};

	f.open(`chm\d.hhk`, "wt");
	f.writeln(
`<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN"><HTML><BODY>
<UL>`);
	foreach (keyNorm; keywordList)
	{
		auto urlList = keywords[keyNorm];
		f.writeln(
`	<LI> <OBJECT type="text/sitemap">
		<param name="Name" value="`, keyTable[keyNorm], `">`);
		foreach (url, link; urlList)
			if (url in pages)
			{
				f.writeln(
`		<param name="Name" value="`, link.title, `">
		<param name="Local" value="`, adjustPath(url, `files`), link.anchor, `">`);
			}
		f.writeln(
`		</OBJECT>`);
	}
	f.writeln(
`</UL>
</BODY></HTML>`);
	f.close();
}
