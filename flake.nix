{
  description = "KOS Desktop Shell - iPadOS-style desktop for KDE Plasma 6";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = let
        kos-desktop = pkgs.callPackage ./packaging/nix/package.nix {
          src = self;
        };
      in {
        inherit kos-desktop;
        inherit (kos-desktop.passthru)
          shell-data-service kos-settings kos-platform kosctl
          kwin-dock-window-animation kwin-stage-animation kwin-context-menu-input kwin-effects-glass
          kwin-kos-bridge kwin-kos-decoration;
        default = kos-desktop;
      };

      # Fully declarative NixOS module — no manual steps required
      nixosModules.kos = { config, lib, pkgs, ... }:
      let
        cfg = config.services.kos;
        # Build against the host's architecture, Qt and KWin, including overlays.
        kos = pkgs.callPackage ./packaging/nix/package.nix {
          src = self;
          buildWeather = cfg.weather.enable;
        };
        qs_bin = "${pkgs.quickshell}/bin/quickshell";

        sync-shell = pkgs.callPackage ./packaging/nix/sync-shell.nix { inherit kos; };

        # NixOS control interface
        kos-ctl = pkgs.callPackage ./packaging/nix/kos-ctl.nix { inherit sync-shell; };
      in {
        options.services.kos = {
          enable = lib.mkEnableOption "KOS Desktop Shell";
          weather = {
            enable = lib.mkEnableOption "KOS Weather standalone application";
          };
        };

        config = lib.mkIf cfg.enable {
          # System-wide packages: binaries + KWin plugins + kosctl + kos-ctl
          #
          # The window decoration is one of the plugins, not an option: the KOS
          # Bridge effect draws the window buttons only on windows wearing it,
          # so installing the effect without the decoration would leave the
          # session with no window buttons at all. Installing it is not the same
          # as selecting it — that stays with the user, in System Settings >
          # Window Decorations, and so does turning it back off.
          environment.systemPackages = [
            pkgs.quickshell
            kos
            kos.passthru.kosctl
            kos-ctl
            kos.passthru.kwin-dock-window-animation
            kos.passthru.kwin-stage-animation
            kos.passthru.kwin-context-menu-input
            kos.passthru.kwin-effects-glass
            kos.passthru.kwin-kos-bridge
            kos.passthru.kwin-kos-decoration
          ] ++ lib.optionals cfg.weather.enable [
            kos.passthru.weather
          ];

          # KWin plugins live under lib/kwin/ in the Nix store
          environment.pathsToLink = [ "/lib/kwin" ];

          # Systemd user services — declaratively defined with Nix store paths
          systemd.user.services = {
            # Oneshot: copy shell QML to ~/.config/quickshell/kos/
            kos-shell-init = {
              description = "KOS shell config initializer";
              wantedBy = [ "plasma-workspace-wayland.target" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = sync-shell;
              };
            };

            # Platform daemon
            kos-platform = {
              description = "KOS platform integration service";
              wantedBy = [ "plasma-workspace-wayland.target" ];
              after = [ "graphical-session.target" "plasma-kwin_wayland.service" ];
              partOf = [ "plasma-workspace-wayland.target" ];
              # Apps launched from KOS (KIO::ApplicationLauncherJob) inherit
              # this unit's environment, so it must keep the session PATH that
              # Plasma imports into the user manager: per-user profiles
              # (/etc/profiles/per-user/$USER/bin, ~/.nix-profile/bin) and
              # /run/wrappers/bin live only there. NixOS writes a PATH from
              # `path` into every unit, which would shadow it; drop that line.
              environment.PATH = lib.mkForce null;
              serviceConfig = {
                Type = "simple";
                ExecStart = "${kos}/libexec/kos-platform daemon";
                Environment = [
                  "KOS_PLATFORM_KWIN_SCRIPT=${kos}/share/kos/platform/kwin/window-bridge.js"
                ];
                Restart = "on-failure";
                RestartSec = 2;
              };
            };

            # Data service
            kos-data = {
              description = "KOS persistent data service";
              wantedBy = [ "plasma-workspace-wayland.target" ];
              after = [ "graphical-session.target" "plasma-kwin_wayland.service" ];
              partOf = [ "plasma-workspace-wayland.target" ];
              serviceConfig = {
                Type = "simple";
                ExecStart = "${kos}/libexec/kos-data-service";
                Restart = "on-failure";
                RestartSec = 2;
              };
            };

            # Quickshell desktop shell
            kos-shell = {
              description = "KOS Quickshell desktop shell";
              wantedBy = [ "plasma-workspace-wayland.target" ];
              requires = [ "kos-platform.service" "kos-shell-init.service" ];
              wants = [ "kos-data.service" ];
              after = [ "graphical-session.target" "plasma-kwin_wayland.service" "plasma-plasmashell.service"
                "kos-platform.service" "kos-data.service" "kos-shell-init.service" ];
              partOf = [ "plasma-workspace-wayland.target" ];
              # Session PATH, as for kos-platform: the shell also launches
              # apps directly when the daemon is unavailable.
              environment.PATH = lib.mkForce null;
              serviceConfig = {
                Type = "simple";
                KillMode = "process";
                ExecStart = "${qs_bin} --no-duplicate -c kos";
                Environment = [
                  "QS_DISABLE_FILE_WATCHER=1"
                  "MALLOC_ARENA_MAX=2"
                  "QML2_IMPORT_PATH=%h/.config/quickshell/kos:${kos.passthru.kos-spatial3d}/lib/qt6/qml:${pkgs.kdePackages.qtquick3d}/lib/qt-6/qml:${pkgs.kdePackages.qt5compat}/lib/qt-6/qml"
                  "QT_PLUGIN_PATH=${pkgs.kdePackages.qtsvg}/lib/qt-6/plugins:${pkgs.kdePackages.qtimageformats}/lib/qt-6/plugins"
                ];
                Restart = "on-failure";
                RestartSec = 2;
              };
            };
          };
        };
      };

      # Export source path for other flakes
      lib.${system} = {
        src = ./.;
      };
    };
}
