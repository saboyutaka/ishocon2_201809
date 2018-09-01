.DEFAULT_GOAL := help

restart: ## Copy config
	sudo cp /home/ishocon/webapp/config/nginx/nginx.conf /etc/nginx/nginx.conf
	sudo nginx -t
	sudo cp /home/ishocon/webapp/config/mysql/my.cnf /etc/mysql/my.cnf
	sudo service nginx restart
	sudo service mysql restart

image: ## Run Serve
	docker-compose exec app /bin/bash

bench: ## Run Serve
	docker-compose exec bench /bin/bash

bundle: ## Run Bundle install
	docker-compose exec --rm app bundle install

alp: ## Run alp
	 docker-compose run --rm alp -f access.log --sum -r --aggregates='/candidates/\d+, /political_parties/\w+' --include-statuses='2[00-99]'
	 docker-compose run --rm alp -f access.log --sum -r --aggregates='/candidates/\d+, /political_parties/\w+' --include-statuses='3[00-99]'
	 docker-compose run --rm alp -f access.log --sum -r --aggregates='/candidates/\d+, /political_parties/\w+' --include-statuses='4[00-99]'
	 docker-compose run --rm alp -f access.log --sum -r --aggregates='/candidates/\d+, /political_parties/\w+' --include-statuses='5[00-99]'

mitmweb: ## Run mitmweb
	mitmweb --mode reverse:http://localhost:8888/ -p 80
	mitmdump -n -C flows.dms



replay: ## Run mitmdump

db-reset: _download_dbdump ## Reset DB
	docker-compose up -d db
	docker-compose exec db sh /var/tmp/wait.sh
	docker-compose exec db mysql -uroot -e 'drop database if exists isubata'
	docker-compose exec db mysql -uroot -e 'create database isubata'
	docker-compose exec db sh -c 'mysql -uroot isubata < /var/tmp/db.dump'

_download_dbdump: ## Download db.dump.tgz from Dropbox
	@if ! [ -f db/db.dump ];then curl -L -O -J 'https://www.dropbox.com/s/pbkxpnd2av9pjd7/db.dump?dl=0' && mv db.dump db; fi


.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
