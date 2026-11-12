apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gpg

# Add the HashiCorp repo
wget -O - https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list

# Add the OpenTofu repo
curl -fsSL https://get.opentofu.org/opentofu.gpg > /etc/apt/keyrings/opentofu.gpg
curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey | gpg --no-tty --batch --dearmor -o /etc/apt/keyrings/opentofu-repo.gpg >/dev/null
chmod a+r /etc/apt/keyrings/opentofu.gpg /etc/apt/keyrings/opentofu-repo.gpg

echo \
  "deb [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main
deb-src [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main" | \
  tee /etc/apt/sources.list.d/opentofu.list > /dev/null
chmod a+r /etc/apt/sources.list.d/opentofu.list

# Add the Terramate repo
echo "deb [trusted=yes] https://repo.terramate.io/apt/ /" > /etc/apt/sources.list.d/terramate.list
