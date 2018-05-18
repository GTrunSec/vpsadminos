{ config, lib, pkgs, utils, ... }:

with lib;
let
  cfg = config.services.udev;
  hwdbBin = pkgs.runCommand "hwdb.bin"
    { preferLocalBuild = true;
      allowSubstitutes = false;
    }
    ''
      mkdir -p etc/udev/hwdb.d
      for i in ${pkgs.eudev}/var/lib/udev/hwdb.d/*; do
        ln -s $i etc/udev/hwdb.d/$(basename $i)
      done

      echo "Generating hwdb database..."
      # hwdb --update doesn't return error code even on errors!
      res="$(${pkgs.eudev}/bin/udevadm hwdb --update --root=$(pwd) 2>&1)"
      echo $res
      [ -z "$(echo "$res" | egrep '^Error')" ]
      mv etc/udev/hwdb.bin $out
    '';

  # Perform substitutions in all udev rules files.
  udevRules = pkgs.runCommand "udev-rules"
    { preferLocalBuild = true;
      allowSubstitutes = false;
      packages = unique (map toString cfg.packages);
    }
    ''
      mkdir -p $out
      shopt -s nullglob
      set +o pipefail

      # Set a reasonable $PATH for programs called by udev rules.
      echo 'ENV{PATH}="${udevPath}/bin:${udevPath}/sbin"' > $out/00-path.rules

      # Add the udev rules from other packages.
      for i in $packages; do
        echo "Adding rules for package $i"
        for j in $i/var/lib/udev/rules.d/*; do
          echo "Copying $j to $out/$(basename $j)"
          cat $j > $out/$(basename $j)
        done
      done

      # Fix some paths in the standard udev rules.  Hacky.
      for i in $out/*.rules; do
        substituteInPlace $i \
          --replace \"/sbin/modprobe \"${pkgs.kmod}/bin/modprobe \
          --replace \"/sbin/mdadm \"${pkgs.mdadm}/sbin/mdadm \
          --replace \"/sbin/blkid \"${pkgs.utillinux}/sbin/blkid \
          --replace \"/bin/mount \"${pkgs.utillinux}/bin/mount \
          --replace /usr/bin/readlink ${pkgs.coreutils}/bin/readlink \
          --replace /usr/bin/basename ${pkgs.coreutils}/bin/basename
      done

      echo -n "Checking that all programs called by relative paths in udev rules exist in ${pkgs.eudev}/lib/udev... "
      import_progs=$(grep 'IMPORT{program}="[^/$]' $out/* |
        sed -e 's/.*IMPORT{program}="\([^ "]*\)[ "].*/\1/' | uniq)
      run_progs=$(grep -v '^[[:space:]]*#' $out/* | grep 'RUN+="[^/$]' |
        sed -e 's/.*RUN+="\([^ "]*\)[ "].*/\1/' | uniq)
      for i in $import_progs $run_progs; do
        if [[ ! -x ${pkgs.eudev}/lib/udev/$i && ! $i =~ socket:.* ]]; then
          echo "FAIL"
          echo "$i is called in udev rules but not installed by udev"
          exit 1
        fi
      done
      echo "OK"
    '';

  extraUdevRules = pkgs.writeTextFile {
    name = "extra-udev-rules";
    text = cfg.extraRules;
    destination = "/var/lib/udev/rules.d/99-local.rules";
  };

  # Udev has a 512-character limit for ENV{PATH}, so create a symlink
  # tree to work around this.
  udevPath = pkgs.buildEnv {
    name = "udev-path";
    paths = cfg.path;
    pathsToLink = [ "/bin" "/sbin" ];
    ignoreCollisions = true;
  };
in
{
  options = {
    services.udev = {
      extraRules = mkOption {
        default = "";
        type = types.lines;
        example = ''
          KERNEL=="eth*", ATTR{address}=="00:1D:60:B9:6D:4F", NAME="my_fast_network_card"
        '';
        description = "Additional udev rules";
      };

      packages = mkOption {
        type = types.listOf types.path;
        default = [];
        description = ''
          List of packages containing udev rules.
        '';
        apply = map getBin;
      };

      path = mkOption {
        type = types.listOf types.path;
        default = [];
        description = ''
          Packages added to the <envar>PATH</envar> environment variable when
          executing programs from Udev rules.
        '';
      };
    };
  };

  config = mkMerge [
    (mkIf (!config.boot.isContainer) {
      services.udev.packages = [ pkgs.eudev extraUdevRules ];
      services.udev.path = [ pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.utillinux pkgs.eudev ];

      environment.etc = {
        "udev/rules.d".source = udevRules;
        "udev/hwdb.bin".source = hwdbBin;

        "service/eudev/run".source = pkgs.writeScript "eudev" ''
          #!/bin/sh
          exec ${pkgs.eudev}/bin/udevd
        '';

        "service/eudev-trigger/run".source = pkgs.writeScript "eudev-trigger" ''
          #!/bin/sh
          ${pkgs.eudev}/bin/udevadm trigger --action=add --type=subsystems
          ${pkgs.eudev}/bin/udevadm trigger --action=add --type=devices
          exec sv once .
        '';

        "service/eudev-trigger/check".source = pkgs.writeScript "eudev-trigger-check" ''
          #!/bin/sh
          ${pkgs.eudev}/bin/udevadm settle
        '';
      };
    })
  ];
}

