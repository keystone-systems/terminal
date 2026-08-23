{
  self,
  crane,
  himalaya,
  calendula,
  cardamum,
  comodoro,
  llm-agents,
  grafana-mcp-src,
}:
final: prev:
let
  system = final.stdenv.hostPlatform.system;
  craneLib = crane.mkLib final;
  pim = {
    himalaya = himalaya.packages.${system}.default;
    calendula = calendula.packages.${system}.default;
    cardamum = cardamum.packages.${system}.default;
    comodoro = comodoro.packages.${system}.default;
  };
in
{
  keystone-terminal = {
    inherit (pim) himalaya calendula cardamum;
    comodoro =
      if final.stdenv.isLinux then
        pim.comodoro.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.makeWrapper ];
          buildInputs = (old.buildInputs or [ ]) ++ [ final.dbus ];
          preInstall = (old.preInstall or "") + ''
            export LD_LIBRARY_PATH="${final.lib.makeLibraryPath [ final.dbus ]}:''${LD_LIBRARY_PATH:-}"
          '';
          postInstall = (old.postInstall or "") + ''
            wrapProgram $out/bin/comodoro --prefix LD_LIBRARY_PATH : "${
              final.lib.makeLibraryPath [ final.dbus ]
            }"
          '';
        })
      else
        pim.comodoro;

    claude-code = llm-agents.packages.${system}.claude-code;
    gemini-cli = llm-agents.packages.${system}.gemini-cli;
    codex = llm-agents.packages.${system}.codex;
    opencode = llm-agents.packages.${system}.opencode;

    agent-mail = final.callPackage ../packages/agent-mail {
      himalaya = final.keystone-terminal.himalaya;
    };
    agent-coding-agent = final.callPackage ../packages/agent-coding-agent { };
    cfait = final.callPackage ../packages/cfait { inherit craneLib; };
    chrome-devtools-mcp = final.callPackage ../packages/chrome-devtools-mcp { };
    fetch-email-source = final.callPackage ../packages/fetch-email-source {
      himalaya = final.keystone-terminal.himalaya;
    };
    fetch-forgejo-sources = final.callPackage ../packages/fetch-forgejo-sources { };
    fetch-github-sources = final.callPackage ../packages/fetch-github-sources { };
    forgejo-cli-ex = final.callPackage ../packages/forgejo-cli-ex { inherit craneLib; };
    forgejo-project = final.callPackage ../packages/forgejo-project { };
    grafana-mcp = final.callPackage ../packages/grafana-mcp { inherit grafana-mcp-src; };
    keystone-conventions = final.callPackage ../packages/keystone-conventions {
      keystone-src = self;
    };
    podman-agent = final.callPackage ../packages/podman-agent { };
    zesh = final.callPackage ../packages/zesh { inherit craneLib; };
    zide = final.callPackage ../packages/zide { };
  };
}
