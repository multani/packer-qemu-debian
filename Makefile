PACKER_FILE = debian.json

OUTPUT_DIR = output
OUTPUT_NAME = debian.qcow2
OUTPUT = $(OUTPUT_DIR)/$(OUTPUT_NAME)

PACKER_FLAGS = -var output_dir="$(OUTPUT_DIR)" -var output_name="$(OUTPUT_NAME)"
PACKER_BUILD_FLAGS =


all:
	$(MAKE) $(OUTPUT) create converge verify destroy

clean:
	rm -rf $(OUTPUT_DIR) *.json

really-clean: clean
	rm -rf packer_cache/ .kitchen/ .gems/


%.json: %.yaml
	@echo "Convert YAML to JSON: $< => $@"
	@python3 -c "import yaml, json, sys; json.dump(yaml.load(sys.stdin), sys.stdout, indent=2, sort_keys=True)" < $< > $@

variables.yaml:
	@if [ ! -f "$(@:.json=.yaml)" ]; then \
		echo "{}" > $@; \
	fi

$(OUTPUT): $(PACKER_FILE)
	$(MAKE) build

build: validate $(PACKER_FILE)
	packer build $(PACKER_FLAGS) $(PACKER_BUILD_FLAGS) $(PACKER_FILE)

validate: $(PACKER_FILE)
	packer validate $(PACKER_FLAGS) $(PACKER_FILE)

test create setup converge destroy verify list: .gems
	OUTPUT=./$(OUTPUT) bundle exec kitchen $@

.gems: Gemfile
	bundle install --path $@
	touch $<
