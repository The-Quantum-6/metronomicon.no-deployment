{ inputs, self, ... }: {
  flake.nixosConfigurations.test-vm = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ({ lib, pkgs, config, ... }: {
        system.stateVersion = "25.11";
        users.users.root.password = "root";
        services.getty.autologinUser = "root";

        virtualisation.vmVariant = {
          virtualisation.sharedDirectories = {
            env-dir = {
              source = "$ENV_DIR";   # set by the wrapper script
              target = "/mnt/env-host";
            };
          };
          virtualisation.forwardPorts = [
            { from = "host"; host.port = 443; guest.port = 443; }
            { from = "host"; host.port = 80; guest.port = 80; }
          ];
        };

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
              pull = "newer";
              dependsOn = [ "db" ];
              extraOptions = [ "--network=appnet" ];
            };

            frontend = {
              image = "jobau8311/metronomicon-frontend:candidate";
              environmentFiles = [ "/run/agenix/.env" ];
              ports = [ "8080:80" ];
              pull = "newer";
              dependsOn = [ "backend" ];
              extraOptions = [ "--network=appnet" ];
            };
          };
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

          {
            load-env = {
              description = "Load .env from host shared directory";
              wantedBy = [ "multi-user.target" ];
              before = [ "portfolio.service" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = ''
                mkdir -p /run/agenix
                if [ -f /mnt/env-host/.env ]; then
                  cp /mnt/env-host/.env /run/agenix/.env
                  chmod 600 /run/agenix/.env
                  echo "Loaded .env from host"
                else
                  echo "WARNING: No .env found at /mnt/env-host/.env" >&2
                fi
              '';
            };
          }
          # agenix ordering + restart-on-secret-change for all three containers
          (lib.genAttrs [ "podman-db" "podman-backend" "podman-frontend" ] (_: {
            after = [ "agenix.service" "create-appnet.service" ];
            wants = [ "agenix.service" ];
            restartTriggers = [ "/run/agenix/.env" ];
          }))
        ];
        
        networking.firewall.allowedTCPPorts = [ 443 80 ];
        services.caddy ={
          enable = true; # Should reverse proxy to localhost 3000
          virtualHosts."localhost".extraConfig = ''
            tls internal
            handle_path /api/* {
              reverse_proxy localhost:3000
            }
            handle {
              reverse_proxy localhost:8080
            }
          '';
        };
      })
    ];
  };
}