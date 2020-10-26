# SPDX-FileCopyrightText: 2020 Serokell <https://serokell.io/>
#
# SPDX-License-Identifier: MPL-2.0

{
  description = "A Simple multi-profile Nix-flake deploy tool.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    naersk = {
      url = "github:nmattia/naersk/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, utils, naersk, ... }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        naersk-lib = pkgs.callPackage naersk { };
      in
      {
        defaultPackage = self.packages."${system}".deploy-rs;
        packages.deploy-rs = naersk-lib.buildPackage ./.;

        defaultApp = self.apps."${system}".deploy-rs;
        apps.deploy-rs = {
          type = "app";
          program = "${self.defaultPackage."${system}"}/bin/deploy";
        };

        lib = rec {
          setActivate = base: activate: pkgs.buildEnv {
            name = ("activatable-" + base.name);
            paths = [
              base
              (pkgs.writeTextFile {
                name = base.name + "-activate-path";
                text = ''
                  #!${pkgs.runtimeShell}
                  ${activate}
                '';
                executable = true;
                destination = "/deploy-rs-activate";
              })
            ];
          };

          # DEPRECATED
          checkSchema = checks.schema;

          deployChecks = deploy: builtins.mapAttrs (_: check: check deploy) checks;

          checks = {
            schema = deploy: pkgs.runCommandNoCC "jsonschema-deploy-system" { } ''
              ${pkgs.python3.pkgs.jsonschema}/bin/jsonschema -i ${pkgs.writeText "deploy.json" (builtins.toJSON deploy)} ${./interface/deploy.json} && touch $out
            '';

            activate = deploy:
              let
                allPaths = pkgs.lib.flatten (pkgs.lib.mapAttrsToList (nodeName: node: pkgs.lib.mapAttrsToList (profileName: profile: profile.path) node.profiles) deploy.nodes);
              in
              pkgs.runCommandNoCC "deploy-rs-check-activate" { } ''
                for i in ${builtins.concatStringsSep " " allPaths}; do test -f "$i/deploy-rs-activate" || (echo "A profile path is missing an activation script" && exit 1); done

                touch $out
              '';
          };
        };
      });
}
