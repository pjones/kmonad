{ config, lib, pkgs, ... }:

let
  cfg = config.services.kmonad;

  # Per-keyboard options:
  keyboard = { name, ... }: {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        example = "laptop-internal";
        description = "Keyboard name.";
      };

      device = lib.mkOption {
        type = lib.types.path;
        example = "/dev/input/by-id/some-dev";
        description = "Path to the keyboard's device file.";
      };

      compose = {
        key = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "ralt";
          description = "The (optional) compose key to use.";
        };

        delay = lib.mkOption {
          type = lib.types.int;
          default = 5;
          description = "The delay (in milliseconds) between compose key sequences.";
        };
      };

      fallthrough = lib.mkEnableOption "Reemit unhandled key events.";

      allowCommands = lib.mkEnableOption "Allow keys to run shell commands.";

      config = lib.mkOption {
        type = lib.types.lines;
        description = ''
          Keyboard configuration excluding the defcfg block.
        '';
      };
    };

    config = {
      name = lib.mkDefault name;
    };
  };

  # Create a complete KMonad configuration file:
  mkCfg = keyboard:
    let defcfg = ''
      (defcfg
        input  (device-file "${keyboard.device}")
        output (uinput-sink "kmonad-${keyboard.name}")
    '' +
    lib.optionalString (keyboard.compose.key != null) ''
      cmp-seq ${keyboard.compose.key}
      cmp-seq-delay ${toString keyboard.compose.delay}
    '' + ''
        fallthrough ${lib.boolToString keyboard.fallthrough}
        allow-cmd ${lib.boolToString keyboard.allowCommands}
      )
    '';
    in
    pkgs.writeTextFile {
      name = "kmonad-${keyboard.name}.cfg";
      text = defcfg + "\n" + keyboard.config;
      checkPhase = "${cfg.package}/bin/kmonad -d $out";
    };

  # Build a systemd path config that starts the service below when a
  # keyboard device appears:
  mkPath = keyboard: rec {
    name = "kmonad-${keyboard.name}";
    value = {
      description = "KMonad trigger for ${keyboard.device}";
      wantedBy = [ "default.target" ];
      pathConfig.Unit = "${name}.service";
      pathConfig.PathExists = keyboard.device;
    };
  };

  # Build a systemd service that starts KMonad:
  mkService = keyboard: {
    name = "kmonad-${keyboard.name}";
    value = {
      description = "KMonad for ${keyboard.device}";
      script = "${cfg.package}/bin/kmonad ${mkCfg keyboard}";
      serviceConfig.Restart = "no";
      serviceConfig.User = "kmonad";
      serviceConfig.SupplementaryGroups = [ "input" "uinput" ];
      serviceConfig.Nice = -20;
    };
  };
in
{
  options.services.kmonad = {
    enable = lib.mkEnableOption "KMonad: An advanced keyboard manager.";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.kmonad;
      example = "pkgs.haskellPacakges.kmonad";
      description = "The KMonad package to use.";
    };

    keyboards = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule keyboard);
      default = { };
      description = "Keyboard configuration.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    users.groups.uinput = { };
    users.groups.kmonad = { };

    users.users.kmonad = {
      description = "KMonad system user.";
      group = "kmonad";
      isSystemUser = true;
    };

    services.udev.extraRules = ''
      # KMonad user access to /dev/uinput
      KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
    '';

    systemd.paths =
      builtins.listToAttrs
        (map mkPath (builtins.attrValues cfg.keyboards));

    systemd.services =
      builtins.listToAttrs
        (map mkService (builtins.attrValues cfg.keyboards));
  };
}
