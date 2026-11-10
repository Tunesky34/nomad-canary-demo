.PHONY: lab-up test smoke build

lab-up:
	sudo ./scripts/lab-up.sh

test:
	cd app && node --test

smoke:
	./scripts/smoke-local.sh

build:
	docker build -t localhost:5000/demo:dev app
