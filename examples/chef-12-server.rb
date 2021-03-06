##### Example bootstrap template #####
# This bootstrap will create a brand new erchef server and
# use your existing settings to set things up. It will automatically
# disable the webui, create a client named after the client in
# your existing configuration, and update the public keys for your
# client, as well as the chef-validator. Afterwards, it will install
# the cookbooks it requires for itself, and then register itself with
# itself. How meta.
#
# NOTE: It uses the node IP address for configuration, rather than the
# FQDN. You can see it being done down there in the json building. The
# example is based on eth0. Modify or remove as needed.

sudo bash -c '

curl -L https://www.chef.io/chef/install.sh | bash
mkdir -p /var/chef/cache /var/chef/cookbooks /var/chef/cookbooks/chef-server-populator
wget -qO- https://supermarket.chef.io/cookbooks/chef-server/download | tar xvzC /var/chef/cookbooks/
wget -qO- https://supermarket.chef.io/cookbooks/chef-server-ingredient/download | tar xvzC /var/chef/cookbooks/
wget -qO- https://supermarket.chef.io/cookbooks/packagecloud/download | tar xvzC /var/chef/cookbooks/
wget -qO- https://github.com/hw-cookbooks/chef-server-populator/tarball/feature/chef-12 | tar xvzC /var/chef/cookbooks/chef-server-populator --strip-components=1

mkdir -p /tmp/chef-server-setup
(
cat <<'EOP'
<%= IO.read(Chef::Config[:validation_key]) %>
EOP
) > /tmp/chef-server-setup/validator.pem
(
cat <<'EOP'
<%= %x{openssl rsa -in #{Chef::Config[:validation_key]} -pubout} %>
EOP
) > /tmp/chef-server-setup/validator_pub.pem
(
cat <<'EOP'
<%= %x{openssl rsa -in #{Chef::Config[:client_key]} -pubout} %>
EOP
) > /tmp/chef-server-setup/user_pub.pem

mkdir -p /etc/chef
cp /tmp/chef-server-setup/validation.pem /etc/chef/validation.pem
chmod 600 /etc/chef/validator.pem

IPADDR=`curl http://169.254.169.254/latest/meta-data/public-ipv4`
if [ $? -ne 0 ]
  then
    IPADDR=`ip addr show eth0 | grep "inet " | awk -F" " '\''{print $2}'\'' | sed -e "s/\/..//"`
fi

(
echo "
{
  \"chef-server\": {
    \"version\": \"12.0.5-1\",
    \"api_fqdn\": \"${IPADDR}\"
  },
  \"chef_server_populator\": {
    \"orgs\": {
      \"inception_llc\": {
        \"validator_pub_key\": \"validator_pub.pem\"
      }
    },
    \"org_users\": {
      \"inception_llc\": {
        \"pub_key\": \"user_pub.pem\"
      }
    },
    \"servername_override\": \"${IPADDR}\",
    \"base_path\": \"/tmp/chef-server-setup\"
  },
  \"run_list\": [ \"recipe[chef-server-populator]\" ]
}
"
) > /tmp/chef-server.json

chef-solo -j /tmp/chef-server.json

rm -rf /tmp/chef-server-setup

(
cat <<'EOP'
log_level        :info
log_location     STDOUT
chef_server_url  "https://127.0.0.1/organizations/inception_llc"
validation_client_name "inception_llc-validator"
force_logger     true
ssl_verify_mode :verify_none
<% if @config[:chef_node_name] == nil %>
# Using default node name
<% else %>
node_name "<%= @config[:chef_node_name] %>"
<% end %>
EOP
) > /etc/chef/client.rb

(
echo "
{
  \"chef_server_populator\": {
    \"servername_override\": \"${IPADDR}\"
  },
  \"run_list\": [ \"recipe[chef-server-populator]\"  ]
}
"
) > /etc/chef/first-boot.json

<%= start_chef %>
echo "**********************************************"
echo "* NOTE: Update chef_server_url in knife.rb!  *"
echo "*   IP: https://${IPADDR}                    *"
echo "**********************************************"
'
