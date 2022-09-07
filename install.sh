if (( $EUID != 0 )); then
    echo "Please run as root"
    exit
fi

clear

GitHub_Account="https://raw.githubusercontent.com/TobiDev01/PterodactylInstaller"
FQDN=""
MYSQL_PASSWORD=""
email=""
user_username=""
user_password=""
email_regex="^(([A-Za-z0-9]+((\.|\-|\_|\+)?[A-Za-z0-9]?)*[A-Za-z0-9]+)|[A-Za-z0-9]+)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"

installPanel(){
    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    add-apt-repository ppa:redislabs/redis -y
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
    apt update
    apt-add-repository universe
    apt -y install php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/

    mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -u root -e "CREATE DATABASE panel;"
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "CREATE USER 'pterodactyluser'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'127.0.0.1' WITH GRANT OPTION;"

    rm /etc/mysql/my.cnf
    curl -o /etc/mysql/my.cnf $GitHub_Account/my.cnf
    cp .env.example .env
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
    php artisan key:generate --force

    php artisan p:environment:setup \
    --author="$email" \
    --url="https://$FDQN" \
    --timezone="America/New_York" \
    --cache="redis" \
    --session="redis" \
    --queue="redis" \
    --redis-host="localhost" \
    --redis-pass="null" \
    --redis-port="6379" \
    --settings-ui=true

    php artisan p:environment:database \
    --host="127.0.0.1" \
    --port="3306" \
    --database="panel" \
    --username="pterodactyl" \
    --password="${MYSQL_PASSWORD}"

    php artisan migrate --seed --force

    php artisan p:user:make \
    --email="$email" \
    --username="$user_username" \
    --name-first="$user_username" \
    --name-last="$user_username" \
    --password="$user_password" \
    --admin=1

    chown -R www-data:www-data /var/www/pterodactyl/*

    crontab -l | {
        cat
        echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
    } | crontab -

    curl -o /etc/systemd/system/pteroq.service $GitHub_Account/pteroq.service
    sudo systemctl enable --now redis-server
    sudo systemctl enable --now pteroq.service
    rm /etc/nginx/sites-enabled/default
    curl -o /etc/nginx/conf.d/pterodactyl.conf $GitHub_Account/pterodactyl.conf
    sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/conf.d/pterodactyl.conf
    sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    sudo systemctl restart nginx
}

valid_email() {
  [[ $1 =~ ${email_regex} ]]
}
invalid_ip() {
  ip route get "$1" >/dev/null 2>&1
  echo $?
}
check_FQDN_SSL() {
  if [[ $(invalid_ip "$FQDN") == 1 && $FQDN != 'localhost' ]]; then
    SSL_AVAILABLE=true
  else
    echo "* Enter a valid domain name."
  fi
}
password_input() {
  local __resultvar=$1
  local result=''
  local default="$4"

  while [ -z "$result" ]; do
    echo -n "* ${2}"

    while IFS= read -r -s -n1 char; do
      [[ -z $char ]] && {
        printf '\n'
        break
      }
      if [[ $char == $'\x7f' ]]; then
        if [ -n "$result" ]; then
          [[ -n $result ]] && result=${result%?}
          printf '\b \b'
        fi
      else
        result+=$char
        printf '*'
      fi
    done
    [ -z "$result" ] && [ -n "$default" ] && result="$default"
    [ -z "$result" ] && print_error "${3}"
  done

  eval "$__resultvar="'$result'""
}
email_input() {
  local __resultvar=$1
  local result=''

  while ! valid_email "$result"; do
    echo -n "* ${2}"
    read -r result

    valid_email "$result" || print_error "${3}"
  done

  eval "$__resultvar="'$result'""
}
summary() {

  echo "-- Database credentials"
  echo "* Name: panel"
  echo "* User: pterodactyluser"
  echo "* Password: $MYSQL_PASSWORD"
  echo ""
  echo "-- Panel credentials"
  echo "* Email: $user_email"
  echo "* Username: $user_username"
  echo "* Password: $user_password"
  echo ""
  echo "* Hostname/FQDN: $FQDN"
}

echo "[0] Install Panel"
echo "[1] Exit"

read -p "Please enter a number: " choice
if [ $choice == "0" ]
    then

    rand_pw=$(
        tr -dc 'A-Za-z0-9!"#$%&()*+,-./:;<=>?@[\]^_`{|}~' </dev/urandom | head -c 64
        echo
    )

    password_input MYSQL_PASSWORD "Password (press enter to use randomly generated password): " "MySQL password cannot be empty" "$rand_pw"
    email_input email "Provide the email address: " "Email cannot be empty or invalid"
    required_input user_username "Provide username: " "Username cannot be empty"
    password_input user_password "Provide password: " "Password cannot be empty"

    while [ -z "$FQDN" ]; do
    echo -n "* Set the FQDN of this panel (panel.example.com): "
    read -r FQDN
    [ -z "$FQDN" ] && print_error "FQDN cannot be empty"
    done

    check_FQDN_SSL
    summary

#    installPanel
fi
if [ $choice == "1" ]
    then
    exit
fi
