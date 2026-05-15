{
  description = "Don Erleone - Supervised Agent Infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix2container.url = "github:nlewo/nix2container";
    just.url = "github:casey/just";
    nix-rebar3 = {
      url = "github:axelf4/nix-rebar3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, nix2container, just, nix-rebar3, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        beamPkgs = pkgs.beam.packages.erlang_28;
        n2c = nix2container.packages.${system}.nix2container;

        rebar3Lib = nix-rebar3.lib.${system}.override {
          erlang = beamPkgs.erlang;
          rebar3 = beamPkgs.rebar3;
        };

        appName = "don-erleone";
        releaseName = "don_erleone";
        version = "0.1.0";

        erlApp = rebar3Lib.buildRebar3 {
          pname = appName;
          inherit version;
          root = ./.;
          releaseType = "release";
          profile = "prod";
          singleStep = true;
          dontFixup = false;
          dontCheckForBrokenSymlinks = true;
          preInstall = ''
            export HOME=$TEMPDIR
          '';
        };

        relBinPath = "${erlApp}/bin/${releaseName}";

        run-script = pkgs.writeShellScriptBin "don-erleone-runner" ''
          set -e

          export RELEASE_TMP=''${RELEASE_TMP:-/tmp}
          export RELEASE_MUTABLE_DIR=''${RELEASE_MUTABLE_DIR:-/tmp}
          export RELX_OUT_FILE_PATH=''${RELEASE_TMP}

          export RELEASE_NODE=''${RELEASE_NODE:-don_erleone@127.0.0.1}
          export RELEASE_COOKIE=''${RELEASE_COOKIE:-agentic_brain_secret}
          export RELX_REPLACE_OS_VARS=true
          
          # 2. Start EPMD using the stripped binary bundled INSIDE the release 
          echo "=> Starting EPMD..."

          EPMD_BIN=$(find ${erlApp} -path "*/erts-*/bin/epmd" -type f | head -n 1)
          
          if [ -x "$EPMD_BIN" ]; then
             "$EPMD_BIN" -daemon || true
          else
             echo "=> Warning: Bundled epmd not found. The node will attempt to start it."
          fi

          # 3. Boot the app
          COMMAND=''${1:-foreground}
          shift || true
          echo "=> Booting ${appName}..."
          exec ${relBinPath} "$COMMAND" "$@"
        '';

        emptyTmp = pkgs.runCommand "empty-tmp" { } "mkdir -p $out/tmp";

        containerImage = n2c.buildImage {
          name = appName;
          tag = "latest";

          layers = [
            (n2c.buildLayer {
              deps = [
                (pkgs.busybox.override { enableAppletSymlinks = true; })
                pkgs.glibc
                erlApp
              ];
              copyToRoot = [ emptyTmp ];
              perms = [{
                path = emptyTmp;
                regex = ".*";
                mode = "1777";
              }];
            })
          ];

          config = {
            Entrypoint = [ "${run-script}/bin/don-erleone-runner" ];
            WorkingDir = "/data";
            ExposedPorts = {
              "4369/tcp" = {}; # EPMD
              "8080/tcp" = {}; # API
            };
            User = "1000";
            Env = [
              "HOME=/data"
              "MNESIA_DIR=/data/mnesia"
              "PATH=${pkgs.busybox}/bin"
            ];
          };
        };
      in
      {
        formatter = pkgs.nixpkgs-fmt;

        packages = {
          default = erlApp;
          image = containerImage;
        };

        apps = {
          default = {
            type = "app";
            program = "${run-script}/bin/don-erleone-runner";
          };
          load-image = {
            type = "app";
            program = "${containerImage.copyToDockerDaemon}/bin/copy-to-docker-daemon";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            beamPkgs.erlang
            beamPkgs.rebar3
            beamPkgs.erlfmt
            pkgs.just
          ];

          shellHook = ''
            export REBAR3_CACHE_DIR=$PWD/.nix-rebar3
            export PATH=$PWD/_build/default/bin:$PATH
            
            # ANSI Color Codes
            BOLD="\033[1m"
            CYAN="\033[36m"
            GREEN="\033[32m"
            RESET="\033[0m"

            OTP_VER=$(erl -noshell -eval 'io:fwrite("~s", [erlang:system_info(otp_release)]), halt().')

            echo -e "\n''${BOLD}''${CYAN}--- ${appName} Dev Shell (OTP ''${OTP_VER}) ---''${RESET}"
            echo -e "''${GREEN}✔''${RESET} Cache:  ''${BOLD}.nix-rebar3''${RESET}"
            echo -e "''${GREEN}✔''${RESET} Status: ''${BOLD}The Don is Open''${RESET}\n"
          '';
        };
      });
}
