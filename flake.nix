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
        rebar3Lib = nix-rebar3.lib.${system}.override {
          erlang = beamPkgs.erlang;
          rebar3 = beamPkgs.rebar3;
        };
        n2c = nix2container.packages.${system}.nix2container;

        appName = "don_erleone";
        otpName = "don_erleone"; 
        version = "0.1.0";

        erlApp = rebar3Lib.buildRebar3 {
          pname = appName;
          inherit version;
          root = ./.;
          releaseType = "release";
          profile = "prod";

          singleStep = true;
          dontFixup = true;

          preInstall = ''
            export HOME=$TEMPDIR
          '';
        };

        containerImage = n2c.buildImage {
          name = appName;
          tag = "latest";
          config = {
            Entrypoint = [ "${erlApp}/bin/${appName}" "foreground" ];
            WorkingDir = "/tmp";
            user = "1000";
          };
        };

        run-foreground-binary = pkgs.writeShellScriptBin "run-foreground-binary" ''
          exec ${erlApp}/bin/${appName} foreground "$@"
        '';
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
            program = "${run-foreground-binary}/bin/run-foreground-binary";
          };
          load-image = {
            type = "app";
            program = "${containerImage.copyToDockerDaemon}/bin/copy-to-docker-daemon";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            beamPkgs.erlang  # Uses the variable defined above
            beamPkgs.rebar3
            beamPkgs.erlfmt
            pkgs.inotify-tools
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