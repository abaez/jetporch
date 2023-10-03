{
  description = "a jetporch nix flake";

  # inputs needed for rust along with some nice tooling for development environment
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "utils";
      };
    };
    naersk = {
      url = "github:nix-community/naersk";
      inputs = { nixpkgs.follows = "nixpkgs"; };
    };
    nix-filter.url = "github:numtide/nix-filter";
  };

  outputs = { self, nixpkgs, utils, rust-overlay, naersk, nix-filter }:
    let
      pname = "jetporch";
      cmd = "jetp";
    in utils.lib.eachDefaultSystem (system:
      let
        # nix packages with rust overlay defaulats instead
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            rust-overlay.overlays.default
            (self: super: {
              rustc = self.rust-bin.stable.latest.default;
              cargo = self.rust-bin.stable.latest.default;
            })
          ];
        };

        # override version cargo and rustc version of naersk with overlay
        naersk-lib = naersk.lib.${system}.override {
          cargo = pkgs.cargo;
          rustc = pkgs.rustc;
        };

        buildInputs = [ pkgs.openssl pkgs.pkg-config ];

        src = nix-filter.lib.filter {
          root = ./.;
          include = [ ./Cargo.toml ./Cargo.lock ./build.rs ./src ];
        };

      in rec {
        # main package to base all builds from
        packages.prod = naersk-lib.buildPackage {
          inherit buildInputs pname src;
          release = true;
        };

        # not release version
        packages.dev = naersk-lib.buildPackage {
          inherit buildInputs pname src;
          release = false;
        };

        packages.default = packages.prod;

        # build out a container image if want to run as a container
        packages.container = pkgs.dockerTools.buildImage {
          name = pname;
          tag = packages.prod.version;
          created = "now";
          contents = packages.prod;
          config.Cmd = [ "${packages.prod}/bin/${cmd}" ];
        };

        # useful default app to run from nix directly
        apps.prod = utils.lib.mkApp {
          name = pname;
          drv = packages.prod;
          exePath = "/bin/${cmd}";
        };
        apps.default = apps.prod;

        # dev shell default
        devShells.default = pkgs.mkShell {
          shellHook = ''
            export RUST_SRC_PATH=${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}
          '';

          nativeBuildInputs = [ pkgs.cargo pkgs.openssl ];
        };
      });
}
