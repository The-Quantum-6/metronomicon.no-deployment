{ ... }: {
  flake.nixosModules.ssh-root = { ... }: {
    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
    };

    users.users.root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPHdCri0n+rL2Ziajo1qRNDWXS0G/Jh3hZdj8waE9uhH" # Bootstrap key
    ];
  };
}