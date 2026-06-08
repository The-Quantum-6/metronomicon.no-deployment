# NixOS Deployment Template

> **⚠️ Unfinished — use at your own risk.**
> This template relies on `sed`-based string manipulation of several files and may break if the included workflows or NixOS config files are renamed or restructured.
> It is intended for personal projects and has only been tested with Hetzner Cloud VPSs. Other providers may require changes to `disk-config.nix`.
> Environment names must be 1-63 characters of letters, digits, or hyphens, and must start/end with a letter or digit (e.g. "dev", "staging", "prod"). Workflows now validate this.

A template for deploying [NixOS](https://nixos.org/) to a remote server using [nixos-anywhere](https://github.com/nix-community/nixos-anywhere), with secrets managed by [agenix](https://github.com/ryantm/agenix) and CI/CD powered by GitHub Actions.

## Table of Contents

- [Who Is This For?](#who-is-this-for)
- [What Problem Does This Solve?](#what-problem-does-this-solve)
- [Prerequisites](#prerequisites)
- [Repository Structure](#repository-structure)
- [Flake Inputs](#flake-inputs)
- [Getting Started](#getting-started)
- [Workflows](#workflows)
  - [Bootstrap Host](#bootstrap-host)
  - [Update Host](#update-host)
- [Configuring Environment Variables](#configuring-environment-variables)
- [Configuring Hosts](#configuring-hosts)
- [Disk Configuration](#disk-configuration)
- [The `app` User](#the-app-user)
- [Local Testing with `act`](#local-testing-with-act)
- [Alternatives](#alternatives)
  - [NixOS Deployment Tools](#nixos-deployment-tools)
  - [Secret Management](#secret-management)
  - [Comparison Table](#comparison-table)

## Who Is This For?

This template is designed for deployments that meet the following criteria:

- **NixOS-based**: Your server configuration is a NixOS configuration.
- **Public codebase**: Designed for open-source projects. It can be adapted for private repositories if needed.
- **Secrets via environment variables**: Secrets management works by rendering GitHub environment variables and secrets into a `.env` file, then encrypting it with [agenix](https://github.com/ryantm/agenix).
- **Single server per environment**: Each GitHub environment maps to a single server (but you can create multiple environments for multiple servers).

## What Problem Does This Solve?

This template lets you manage a declarative NixOS deployment and automate updates via GitHub Actions.

For example, if you have a web app, you might want both a staging and a production server. This template allows you to write a single NixOS configuration and store all secrets and environment-specific settings in GitHub. You can then use the two included workflows — **Bootstrap host** and **Update host** — to provision and update any number of servers running that configuration.

Generated configuration files for each deployment are committed back to the repository, allowing you to update or reconfigure individual hosts independently.

## Prerequisites

- A GitHub repository (fork or clone this template)
- [Nix](https://nixos.org/download.html) installed (for local development/testing)
- A remote server (tested with Hetzner Cloud VPSs) accessible via SSH
- Two **ed25519** SSH key pairs:
  - One for root access to deployed hosts
  - One for agenix secret encryption

## Repository Structure (some files omitted)

```
.
├── .github/workflows/
│   ├── bootstrap.yaml                   # Workflow: initial server provisioning
│   └── update.yaml                      # Workflow: update an existing server
└── deployment                           # Main dir for deployment code
    ├── flake.nix                        # Nix flake entry point
    ├── .env.template                    # Template for environment variables
    ├── modules/
    │   ├── flake-parts.nix              # Target system configuration (x86_64-linux)
    │   ├── hosts/
    │   │   └── bootstrap/
    │   │       └── configuration.nix    # Bootstrap host template (copied per host)
    │   └── nixosModules/
    │       ├── setup/
    │       │   ├── bootstrap.nix        # Base NixOS module (boot, packages, SSH, flakes)
    │       │   └── disk-config.nix      # Disk partitioning via disko
    │       ├── common.nix               # Post-bootstrap module (adds agenix secrets)
    │       ├── secrets.nix              # agenix secret declarations (.env)
    │       ├── ssh-root.nix             # OpenSSH config + root authorized keys
    │       └── app-user.nix             # Creates the unprivileged `app` user
    └── secrets/
        ├── keys.nix                     # Public keys authorized to decrypt secrets
        └── secrets.nix                  # agenix secret file declarations
```

After bootstrapping a host named `my-server`, the following files are generated and committed:

```
modules/hosts/my-server/
├── configuration.nix            # Host config (references common + my-server-specific)
└── _hardware-configuration.nix  # Auto-detected hardware config from nixos-anywhere
```

## Flake Inputs

| Input | Purpose |
|-------|---------|
| [nixpkgs](https://github.com/NixOS/nixpkgs) (unstable) | NixOS packages and modules |
| [disko](https://github.com/nix-community/disko) | Declarative disk partitioning |
| [flake-parts](https://github.com/hercules-ci/flake-parts) | Modular flake structure |
| [import-tree](https://github.com/vic/import-tree) | Auto-imports all `.nix` files under `modules/` |
| [agenix](https://github.com/ryantm/agenix) | Age-encrypted secrets management |

## Getting Started

### 1. Fork or clone this template

```bash
# Using GitHub's template feature or:
git clone https://github.com/MPM-Labs/nixos-deployment-template my-deployment
cd my-deployment
```

Alternatively you can incorporate the tool in an existing repo like so:
```bash
git remote add deployment https://github.com/MPM-Labs/nixos-deployment-template.git
git fetch deployment
git merge deployment/main --allow-unrelated-histories
git remote remove deployment
```

### 2. Configure repository-level secrets

In your GitHub repository, go to **Settings → Secrets and variables → Actions** and add:

| Secret | Description |
|--------|-------------|
| `SSH_ROOT_KEY` | ed25519 private key for root access to all deployed hosts |
| `SSH_AGENIX_KEY` | ed25519 private key used by agenix to encrypt secrets |

> **Note**: Update the corresponding public key in `modules/nixosModules/ssh-root.nix` to match your `SSH_ROOT_KEY`, and in `secrets/keys.nix` to match your `SSH_AGENIX_KEY`.

### 3. Create a GitHub environment for your host

Go to **Settings → Environments** and create a new environment. The environment name becomes the hostname of the deployed machine and must be 1-63 characters of letters, digits, or hyphens (starting/ending with a letter or digit).

Add the following secret to the environment:

| Secret | Description |
|--------|-------------|
| `IP_ADDRESS` | The IPv4 address of the target server. IPv6 is not supported. |

Add any additional variables or secrets referenced by your `.env.template` (see [Configuring Environment Variables](#configuring-environment-variables)). The workflows will fail if any referenced values are missing.

### 4. Prepare your server

Ensure the target server has your `SSH_ROOT_KEY` public key in the root user's `authorized_keys`. This is typically configured during server provisioning with your hosting provider.

### 5. Run the Bootstrap workflow

Go to **Actions → Bootstrap host**, select your environment, and run the workflow. See [Bootstrap Host](#bootstrap-host) for details.

## Workflows

### Bootstrap Host

The **Bootstrap host** workflow (`bootstrap.yaml`) performs the initial provisioning of a server. It is triggered manually via `workflow_dispatch` and requires you to select a deployment environment.

The workflow performs these steps:

1. **Creates host configuration** — Copies `modules/hosts/bootstrap/configuration.nix` and `modules/nixosModules/bootstrap-specific.nix`, replacing `bootstrapConfig` with the environment name (hostname). Commits the new files.
2. **Runs nixos-anywhere** — Installs NixOS on the target server using the bootstrap configuration, including disk partitioning via [disko](https://github.com/nix-community/disko). Generates and commits the hardware configuration.
3. **Registers the host's SSH key with agenix** — Fetches the host's ed25519 SSH public key and adds it to `secrets/keys.nix` so the host can decrypt secrets. Commits the change.
4. **Encrypts secrets** — Renders `.env.template` with values from GitHub environment variables and secrets, then encrypts the result into `secrets/.env.age` using agenix. Commits the encrypted file.
5. **Swaps to the full configuration** — Replaces the `bootstrap` module reference with `common` in the host's `configuration.nix`. The `common` module adds agenix and secret access on top of the bootstrap base. Commits and pushes all changes.
6. **Rebuilds the host** — SSHes into the server and runs `nixos-rebuild switch` to apply the full configuration (including secrets).

### Update Host

The **Update host** workflow (`update.yaml`) updates an already-bootstrapped server. It is triggered manually via `workflow_dispatch`.

The workflow performs these steps:

1. **Re-encrypts secrets** — Renders `.env.template` with the latest GitHub environment variables and secrets, then re-encrypts into `secrets/.env.age`. Commits and pushes the change.
2. **Rebuilds the host** — SSHes into the server and runs `nixos-rebuild switch` to apply the latest configuration from the repository.

Use this workflow after making changes to the NixOS configuration or environment variables.

## Configuring Environment Variables

The `.env.template` file defines the environment variables that will be available on deployed hosts. It supports three types of values:

| Type | Syntax | Example |
|------|--------|---------|
| Static values | `KEY=value` | `PUBLIC_VAR_1=localhost` |
| Environment variables (non-secret) | `KEY=${vars.VAR_NAME}` | `ENV_DEPENDENT_VAR=${vars.ENV_VAR}` |
| Environment secrets | `KEY=${secrets.SECRET_NAME}` | `SECRET_VAR=${secrets.SECRET_VAR}` |

- `${vars.VAR_NAME}` is replaced with the value of the GitHub environment **variable** named `VAR_NAME`.
- `${secrets.SECRET_NAME}` is replaced with the value of the GitHub environment **secret** named `SECRET_NAME`.
- The workflows validate that every referenced variable and secret is present before encrypting secrets.

The rendered `.env` file is encrypted with agenix and made available on the deployed host at:

```
/run/agenix/.env
```

This file is owned by the `app` user (mode `400`), so only the `app` user can read it.

## Configuring Hosts

### Shared configuration

Edit `modules/nixosModules/common.nix` to change the NixOS configuration for all hosts. The `common` module imports:

- `bootstrap` — Base system config (boot loader, essential packages like `curl` and `git`, SSH, flakes, `app` user)
- `secrets` — agenix secret declarations
- `agenix` — The agenix NixOS module

Changes to shared configuration only take effect on a host after running the **Update host** workflow for that host.

### Per-host configuration

After bootstrapping, each host gets a `[hostname]-specific.nix` file in `modules/nixosModules/`. This file is initially empty and can be used to add NixOS configuration that applies only to that specific host.

## Disk Configuration

The disk layout is defined in `modules/nixosModules/setup/disk-config.nix` and uses [disko](https://github.com/nix-community/disko) for declarative partitioning. The default layout targets `/dev/sda` and creates:

- A 1 MB BIOS boot partition
- A 500 MB EFI System Partition (ESP) mounted at `/boot`
- An LVM volume group using the remaining space, with a single logical volume formatted as ext4 and mounted at `/`

If your server uses a different disk device (e.g., `/dev/nvme0n1`), you can override the device path in your host-specific configuration using `lib.mkForce` or by adjusting `disk-config.nix`.

## The `app` User

The `bootstrap` module creates an unprivileged user named `app` (defined in `modules/nixosModules/app-user.nix`):

- Home directory: `/home/app`
- Groups: `app`, `networkmanager`
- Not a superuser

This user owns the decrypted `.env` file at `/run/agenix/.env`. Use this user to run your application services.

## Local Testing with `act`

The workflows include `if: ${{ !env.ACT }}` conditionals to skip git operations and secret encryption when running locally with [act](https://github.com/nektos/act). This allows you to test the nixos-anywhere provisioning step without triggering commits or secret management.

## Alternatives

Several tools in the NixOS ecosystem address deployment and secret management. Below is a summary of the most relevant alternatives, how they compare to this template, and when you might prefer one over another.

### NixOS Deployment Tools

#### [NixOps](https://github.com/NixOS/nixops)

NixOps is the original NixOS deployment tool. It manages infrastructure state (which machines exist, their IP addresses, etc.) in a local state file and can provision cloud resources directly (e.g., AWS EC2 instances, GCP VMs).

- **Similarities**: Declarative NixOS configuration, multi-host support, secret provisioning.
- **Differences**: NixOps manages cloud infrastructure lifecycle (create/destroy VMs), while this template assumes the server already exists. NixOps uses a local state file rather than Git and CI/CD for coordination. NixOps does not natively use flakes, though community forks add flake support.

#### [deploy-rs](https://github.com/serokell/deploy-rs)

deploy-rs is a lightweight, flake-native deployment tool written in Rust. It pushes Nix store paths to remote hosts and activates them, with built-in support for rollback on failure.

- **Similarities**: Flake-native, pushes NixOS configurations to remote hosts, supports multi-host deployments.
- **Differences**: deploy-rs focuses solely on deployment activation (push and switch) and does not handle initial provisioning, disk partitioning, or secret encryption. It runs from the command line rather than through CI/CD workflows, though it can be integrated into CI pipelines. It includes automatic rollback if a deployment fails health checks.

#### [Colmena](https://github.com/zhaofengli/colmena)

Colmena is a deployment tool inspired by NixOps and morph. It supports parallel deployments, flakes, and a custom module-based configuration for defining hosts.

- **Similarities**: Declarative multi-host NixOS configuration, flake support, remote deployment via SSH.
- **Differences**: Colmena has its own host definition format (`colmena.nix` or flake-based) and supports parallel deployment to many machines simultaneously. Like deploy-rs, it does not handle initial provisioning or secret encryption. It includes a local evaluation mode for faster iteration and supports deployment to hosts behind a bastion/jump server.

#### [morph](https://github.com/DBCDK/morph)

morph is a NixOS deployment tool that provides a simple, imperative-style CLI for managing fleets of NixOS machines.

- **Similarities**: SSH-based deployment, declarative NixOS configuration, multi-host support.
- **Differences**: morph uses its own `network.nix` format for defining hosts rather than flakes. It supports health checks and rollback, similar to deploy-rs. It does not handle provisioning, disk configuration, or secret management.

#### [nixinate](https://github.com/MatthewCroughan/nixinate)

nixinate is a minimal flake-based deployment tool that generates deployment scripts from your flake's `nixosConfigurations`.

- **Similarities**: Flake-native, generates deployment commands for each host, uses `nixos-rebuild switch` under the hood.
- **Differences**: nixinate is intentionally minimal — it adds a `deploy` app to your flake and nothing else. It does not handle provisioning, secrets, or CI/CD integration.

#### [nixos-rebuild](https://nixos.wiki/wiki/Nixos-rebuild) (with `--target-host`)

The built-in `nixos-rebuild` command supports deploying to remote hosts via `--target-host` and `--build-host` flags, without any additional tooling.

- **Similarities**: Uses the same underlying mechanism (`nixos-rebuild switch`) that this template invokes over SSH.
- **Differences**: Requires manual invocation, no CI/CD integration, no provisioning, no secret management. It is the simplest approach but requires the most manual effort for multi-environment setups.

### Secret Management

This template uses [agenix](https://github.com/ryantm/agenix) for secret management. The main alternative is:

#### [sops-nix](https://github.com/Mic92/sops-nix)

sops-nix integrates [Mozilla SOPS](https://github.com/getsops/sops) with NixOS for secret management. It supports multiple encryption backends including age, GPG, and cloud KMS (AWS, GCP, Azure).

- **Similarities**: Encrypts secrets in the repository, decrypts them on the target host at activation time, integrates with NixOS modules.
- **Differences**: sops-nix supports structured secret formats (YAML, JSON, binary) rather than agenix's single-file approach. It can use cloud KMS for key management, which avoids distributing private keys. agenix is simpler and uses only age/SSH keys, while sops-nix is more flexible but has more configuration overhead.

### Comparison Table
**Please note that this table is AI-generated. You should do your own research.**

| Feature | This Template | NixOps | deploy-rs | Colmena | morph | nixinate |
|---|---|---|---|---|---|---|
| Initial provisioning | ✅ (nixos-anywhere) | ✅ (cloud APIs) | ❌ | ❌ | ❌ | ❌ |
| Disk partitioning | ✅ (disko) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Secret management | ✅ (agenix) | ✅ (built-in) | ❌ | ❌ | ❌ | ❌ |
| Flake support | ✅ | ⚠️ (community forks) | ✅ | ✅ | ❌ | ✅ |
| CI/CD integration | ✅ (GitHub Actions) | ❌ | ❌ (manual) | ❌ (manual) | ❌ (manual) | ❌ (manual) |
| Rollback on failure | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ |
| Parallel deployment | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Cloud resource management | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Multi-host support | ✅ (one per environment) | ✅ | ✅ | ✅ | ✅ | ✅ |

This template combines provisioning (nixos-anywhere), disk management (disko), secrets (agenix), and CI/CD (GitHub Actions) into a single opinionated workflow. The alternatives listed above are generally more focused tools that handle one or two of these concerns and can be composed together for a custom setup.
