all:
	@echo "select target"

release:
	gsutil -m cp -a public-read install.sh gs://get.eva-ics.com/

test:
	gsutil -m cp -a public-read install.sh gs://get.eva-ics.com/install-test.sh
