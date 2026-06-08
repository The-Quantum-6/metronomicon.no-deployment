{ inputs, self, ... }: {
  flake.nixosConfigurations.production = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = with self.nixosModules; [
      common
      disk-config
      ./_hardware-configuration.nix
      {
        networking.hostName = "production";
      }
    ];
  };
}