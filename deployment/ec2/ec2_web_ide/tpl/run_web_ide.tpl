#!/bin/bash

cat <<EOF | sudo tee -a /home/ec2-user/service-key.pem
${service_private_key}
EOF

chown ec2-user:ec2-user /home/ec2-user/service-key.pem
chmod 400 /home/ec2-user/service-key.pem

cat <<EOF | sudo tee -a /etc/nginx/conf.d/web_ide.conf
server {
  listen 80;
  server_name ${web_ide_server_name};

  proxy_busy_buffers_size   512k;
  proxy_buffers   4 512k;
  proxy_buffer_size   256k;

  location / {
    access_by_lua_block {
      local cjson = require "cjson"
      local session = require "resty.session"
      local jwt = require "resty.jwt"
      local http = require "resty.http"
      local openidc = require "resty.openidc"
      local lrucache = require "resty.lrucache"

      local opts = {
        redirect_uri = "${redirect_uri}",
        accept_none_alg = false,
        ssl_verify = "no",
        discovery = "${oidc_auth_url}/.well-known/openid-configuration",
        client_id = "${client_id}",
        client_secret = "${client_secret}",
        redirect_uri_scheme = "https",
        logout_path = "/logout",
        redirect_after_logout_uri = "${oidc_auth_url}/protocol/openid-connect/logout?redirect_uri=${daytona_url}",
        redirect_after_logout_with_id_token_hint = false,
        session_contents = {id_token=true}
      }
      
      local res, err = openidc.authenticate(opts)
      if err then
        ngx.status = 403
        ngx.say(err)
        ngx.exit(ngx.HTTP_FORBIDDEN)
      end

      if res.id_token.sub ~= "${user_uuid}" 
      then
        ngx.header["Content-Type"] = "text/html"
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.say("unauthorized")
        return ngx.exit(ngx.HTTP_OK)
      end
    }

    proxy_set_header Host \$host;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection upgrade;
    proxy_set_header Accept-Encoding gzip;


    proxy_pass http://127.0.0.1:${web_ide_port}/;
  }

  location /ping {
    add_header Content-Type text/plain;
    return 200 'successful!';
  }
}
EOF

cat <<EOF | sudo tee -a /home/ec2-user/.openvscode-server/data/Machine/settings.json
{
  "terminal.integrated.gpuAcceleration": "off"
}
EOF

NAMESERVER=$(grep '^nameserver' /etc/resolv.conf | head -n 1 | awk '{print $2}')
NGINX_CONF="/etc/nginx/nginx.conf"
sed -i "s|^\s*resolver\s\+.*;|    resolver $NAMESERVER valid=300s;|" "$NGINX_CONF"

sudo systemctl enable nginx.service
sudo systemctl restart nginx

sudo systemctl enable code-server
sudo systemctl restart code-server

sudo yum install -y jq
accessToken=$( curl -sS -d 'client_id=${client_id}' -d 'client_secret=${client_secret}' -d 'grant_type=client_credentials' '${get_access_token_url}' | jq -r ".access_token" )
clientInfo=$( curl -sS --header 'Content-Type: application/json' --header "Authorization: Bearer $accessToken" --request GET ${get_client_info_url} )
addClientInfo=$( echo $clientInfo | jq '.redirectUris[.redirectUris | length] |= . + ${valid_uri}' )
curl -sS --header 'Content-Type: application/json' --header "Authorization: Bearer $accessToken" --request PUT ${update_client_info_url} --data-raw "$addClientInfo"

unset accessToken
unset clientInfo
unset addClientInfo

