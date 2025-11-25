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
| `gengroups.d` | Generates `groups.ini` with D forum/mailing list configuration |
| `rebuild-nix` | Build script using Nix flakes |
| `update` | Pull and deploy (stable branch) |
| `update-beta` | Reset to next branch and deploy |
| `restart` | Restart the dfeed process |

## Flake

The parent directory (`dlang.org/`) contains `flake.nix` which builds:
- `groups.ini` from `gengroups.d`
- `forum-template.html` from dlang.org DDOC macros
- Minified CSS and JS files
