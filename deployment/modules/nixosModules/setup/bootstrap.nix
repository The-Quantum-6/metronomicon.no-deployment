{ self, ... }: {
  flake.nixosModules.bootstrap = { modulesPath, lib, pkgs, ... }: {
    imports = with self.nixosModules; [
      (modulesPath + "/installer/scan/not-detected.nix")
      ssh-root
      app-user
    ];
    boot.loader.grub = {
      efiSupport = true;
      efiInstallAsRemovable = true;
    };

    environment.systemPackages = map lib.lowPrio [
      pkgs.curl
      pkgs.gitMinimal
    ];

    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    system.stateVersion = "24.05";
  };
}