.PHONY: lab-up test test-scripts smoke build deploy audit demo-auto demo-manual evidence results

lab-up:            ## one-command lab setup (Ubuntu VM)
	sudo ./scripts/lab-up.sh

test: test-scripts ## all tests that need no cluster
	cd app && node --test

test-scripts:      ## deploy.sh + audit filter against fakes (needs jq)
	./tests/test-deploy.sh
	./tests/test-audit.sh

smoke:             ## build the image, check /health 200 and 500
	./scripts/smoke-local.sh

build:
	docker build -t localhost:5000/demo:dev app

deploy:            ## manual deploy: make deploy IMAGE=localhost:5000/demo:<sha>
	./scripts/deploy.sh

audit:             ## read-only audit of every service job's update block
	./scripts/audit-update-blocks.sh

demo-auto:         ## make demo-auto GOOD_IMAGE=localhost:5000/demo:<sha>
	./scripts/time-rollback.sh auto 3

demo-manual:       ## make demo-manual GOOD_IMAGE=... HUMAN_REACTION_SECONDS=60
	./scripts/time-rollback.sh manual 3

evidence:          ## capture job history/deployments into docs/evidence/ (run after a rollback)
	./scripts/collect-evidence.sh

results:           ## fill docs/results.md from the newest timing CSVs
	./scripts/fill-results.sh
