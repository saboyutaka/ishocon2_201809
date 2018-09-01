.DEFAULT_GOAL := help

image: ## Run Serve
	docker-compose exec app /bin/bash

bench: ## Run Serve
	docker-compose exec bench /bin/bash

update: bundle migrate yarn_install yarn_dev ## Run bundle, migrate and yarn

up: ## Run web container
	docker-compose up -d web

console: ## Run Rails console
	docker-compose run --rm web bundle exec rails c

migrate: ## Run db:migrate
	docker-compose run --rm web bundle exec rails db:migrate

rollback: ## Run db:rollback
	docker-compose run --rm web bundle exec rails db:rollback

bundle: ## Run bundle install
	docker-compose run --rm web bundle install

attach: ## Attach running web container for binding.pry
	docker attach `docker ps -f name=churacari_web -f status=running --format "{{.ID}}"`

yarn_install: ## Run yarn install
	docker-compose run --rm yarn install

yarn_dev: ## Run yarn run dev
	docker-compose run --rm yarn run dev

yarn_watch: ## Run yarn watch
	docker-compose run --rm yarn run watch


.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
