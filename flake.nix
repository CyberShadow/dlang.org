{
  description = "DFeed site configuration for forum.dlang.org";

  inputs = {
    # Reference to the main DFeed flake (4 levels up from this flake)
    dfeed.url = "path:../../../..";
    # Follow dfeed's nixpkgs to use its locked version
    nixpkgs.follows = "dfeed/nixpkgs";
    flake-utils.follows = "dfeed/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, dfeed }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Get the DFeed package from the main flake
        dfeedPkg = dfeed.packages.${system}.default;

        # Helper to download compressors
        htmlcompressor = pkgs.fetchurl {
          url = "https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/htmlcompressor/htmlcompressor-1.5.3.jar";
          sha256 = "1ydh1hqndnvw0d8kws5339mj6qn2yhjd8djih27423nv1hrlx2c8";
        };

        yuicompressor = pkgs.fetchurl {
          url = "https://github.com/yui/yuicompressor/releases/download/v2.4.8/yuicompressor-2.4.8.jar";
          sha256 = "1qjxlak9hbl9zd3dl5ks0w4zx5z64wjsbk7ic73r1r45fasisdrh";
        };

      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "dfeed-dlang-site";
          version = "unstable";

          # Use self to get only git-tracked files from the dlang.org repo
          src = self;

          nativeBuildInputs = with pkgs; [
            dmd
            dtools  # Provides rdmd
            jre_minimal  # For htmlcompressor and yuicompressor
          ];

          # Setup build environment
          preConfigure = ''
            # Make compressors available
            cp ${htmlcompressor} htmlcompressor-1.5.3.jar
            cp ${yuicompressor} yuicompressor-2.4.8.jar
          '';

          buildPhase = ''
            runHook preBuild

            export DCOMPILER=dmd

            # Build groups.ini from gengroups.d
            if [ -f dfeed/gengroups.d ]; then
              echo "Generating groups.ini..."
              mkdir -p sources/mailman
              rdmd --compiler=dmd dfeed/gengroups.d
            fi

            # Build forum-template.html from DDOC
            # The DDOC macros are in the dlang.org repo
            DDOC_FILES="macros.ddoc html.ddoc dlang.org.ddoc windows.ddoc doc.ddoc"
            DDOC_ARGS=""
            for f in $DDOC_FILES; do
              if [ -f "$f" ]; then
                DDOC_ARGS="$DDOC_ARGS $f"
              fi
            done

            if [ -f forum-template.dd ] && [ -n "$DDOC_ARGS" ]; then
              echo "Building forum-template.html..."
              dmd -o- -c -D $DDOC_ARGS forum-template.dd -Dfforum-template.html || true
            fi

            # Minify dlang.org CSS/JS
            JSTOOL="java -jar yuicompressor-2.4.8.jar --type js"
            CSSTOOL="java -jar yuicompressor-2.4.8.jar --type css"

            for css in css/*.css; do
              [[ "$css" == *.min.css ]] && continue
              [ -f "$css" ] || continue
              min="''${css%.css}.min.css"
              echo "Minifying $css..."
              $CSSTOOL < "$css" > "$min" 2>/dev/null || cp "$css" "$min"
            done

            for js in js/*.js; do
              [[ "$js" == *.min.js ]] && continue
              [ -f "$js" ] || continue
              min="''${js%.js}.min.js"
              echo "Minifying $js..."
              $JSTOOL < "$js" > "$min" 2>/dev/null || cp "$js" "$min"
            done

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            # Create site/ directory structure
            mkdir -p $out/site/config
            mkdir -p $out/site/web/static/dlang.org/css
            mkdir -p $out/site/web/static/dlang.org/js
            mkdir -p $out/site/web/static/dlang.org/images

            # Install groups.ini
            if [ -f groups.ini ]; then
              cp groups.ini $out/site/config/
            fi

            # Install mailman config
            if [ -f sources/mailman/puremagic.ini ]; then
              mkdir -p $out/site/config/sources/mailman
              cp sources/mailman/puremagic.ini $out/site/config/sources/mailman/
            fi

            # Install forum-template.html as skel.htt
            if [ -f forum-template.html ]; then
              cp forum-template.html $out/site/web/skel.htt
              cp forum-template.html $out/site/web/static/dlang.org/
            fi

            # Install minified CSS/JS
            cp -r css/*.min.css $out/site/web/static/dlang.org/css/ 2>/dev/null || true
            cp -r js/*.min.js $out/site/web/static/dlang.org/js/ 2>/dev/null || true

            # Install images and other static assets
            cp -r images/* $out/site/web/static/dlang.org/images/ 2>/dev/null || true

            # Copy gengroups.d for reference
            if [ -f dfeed/gengroups.d ]; then
              cp dfeed/gengroups.d $out/site/config/
            fi

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "DFeed site configuration for forum.dlang.org";
            license = licenses.boost;
            platforms = platforms.linux;
          };
        };

        # Also expose the main DFeed package
        packages.dfeed = dfeedPkg;
      }
    );
}
