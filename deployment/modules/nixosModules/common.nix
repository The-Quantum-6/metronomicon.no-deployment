{ self, inputs, ... }: {
  flake.nixosModules.common = { config, ... }: {
    imports = with self.nixosModules; [
      bootstrap
      secrets
      inputs.agenix.nixosModules.default
      app-user
      ssh-root
    ];

    # Example config of docker container
    virtualisation.oci-containers = {
      backend = "podman";
      containers.envtest = {
        user = "999:999";
        image = "mendhak/http-https-echo:40";
        environmentFiles = [ "/run/agenix/.env" ]; # Secrets available at /run/agenix/.env
        ports = [ "80:8080" "443:8443" ];
        pull = "newer";
      };
    };

    systemd.services."podman-envtest" = {
      after = [ "agenix.service" ]; # Wait until agenix is finished
      wants = [ "agenix.service" ];
      restartTriggers = [ config.age.secrets.".env".file ]; # This is required for the container to restart when a secret is changed or added
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}