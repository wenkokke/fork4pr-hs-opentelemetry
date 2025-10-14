{
  lib,
  pkgs,
  all-cabal-hashes,
  ...
}: let
  inherit
    (builtins)
    listToAttrs
    map
    ;
  inherit (import ./matrix.nix) supportedGHCVersions;
in rec {
  inherit pkgs;

  localPackages = {
    hs-opentelemetry-api = ../api;
    hs-opentelemetry-sdk = ../sdk;
    hs-opentelemetry-otlp = ../otlp;
    hs-opentelemetry-semantic-conventions = ../semantic-conventions;
    hs-opentelemetry-exporter-handle = ../exporters/handle;
    hs-opentelemetry-exporter-in-memory = ../exporters/in-memory;
    hs-opentelemetry-exporter-otlp = ../exporters/otlp;
    hs-opentelemetry-propagator-b3 = ../propagators/b3;
    hs-opentelemetry-propagator-datadog = ../propagators/datadog;
    hs-opentelemetry-propagator-w3c = ../propagators/w3c;
    hs-opentelemetry-instrumentation-cloudflare = ../instrumentation/cloudflare;
    hs-opentelemetry-instrumentation-conduit = ../instrumentation/conduit;
    hs-opentelemetry-instrumentation-hspec = ../instrumentation/hspec;
    hs-opentelemetry-instrumentation-http-client = ../instrumentation/http-client;
    hs-opentelemetry-instrumentation-hw-kafka-client = ../instrumentation/hw-kafka-client;
    hs-opentelemetry-instrumentation-persistent = ../instrumentation/persistent;
    hs-opentelemetry-instrumentation-persistent-mysql = ../instrumentation/persistent-mysql;
    hs-opentelemetry-instrumentation-postgresql-simple = ../instrumentation/postgresql-simple;
    hs-opentelemetry-instrumentation-yesod = ../instrumentation/yesod;
    hs-opentelemetry-instrumentation-wai = ../instrumentation/wai;
  };

  localPackageCabalDerivations = hfinal: let
    baseConfig = lib.mapAttrs (name: path: hfinal.callCabal2nix name path {}) localPackages;
  in
    baseConfig
    // {
      hs-opentelemetry-otlp = pkgs.haskell.lib.addSetupDepends baseConfig.hs-opentelemetry-otlp [pkgs.protobuf];
    };

  pluckLocalPackages = hpkgs: let
    narrowAttrs = sourceAttrs: matchAttrs:
      lib.foldl' (
        acc: key:
          if lib.hasAttr key matchAttrs
          then acc // {"${key}" = sourceAttrs.${key};}
          else acc
      ) {} (lib.attrNames sourceAttrs);
  in
    narrowAttrs hpkgs localPackages;

  extendedPackageSetByGHCVersions = listToAttrs (
    map (ghcVersion: {
      name = ghcVersion;
      value = (pkgs.haskell.packages.${ghcVersion}.override {all-cabal-hashes = all-cabal-hashes;}).extend (final: prev: localPackageCabalDerivations final // nixpkgsHaskellTweaks final prev);
      #value = pkgs.haskell.packages.${ghcVersion}.override {overrides = nixpkgsHaskellTweaks;};
    })
    supportedGHCVersions
  );

  mapKeyValues = f: attrs: let
    inherit (lib.attrsets) foldlAttrs;
  in
    foldlAttrs (acc: key: value: acc // f key value) {} attrs;

  localPackageMatrix =
    mapKeyValues (
      key: value: let
        myLocalPackages = pluckLocalPackages value;
        k = "hs-opentelemetry-suite-${key}";
      in {
        "${k}" = pkgs.buildEnv {
          name = k;
          paths = lib.attrValues myLocalPackages;
        };
      }
    )
    extendedPackageSetByGHCVersions;

  localDevPackageDeps = hsPackageSet:
    lib.concatMapAttrs (_: v:
      listToAttrs (
        map (p: {
          name = p.pname;
          value = p;
        })
        v.getBuildInputs.haskellBuildInputs
      ))
    (pluckLocalPackages hsPackageSet);

  localDevPackageDepsAsAttrSet = hsPackageSet:
    lib.filterAttrs (k: _: !builtins.hasAttr k (pluckLocalPackages hsPackageSet))
    (localDevPackageDeps hsPackageSet);

  nixpkgsHaskellTweaks = _final: prev: {
    # nixpkgs has 0.7.1.5, 0.7.1.6 relaxes bounds for 9.10, but we can also just
    # relax the bounds of 0.7.1.5 ourselves
    proto-lens = pkgs.haskell.lib.doJailbreak prev.proto-lens;
    proto-lens-protoc = prev.callHackage "proto-lens-protoc" "0.9.0.0" {};
    proto-lens-protobuf-types = pkgs.haskell.lib.doJailbreak prev.proto-lens-protobuf-types;
    tls = prev.callHackage "tls" "2.1.4" {};
    http2-tls = prev.callHackage "http2-tls" "0.4.5" {};
    snappy-c = pkgs.haskell.lib.doJailbreak prev.snappy-c;
    grapesy = pkgs.haskell.lib.dontCheck prev.grapesy;
    http2 = prev.callHackage "http2" "5.3.9" {};
    optparse-applicative = prev.callHackage "optparse-applicative" "0.19.0.0" {};
    tasty-quickcheck = pkgs.haskell.lib.doJailbreak prev.tasty-quickcheck;
  };
}
