{
  sops = {
    age.sshKeyPaths = [
      # stable host SSH key
      # "/etc/ssh/ssh_host_ed25519_key"

      "/var/agenix/id-ed25519-agenix-primary"
    ];
  };
}
