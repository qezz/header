{
  description = "Header";

  inputs = {
    naersk.url = "github:nix-community/naersk";
    nixpkgs-mozilla.url = "github:mozilla/nixpkgs-mozilla";
    nixpkgs.url = "nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { naersk, nixpkgs, self, utils, nixpkgs-mozilla }:
    utils.lib.eachDefaultSystem (system:
      let
        version = (builtins.substring 0 8 self.lastModifiedDate) + "-"
          + (if self ? rev then builtins.substring 0 7 self.rev else "dirty");

        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import nixpkgs-mozilla) ];
        };

        toolchain = (pkgs.rustChannelOf {
          rustToolchain = ./rust-toolchain.toml;
          sha256 = "sha256-gdYqng0y9iHYzYPAdkC/ka3DRny3La/S5G8ASj0Ayyc=";
        }).rust;

        naersk' = pkgs.callPackage naersk {
          cargo = toolchain;
          rustc = toolchain;
        };

        nativeBuildInputs = [ pkgs.pkg-config ];

        projectCargo = { description, cargoCommand }:
          naersk'.buildPackage {
            inherit description nativeBuildInputs;

            src = pkgs.lib.sourceFilesBySuffices ./. [
              ".rs"
              "Cargo.lock"
              "Cargo.toml"
            ];

            # Deny warnings.
            RUSTFLAGS = "-D warnings";

            # Ensure we have pretty output, even on CI.
            CARGO_TERM_COLOR = "always";

            cargoBuild = _:
              "mkdir -p $out/log && cargo $cargo_options ${cargoCommand} 2>&1 | tee $out/log/build.ansi";

            installPhase = ''
              mkdir -p $out/bin target/release
              find target/release -maxdepth 1 -executable -type f -execdir cp '{}' $out/bin ';'
            '';
          };

      in rec {
        devShells = {
          default = pkgs.mkShell {
            nativeBuildInputs = [ toolchain ] ++ nativeBuildInputs;

            # Set a few environment variables that are useful for running locally.
            RUST_SRC_PATH = pkgs.rustPlatform.rustLibSrc;
          };
        };

        checks = rec {
          test = projectCargo {
            description = "Run tests";
            cargoCommand = "test";
          };

          # Note, --tests means "also lint the tests", not "only lint the tests".
          clippy = projectCargo {
            description = "Run Clippy";
            cargoCommand = "clippy --tests";
          };

          fmt-rust = {
            description = "Check Rust formatting";
          } // pkgs.runCommand "check-fmt-rust" {
            buildInputs = [ toolchain ];
          } ''
            cargo fmt --manifest-path ${./.}/Cargo.toml -- --check
            mkdir -p $out/log
            echo "fmt ok" > $out/log/build.ansi
          '';
        };

        packages = rec {
          default = header;

          header = projectCargo {
            description = "Build binary in release mode";
            cargoCommand = "build --release";
          };

          container = pkgs.dockerTools.buildLayeredImage {
            name = "qezz/header";
            tag = "v${version}";
            contents = [ header pkgs.cacert ];

            config.Entrypoint = [
              "${header}/bin/header"
            ];

            # Run as user 1 and group 1, so we don't run as root. There is no
            # /etc/passwd inside this container, so we use user ids instead.
            config.User = "1:1";
          };
        };
      });
}
