{ ... }: {
  flake.nixosModules.app-user = { ... }: {
    users.users.app = {
      isSystemUser = true;
      group = "app";
      uid = 999;
    };
    users.groups.app = {
      gid = 999;
    };
  };
}