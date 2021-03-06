#/bin/bash

function command_exists {
  command -v "$1" > /dev/null;
}

# config
HOST=polidog.local
PORT=80

APP_DIR="/var/www/app"
MYSQL_PASSWORD="root"
WP_DATABASE_NAME="wordpress"

while [ $# -gt 0 ];
do
    case ${1} in

        --host|-h)
            HOST=${2}
            shift
        ;;

        --port|-p)
            PORT=${2}
            shift
        ;;

        --dir)
            APP_DIR=${2}
            shift
        ;;

        --mysql-password)
            MYSQL_PASSWORD=${2}
            shift
        ;;

        --database-name|-n)
            WP_DATABASE_NAME=${2}
            shift
        ;;

        *)
            echo "[ERROR] Invalid option '${1}'"
            usage
            exit 1
        ;;
    esac
    shift
done




# base
yum install -y epel-release

# nginx
nginx_file="/etc/yum.repos.d/nginx.repo"
nginx_conf_file="/etc/nginx/conf.d/wordpress.conf"

if [ ! -e ${nginx_file} ]; then
  cat > ${nginx_file} << `EOF`
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=0
enabled=1
`EOF`
fi

if ! command_exists nginx ; then
  yum --enablerepo=nginx install nginx -y

  if [ ! -e ${nginx_conf_file} ]; then
      cat ${APP_DIR}/wordpress.conf >> ${nginx_conf_file}
  fi

  # サービス登録
  systemctl enable nginx.service


fi

sed -i "s/listen 80;$/listen ${PORT};/" ${nginx_conf_file}
sed -i "s/server_name .*;$/server_name ${HOST};/" ${nginx_conf_file}
systemctl restart nginx



# mysql
if ! command_exists mysql ; then
  rpm -Uvh http://dev.mysql.com/get/mysql-community-release-el7-5.noarch.rpm
  yum install -y mysql-server

  systemctl enable mysqld.service
  systemctl start mysqld.service

  /usr/bin/mysql -e "CREATE DATABASE ${WP_DATABASE_NAME};" -D mysql
  /usr/bin/mysql -e "SET PASSWORD FOR 'root'@'::1' = PASSWORD('newpassword');" -D mysql
  /usr/bin/mysql -e "SET PASSWORD FOR 'root'@'127.0.0.1' = PASSWORD('${MYSQL_PASSWORD}');" -D mysql
  /usr/bin/mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${MYSQL_PASSWORD}');" -D mysql

fi


# php
if ! command_exists php ; then
  php_repo_file="/etc/yum.repos.d/php"
  rpm -Uvh http://rpms.famillecollet.com/enterprise/remi-release-7.rpm
  yum install -y --enablerepo=remi-php70 php php-ast php-fpm php-mysqlnd php-pdo php-tidy php-zip php-mbstring php-gd

  # php config
  sed -i "s/^;date.timezone =$/date.timezone = \"Asia\/Tokyo\"/" /etc/php.ini | grep "^timezone" /etc/php.ini

  # php-fpm config
  sed -i "s/^listen = 127.0.0.1:9000$/listen = \/var\/run\/php-fpm\/php-fpm\.sock/" /etc/php-fpm.d/www.conf | grep "^listen" /etc/php.ini
  sed -i "s/^;listen.mode = 0660$/listen.mode = 0666/" /etc/php-fpm.d/www.conf | grep "^listen\.mode" /etc/php-fpm.d/www.conf
  sed -i "s/^user = apache$/user = nginx/" /etc/php-fpm.d/www.conf | grep "^user =" /etc/php-fpm.d/www.conf
  sed -i "s/^group = apache$/group = nginx/" /etc/php-fpm.d/www.conf | grep "^group =" /etc/php-fpm.d/www.conf

  systemctl enable php-fpm.service
  systemctl start php-fpm.service
fi

# composer
if ! command_exists composer ; then
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer
  cd ${APP_DIR}
fi

if [ ! -e ${APP_DIR}/wordpress ] ; then
  composer install --no-interaction
fi
