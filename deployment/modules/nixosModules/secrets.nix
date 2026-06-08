{ ... }: {
  flake.nixosModules.secrets = { ... }: {
    age.secrets.".env" = {
      file = ../../secrets/.env.age;
      mode = "400";
      owner = "app";
      group = "app";
    };
  };
}