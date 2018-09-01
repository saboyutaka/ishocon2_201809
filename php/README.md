# AMI環境でのPHPの動かし方

## phpのインストール

```
sudo apt update
sudo apt install -y php php-cli php-fpm php-mysql
```

## composerのインストール(https://getcomposer.org/download/)

```
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php -r "if (hash_file('SHA384', 'composer-setup.php') === '544e09ee996cdf60ece3804abc52599c22b1f40f4323403c44d44fdfdd586475ca9813a858088ffbc1f233e9b180f061') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
php composer-setup.php
php -r "unlink('composer-setup.php');"
```

## composerでパッケージをインストールする

```
php composer.phar install
```

## nginx.confの書き換え

```
(
    /etc/nginx/nginx.confのバックアップ
)
sudo cp webapp/php/php-nginx.conf /etc/nginx/nginx.conf
sudo service nginx reload
```

# Docker環境でのPHPの動かし方

## nginx.confの書き換え

```
(
    /etc/nginx/nginx.confのバックアップ
)
sudo cp webapp/php/php-nginx.conf /etc/nginx/nginx.conf
sudo service nginx reload
```

## php-fpmの再起動

```
sudo service php7.2-fpm restart
```
