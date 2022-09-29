all:
	@echo "select target"

release:
	gsutil -m cp -a public-read install.sh gs://pub.bma.ai/eva3/install

test:
	gsutil -m cp -a public-read install.sh gs://pub.bma.ai/eva3/install-test.sh
