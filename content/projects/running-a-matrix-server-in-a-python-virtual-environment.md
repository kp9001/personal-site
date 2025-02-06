---
title: "Running a Matrix Server in a Python Virtual Environment"
showToc: true
TocOpen: false
draft: false
hidemeta: false
comments: false
disableShare: true
disableHLJS: false
hideSummary: false
searchHidden: true
ShowReadingTime: false
ShowBreadCrumbs: false
ShowWordCount: false
UseHugoToc: true
---

In this article, I outline the setup of a [matrix](https://matrix.org) server in a Python virtual environment on Fedora. This is based on the setup I used for a matrix server I ran years ago. My server is no longer live, so links to it in this article will not work, but the setup detailed here should still work. 

Matrix is a decentralized network which bridges clients for instant messaging, video conferencing, and VoIP. It supports [end to end encryption via the Olm and Megolm cryptographic ratchets](https://matrix.org/docs/guides/end-to-end-encryption-implementation-guide/). 

This outline will cover various aspects of security hardening starting from the deployment of the server. 

### Deploying a VPS

We will be deploying matrix on a virtual private server running Fedora 36. We can configure a firewall on our VPS provider, only allowing the ports which we will need for the matrix service

- 22 SSH - passwordless FIDO2 only
- 80 HTTP - HTTPS redirect only
- 443 HTTPS - reverse proxy via Cloudflare

We can then configure our local firewall to match

```
firewall-cmd --permanent --add-service http
firewall-cmd --permanent --add-service https
firewall-cmd --reload
```

### Confgiuring User Accounts

We want to restrict access to the root user, so we will create a dedicated admin user with sudo permissions

```
adduser admin
usermod -aG wheel admin
```

We will now create a dedicated matrix user to run the application without any root access. This is best practice as we do not want any exploit in the matrix process to have the potential of escalating to root. 

```
sudo useradd matrix
```

If desired, ssh keys can be added to this user's `.ssh` directory as well. Otherwise it can be accessed via `sudo -iu matrix`. Configurating a matrix user password is not really needed because the admin user has root access anyway, and this is the default ssh user.

### Install Matrix Dependencies

We are now ready to install our matrix dependencies. 

```
sudo dnf install libtiff-devel libjpeg-devel libzip-devel freetype-devel 
  lcms2 libwebp-devel tcl-devel tk-devel redhat-rpm-config 
  python36 virtualenv libffi-devel openssl-devel
sudo dnf group install "Development Tools"
```

### Synapse Installation and Configuration

Rather than installing matrix directly, we will be configuring a python virtual environment. 

```
sudo -iu matrix
mkdir ~/synapse
virtualenv -p python3 ~/synapse/env
source ~/synapse/env/bin/activate
pip install --upgrade pip virtualenv six packaging appdirs setuptools
pip install matrix-synapse
python -m synapse.app.homeserver --server-name matrix.kplante.com --config-path homeserver.yaml --generate-config --report-stats=no
```

Now matrix is installed and initiated. We must now make the following changes in `homeserver.yaml`:

```
serve_server_wellknown: true
enable_registration: true
registration_requires_token: true
```

We need the wellknown line in order to process federation requests on port 443. Without this, we would need to expose port 8448. We don't need to do this because we are only running matrix on this server. For reference: [Delegation of incoming federation traffic](https://github.com/matrix-org/synapse/blob/develop/docs/delegate.md)

You need enable_registration to allow new users to register accounts. You can also enable insecure registration, but this is not recommended as bots can flood your registration. You can either enable captcha or email registration, or for a more private server, configure single use access tokens. The latter is what we did above. Details on how to set it up will be in an addendum at the bottom.

### TLS via Cloudflare

At this time, our matrix server is running, but we need a web server to proxy the traffic and access the server. Before we install and configure our webserver, we're going to prepare our TLS configuration. You can manage this locally for free using a tool like certbot, but I will be using Cloudflare. Here is a brief rundown of the setup: 

- Cloudflare -> DNS -> Create A (ipv4 root), AAAA (ipv6 root), and CNAME (matrix) records
- Cloudflare -> SSL/TLS -> Overview -> Full (strict) mode
- Cloudflare -> SSL/TLS -> Edge Certificates -> enable the following:
	- Always Use HTTPS
	- Enable TLS Version: TLS 1.3
	- Certificate Transperancy Monitoring
- Cloudflare -> SSL/TLS -> Origin Server -> Create Certificate
- Create wildcard cert with ECC
- Copy pem to `/etc/ssl/certs/<cert>.pem` as root
- Copy key to `/etc/ssl/private/<privkey>.key` as root
- Configure proper key perms: `sudo chmod 600 /etc/ssl/private/<privkey>.key` (these will later be pointed to in our nginx site configs)

### Install and Configure Nginx

Matrix requires a webserver to route traffic. We will use nginx as our webserver. 

```
sudo dnf install nginx
```

We will create a 4096 bit Diffie-Hellman prime for key exchange. This took 10 minutes on my single core server. The output will be references in the matrix nginx config under `ssl_dhparam`. 

```
openssl genpkey -genparam -algorithm DH -out /etc/ssl/certs/dhparam4096.pem -pkeyopt dh_paramgen_prime_len:4096
```

We need an nginx configuration for matrix. 

```
sudoedit /etc/nginx/conf.d/matrix.conf
```

This will configure the reverse proxy on port 8008, enable TLS with the certificates we generated in Cloudflare, and increases our max upload size to match the configuration in homeserver.yaml. (To change it, changes must be made in both places.) In addition, this example includes a number of optional security headers. It also strictly enforces TLSv1.3, which is okay because we are reverse proxying with Cloudflare. 

```
server {
    listen 80;
    listen [::]:80;
    server_name <name>
    return 301 https://$host$request_uri;

}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name <name>;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;
    add_header Content-Security-Policy "default-src 'none'; img-src 'self'; style-src 'self'; script-src 'self'";
    add_header X-Frame-Options "DENY" always;

    ssl_certificate /etc/ssl/certs/<name>.pem;
    ssl_certificate_key /etc/ssl/private/<name>.key;
    ssl_dhparam /etc/ssl/certs/dhparam4096.pem;
    ssl_protocols TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers on;
    ssl_conf_command Options PrioritizeChaCha;

    location / {
        proxy_pass http://localhost:8008;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $host;
        client_max_body_size 50M;
    }
}
```

```
sudo systemctl restart nginx
```

The above configuration is based on the standard in the [Reverse Proxy](https://github.com/matrix-org/synapse/blob/develop/docs/reverse_proxy.md) docs, but without the 8448 configuration (since we are using 443 with wellknown as described above). 

### SELinux Setting

Since we are using Fedora, which comes enforcing a number of SELinux policies by default, we must allow httpd to act as a relay per the following:
- https://stackoverflow.com/questions/23948527/13-permission-denied-while-connecting-to-upstreamnginx
- https://security.stackexchange.com/questions/152358/difference-between-selinux-booleans-httpd-can-network-relay-and-httpd-can-net

```
sudo setsebool -P httpd_can_network_relay 1
```

### Start Matrix-Synapse

The following sequence of commands will start our matrix server.

```
cd ~/synapse
source env/bin/activate
synctl start
```

At this point, if everything has been properly configured, we should be able to reach https://matrix.kplante.com in our browser with proper TLS verification. It should show a webpage informing us that matrix is running. 

If our wellknown from above is properly configured, we should also be able to access https://matrix.kplante.com/.well-known/matrix/server and see the following response:

```
{"m.server":"matrix.kplante.com:443"}
```

We can also test our federation using the [Matrix Federation Tester](https://federationtester.matrix.org/)

### Configure to Auto Restart

We want our matrix server to automatically restart if it crashes for any reason. This can be done with a lazy crontab. 

```
sudo crontab -u matrix -e
```

```
SHELL=/bin/bash
HOME=/home/matrix/synapse
* * * * * ps aux | grep synapse.app.homeserver | grep -v grep &>/dev/null || { source /home/matrix/synapse/env/bin/activate && synctl start &>/dev/null && date >> restart.log; }
```

This will check once per minute to see if  a  synapse.app.homeserver process is running. If so, it will exit. If not, it will run `synctl start` from the virtualenv from the `/home/matrix/synapse` working directory. (The working directory is important so that it reads the right `homeserver.yaml` file.)

As long as the `synapse` directory is preserved minus the virtualenv, it can be easily migrated to a new virtualenv by rerunning the earlier commands. `database.md` and `media` hold the server's data, `homeserver.yaml` contains the server configuration, and the directory will also have key files generated. 

### Automatic Updates

Lastly, we will configure another crontab to perform daily system updates and reload nginx configurations. 

```
sudo crontab -e
```

```
0 9 * * * dnf update -y && systemctl reload nginx
```

For upgrading the matrix-synapse homeserver itself, we can carry out the following process as the matrix user:

```
cd /home/matrix/synapse
source /home/matrix/synapse/env/bin/activate
pip install --upgrade pip virtualenv six packaging appdirs setuptools
pip install --upgrade matrix-synapse
synctl restart
deactivate
cd -
```

I created a bash script to carry out this procedure and placed it into `/home/matrix/.local/bin/matrix_upgrade`. If desired, you can configure automatic updates with this in a similar way, with a matrix user crontab. 

```
sudo crontab -u matrix -e
```

```
0 9 * * * matrix_upgrade
```

### Access via Client

We are now ready to access our server from our client. Create accounts and sign in via a matrix client or the [element web app](https://app.element.io/). You can configure your own element web app via any of the instructions [here](https://github.com/vector-im/element-web), but per the security advisory in the readme, it is a bad idea for that app to share a domain with your homeserver. 

### Addendum: Matrix Admin API

Instructions on how to configure token based access as described above using the admin API:

#### References:

- [The Admin API](https://matrix-org.github.io/synapse/latest/usage/administration/admin_api/)
- [Registration Tokens](https://matrix-org.github.io/synapse/latest/usage/administration/admin_api/registration_tokens.html)

#### Procedure:

- Create an admin user on the matrix server cli:

```
register_new_matrix_user -c homeserver.yaml http://localhost:8008
```

- This will create the following interactive prompt:

```
New user localpart [matrix]: <username>
Password: <password>
Confirm password: <password>
Make admin [no]: yes
Sending registration request...
Success.
```

- Log in with this user via a matrix client and find your access token. On element, go to settings -> help to find it. 

- Use it with the following calls to the admin API:

- Show current access tokens

```
curl -X GET \ 
--header "Authorization: Bearer <admin access_token>" \
"https://<hostname>/_synapse/admin/v1/registration_tokens"
```
- Create new access tokens

```
curl -X POST \
--header "Authorization: Bearer <admin access_token>" \
"https://<hostname>/_synapse/admin/v1/registration_tokens/new" \
-d '{"uses_allowed": 1}'
```

