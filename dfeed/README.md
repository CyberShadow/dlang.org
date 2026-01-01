# DFeed Configuration for forum.dlang.org

This directory contains the site-specific configuration for running DFeed
as [forum.dlang.org](https://forum.dlang.org/).

## Quick Start

```bash
git clone --recursive https://github.com/CyberShadow/DFeed.git
cd DFeed

# Clone dlang.org into the site directory
git clone https://github.com/dlang/dlang.org.git site/web/static/dlang.org

# Build and install using Nix
./site/web/static/dlang.org/dfeed/rebuild-nix

# Configure NNTP source
mkdir -p site/config/sources/nntp
echo "host = news.digitalmars.com" > site/config/sources/nntp/digitalmars.ini

# Run
./dfeed
```

On first start, DFeed downloads messages from the NNTP server.
Stop at any time if you don't need the full archive.
Access the web interface at http://localhost:8080/.

## Building

The `rebuild-nix` script builds both the main DFeed application and the
dlang.org site resources (forum template, minified CSS/JS, groups.ini).

```bash
./site/web/static/dlang.org/dfeed/rebuild-nix
```

## Deployment

### Beta Instance (beta.forum.dlang.org)

```bash
git push -v --force-with-lease github next && ssh dfeed-beta@k3.1azy.net DFeed/site/web/static/dlang.org/dfeed/update-beta
```

### Production Instance (forum.dlang.org)

```bash
git push -v github github/next:master && ssh dfeed@k3.1azy.net DFeed/site/web/static/dlang.org/dfeed/update
```

## Files

| File | Purpose |
|------|---------|
| [`flake.nix`](flake.nix) | Nix flake for building forum resources |
| [`gengroups.d`](gengroups.d) | Generates `groups.ini` with D forum/mailing list configuration |
| [`rebuild-nix`](rebuild-nix) | Build script using Nix flakes |
| [`update`](update) | Pull and deploy (stable branch) |
| [`update-beta`](update-beta) | Reset to next branch and deploy |
| [`restart`](restart) | Restart the dfeed process |
| | |
| [`../forum-template.dd`](../forum-template.dd) | Page template (compiled to `skel.htt`) |
| [`../css/style.css`](../css/style.css) | Main stylesheet |
| [`../js/dlang.js`](../js/dlang.js) | Main JavaScript |
| [`../dlang.org.ddoc`](../dlang.org.ddoc) | DDOC macros for site-wide styling |

## Flake

The `flake.nix` in this directory builds:
- `groups.ini` from `gengroups.d`
- `forum-template.html` from dlang.org DDOC macros
- Minified CSS and JS files

It uses a non-flake input (`dlang-org-src`) to access the parent dlang.org
directory. The `rebuild-nix` script overrides this input at build time.
