{ ... }: {
  flake.nixosModules.ssh-root = { ... }: {
    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
    };

    users.users.root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA5uAZGPf8TJI9N5uyVAHxG8AsWu6AJmdkWGMkhpriDa" # Bootstrap key
    ];
  };
}