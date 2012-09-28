TARGET = sparsebundlefs

PKG_CONFIG = pkg-config
CFLAGS = -Wall -O2 -march=native
DEFINES = -DFUSE_USE_VERSION=26

ifeq ($(shell uname), Darwin)
	# Pick up OSXFUSE, even with pkg-config from MacPorts
	PKG_CONFIG := PKG_CONFIG_PATH=/usr/local/lib/pkgconfig $(PKG_CONFIG)
else ifeq ($(shell uname), Linux)
	LFLAGS += -Wl,-rpath=$(shell $(PKG_CONFIG) fuse --variable=libdir)
endif

FUSE_FLAGS := $(shell $(PKG_CONFIG) fuse --cflags --libs)

$(TARGET): sparsebundlefs.cpp
	$(CXX) $(CFLAGS) $(FUSE_FLAGS) $(LFLAGS) $(DEFINES) $< -o $@

all: $(TARGET)

clean:
	rm -f $(TARGET)
