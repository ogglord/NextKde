{
  writeShellScriptBin,
  ...
}:

# Installed by services.kos.cli.enable. The NixOS module owns the units and
# the shell config copy; this helper only drives them.
writeShellScriptBin "kos-ctl" ''
  # KOS NixOS Control Interface
  # Unified interface for managing KOS Desktop Shell on NixOS

  set -euo pipefail

  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'

  SHELL_CONFIG="''${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/kos"
  UNITS="kos-platform.service kos-data.service kos-shell.service"

  print_ok()   { printf "$GREEN✓$NC %s\n" "$1"; }
  print_warn() { printf "$YELLOW⚠$NC %s\n" "$1"; }
  print_err()  { printf "$RED✗$NC %s\n" "$1"; }
  print_info() { printf "$CYANℹ$NC %s\n" "$1"; }

  usage() {
    cat <<'EOF'
kos-ctl — NixOS KOS Desktop Shell Controller

Usage: kos-ctl <command> [options]

Commands:
  start       Start all KOS services
  stop        Stop all KOS services
  restart     Restart all KOS services
  status      Show service status
  logs        Follow KOS logs
  sync        Sync shell config from the current system generation
  doctor      Check KOS installation health

Autostart follows services.kos.enable in the NixOS configuration.

Examples:
  kos-ctl start      # Start KOS
  kos-ctl status     # Check status
  kos-ctl logs       # View logs

EOF
  }

  check_nixos() {
    if [[ ! -f /etc/NIXOS ]]; then
      print_err "This command is only for NixOS systems"
      exit 1
    fi
  }

  # kos-shell-init copies the shell from the package the module installed,
  # so sync never has to guess a store path.
  sync_shell_config() {
    print_info "Syncing shell config from the system generation..."
    if ! systemctl --user restart kos-shell-init.service; then
      print_err "kos-shell-init.service failed"
      print_info "Check: journalctl --user -u kos-shell-init"
      return 1
    fi
    print_ok "Shell config synced"
  }

  start_services() {
    sync_shell_config

    for unit in $UNITS; do
      if systemctl --user is-active "$unit" >/dev/null 2>&1; then
        systemctl --user restart "$unit"
      else
        systemctl --user start "$unit" 2>/dev/null || true
      fi
    done

    print_ok "KOS services started"
  }

  stop_services() {
    for unit in kos-shell.service kos-platform.service kos-data.service; do
      if systemctl --user is-active "$unit" >/dev/null 2>&1; then
        systemctl --user stop "$unit"
        print_ok "$unit stopped"
      fi
    done
  }

  show_status() {
    printf "\n$GREEN=== KOS Service Status ===$NC\n"
    for unit in $UNITS; do
      if systemctl --user is-active "$unit" >/dev/null 2>&1; then
        printf "  $GREEN●$NC %s: running\n" "$unit"
      else
        printf "  $RED●$NC %s: stopped\n" "$unit"
      fi
    done
    printf "\n"
  }

  doctor() {
    print_info "Checking KOS installation..."

    if command -v quickshell >/dev/null 2>&1; then
      print_ok "quickshell: $(command -v quickshell)"
    else
      print_err "quickshell not found"
    fi

    if [[ -f "$SHELL_CONFIG/shell.qml" ]]; then
      print_ok "Shell config exists"
    else
      print_warn "Shell config missing (run: kos-ctl sync)"
    fi

    for unit in kos-shell-init.service $UNITS; do
      if systemctl --user cat "$unit" >/dev/null 2>&1; then
        print_ok "$unit: installed"
      else
        print_err "$unit: not installed (is services.kos.enable set?)"
      fi
    done

    printf "\n"
  }

  # Main
  check_nixos

  case "''${1:-help}" in
    start)    start_services ;;
    stop)     stop_services ;;
    restart)  stop_services; sleep 1; start_services ;;
    status)   show_status ;;
    logs)     journalctl --user -u kos-platform.service -u kos-data.service -u kos-shell.service -f ;;
    sync)     sync_shell_config ;;
    doctor)   doctor ;;
    help|-h|--help) usage ;;
    *)
      print_err "Unknown command: ''${1:-}"
      usage
      exit 1
      ;;
  esac
''
