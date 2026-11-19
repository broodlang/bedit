# Build the counter.
# ^^^^^^^^^^^^^^^^^^ comment
PROFILE ?= release
# ^^^^^ keyword
TARGET := target/$(PROFILE)/counter
#                ^^^^^^^^^^ keyword
SOURCES = $(wildcard src/*.rs)

.PHONY: all clean test
# ^^^^ constant

all: $(TARGET)
# ^ function

$(TARGET): $(SOURCES) Cargo.toml
	cargo build --profile $(PROFILE)

test:
	cargo test

clean:
	rm -rf target

ifeq ($(PROFILE),release)
# ^^ constant
STRIP = strip
endif

include local.mk
# ^^^^^ constant
