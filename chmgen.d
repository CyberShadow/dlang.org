// D HTML to CHM converter/generator
// By Vladimir Panteleev <vladimir@thecybershadow.net> (2007-2015)
// Placed in the Public Domain
// Written in the D Programming Language, version 2

import std.algorithm;
import std.exception;
import std.file;
import std.range;
import std.stdio : File, stderr;
import std.string;
import std.regex;
import std.path;

enum ROOT = `.`;

// ********************************************************************

string fixSlashes(string s)
{
	return s.replace(`/`, `\`);
}

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

string adjustPath(string s, string prefix)
{
	enforce(s.startsWith(ROOT ~ `\`), "Bad path: " ~ s);
	return prefix ~ s[ROOT.length..$];
}

// ********************************************************************

class Nav
{
	string title, url;
	Nav[] children;
}

class Page
{
	string fileName, title, src;
}

struct KeyLink
{
	string anchor, title;
}

Nav loadNav(string fileName, string base)
{
	import std.json;
	auto text = fileName
		.readText()
		.replace("\r", "")
		.replace("\n", "")
	//	.replaceAll(re!`/\*.*?\*/`, "")
		.replaceAll(re!`,\s*\]`, `]`)
	;
	scope(failure) std.file.write("error.json", text);
	auto json = text.parseJSON();

	Nav parseNav(JSONValue json)
	{
		if (json.type == JSON_TYPE.ARRAY)
		{
			auto nodes = json.array;
			auto root = parseNav(nodes[0]);
			root.children = nodes[1..$].map!parseNav.array().filter!`a`.array();
			return root;
		}
		else
		{
			auto obj = json.object;
			auto nav = new Nav;
			nav.title = obj["t"].str.strip();
			if ("a" in obj)
			{
				auto url = absoluteUrl(base, obj["a"].str.strip());
				if (url.canFind(`://`))
				{
					stderr.writeln("Skipping external navigation item: " ~ url);
					return null;
				}
				else
				if (!exists(`chm\files\` ~ url))
				{
					stderr.writeln("Skipping non-existent navigation item: " ~ url);
					//url = "http://dlang.org/" ~ url;
					return null;
				}
				else
					nav.url = `files\` ~ url;
			}
			return nav;
		}
	}

	return parseNav(json);
}

// ********************************************************************

Page[string] pages;
KeyLink[string][string] keywords;   // keywords[keyword][original url w/o anchor] = anchor/title
string[string] keyTable;

void addKeyword(string keyword, string link)
{
	keyword = keyword.strip();
	if (!keyword.length)
		return;
	link = link.strip();
	string file = link.stripAnchor().fixSlashes();
	string anchor = link.getAnchor();

	if (keyword !in keywords
	 || file !in keywords[keyword]
	 || keywords[keyword][file].anchor > anchor) // "less" is better
		keywords[keyword][file] = KeyLink(anchor);

	if (keyword !in keyTable
	 || keyTable[keyword] > keyword) // "less" is better
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

	foreach (fileName; files)
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

				bool foundBody, redirect;

				foreach (ref line; lines)
				{
					scope(failure) stderr.writeln("Error while processing line: ", line);

					RegexMatch!string m;

					// Find title

					if (!!(m = line.match(re!`^<title>(.*) - D Programming Language</title>$`)))
						page.title = m.captures[1];

					// Add document CSS class

					if (!!(m = line.match(re!`^(<body id='.*' class='.*)('>)$`)))
					{
						line = m.captures[1] ~ " chm" ~ m.captures[2];
						foundBody = true;
					}

					if (line.match(re!`^<meta http-equiv="Refresh" content="0; URL=`))
						redirect = true;

					// Fix links

					line = line.replace(`<a href="."`, `<a href="index.html"`);
					line = line.replace(`<a href=".."`, `<a href="..\index.html"`);

					// Find anchors

					enum attrs = `(?:(?:\w+=\"[^"]*\")?\s*)*`;
					enum name = `(?:name|id)`;
					if (!!(m = line.match(re!(`<a `~attrs~name~`="(\.?[^"]*)"`~attrs~`>(.*?)</a>`))))
						addKeyword(m.captures[2].replaceAll(re!`<.*?>`, ``), fileName ~ "#" ~ m.captures[1]);
					else
					if (!!(m = line.match(re!(`<a `~attrs~name~`="(\.?([^"]*?)(\.\d+)?)"`~attrs~`>`))))
						addKeyword(m.captures[2], fileName ~ "#" ~ m.captures[1]);
					//<a class="anchor" title="Permalink to this section" id="integerliteral" href="#integerliteral">Integer Literals</a>

					if (!!(m = line.match(re!(`<div class="quickindex" id="(quickindex\.(.+))"></div>`))))
						addKeyword(m.captures[2], fileName ~ "#" ~ m.captures[1]);

					if (!!(m = line.match(re!(`<a `~attrs~`href="([^"]*)"`~attrs~`>(.*?)</a>`))))
						if (!m.captures[1].canFind("://"))
							addKeyword(m.captures[2].replaceAll(re!`<.*?>`, ``), absoluteUrl(fileName, m.captures[1]));

					// Disable scripts

					line = line.replaceAll(re!`<script.*</script>`, ``);
					line = line.replaceAll(re!`<script.*\bsrc=`, ``);

					// Remove external stylesheets

					if (line.startsWith(`<link rel="stylesheet" href="http`))
						line = null;
				}

				enforce(foundBody || redirect, "Body not found");

				page.src = lines.join("\r\n");
				std.file.write(newFileName, page.src);
			}
			else
			{
				stderr.writeln("Copying ", fileName);
				copy(fileName, newFileName);
			}
		}

	// Load navigation

	auto nav = loadNav("chm-nav-doc.json", ``);
	auto phobosIndex = `files\phobos\index.html`;
	auto navPhobos = nav.children.find!(child => child.url == phobosIndex).front;
	auto phobos = loadNav("chm-nav-std.json", `phobos\`);
	navPhobos.children = phobos.children.filter!(child => child.url != phobosIndex).array();

	// Retreive keyword link titles

	foreach (keyNorm, urls; keywords)
		foreach (url, ref link; urls)
			if (url in pages)
				link.title = pages[url].title;

	// ************************************************************

	// Write project file

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

	// Write TOC file

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

	// Write index file

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

	// Done!
}
