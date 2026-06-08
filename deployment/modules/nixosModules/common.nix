{ self, inputs, ... }: {
  flake.nixosModules.common = { config, pkgs, lib, ... }: {
    imports = with self.nixosModules; [
      bootstrap
      secrets
      inputs.agenix.nixosModules.default
      app-user
      ssh-root
    ];

    virtualisation.podman.enable = true;

    virtualisation.oci-containers = {
      backend = "podman";
      containers = {
        db = {
          image = "postgres:18";
          environmentFiles = [ "/run/agenix/.env" ];
          volumes = [ "db_data:/var/lib/postgresql/18/docker" ];
          extraOptions = [
            "--network=appnet"
            "--health-cmd=pg_isready -U $POSTGRES_USER -d $POSTGRES_DB"
            "--health-interval=10s"
            "--health-timeout=5s"
            "--health-retries=5"
          ];
        };

        backend = {
          image = "jobau8311/metronomicon-backend:candidate";
          user = "999:999";
          environmentFiles = [ "/run/agenix/.env" ];
          ports = [ "3000:3000" ];
          pull = "always";
          dependsOn = [ "db" ];
          extraOptions = [ "--network=appnet" ];
        };

        frontend = {
          image = "jobau8311/metronomicon-frontend:candidate";
          environmentFiles = [ "/run/agenix/.env" ];
          ports = [ "8080:80" ];
          pull = "always";
          dependsOn = [ "backend" ];
          extraOptions = [ "--network=appnet" ];
        };
      };
    };

    services.caddy = {
      enable = true;
      virtualHosts."metronomicon.no".extraConfig = ''
        handle_path /api/* {
          reverse_proxy localhost:3000
        }
        handle {
          reverse_proxy localhost:8080
        }
      '';
    };

    systemd.services = lib.mkMerge [
      {
        # User-defined network so containers resolve each other by name
        # (db, backend, frontend), like the compose default network did.
        create-appnet = {
          serviceConfig.Type = "oneshot";
          wantedBy = [ "multi-user.target" ];
          before = [
            "podman-db.service"
            "podman-backend.service"
            "podman-frontend.service"
          ];
          script = ''
            ${pkgs.podman}/bin/podman network exists appnet \
              || ${pkgs.podman}/bin/podman network create appnet
          '';
        };
      }
      # agenix ordering + restart-on-secret-change for all three containers
      (lib.genAttrs [ "podman-db" "podman-backend" "podman-frontend" ] (_: {
        after = [ "agenix.service" "create-appnet.service" ];
        wants = [ "agenix.service" ];
        restartTriggers = [ config.age.secrets.".env".file ];
      }))
    ];

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}