# Custom Arduino makefile

# TODO:
#   - programmer

PORT = /dev/ttyACM0
BOARD = mega atmega2560
PROGRAMMER = stk500v2
ARDUINO_DIR = /opt/arduino-1.5.6-r2
ARDUINO_LIBS = 

# board and cpu
BOARD_VARIANT = $(word 1,$(BOARD))
BOARD_CPU = $(word 2,$(BOARD))

# filename of sketch file
SKETCH_FILE = $(firstword $(wildcard *.ino *.pde) $(notdir $PWD).cpp)

TARGET = $(basename $(SKETCH_FILE))

# helper variables
null  :=
space := $(null) #
comma := ,

# check for Arduino version
ARDUINO_VERSION := $(shell cat $(ARDUINO_DIR)/lib/version.txt | sed -e 's/^[0-9]://g' -e 's/[.]//g' -e 's/$$/0000/' | head -c3)

# determine arduino hardware directory
ifeq ($(shell expr $(ARDUINO_VERSION) '<' 150),1)
    BOARD_VARIANT_LIST = $(call get_board_variants,$(ARDUINO_DIR)/hardware/arduino/boards.txt)
    ifneq ($(filter $(BOARD_VARIANT),$(BOARD_VARIANT_LIST)), '')
        MCU_FAMILY = avr
    else
        $(error Non supported board variant)
    endif
    ARDUINO_HW_DIR = $(ARDUINO_DIR)/hardware/arduino
    ARDUINO_BOARDS_LIST = $(ARDUINO_HW_DIR)/boards.txt
else
    BOARD_VARIANT_LIST = $(call get_board_variants,$(ARDUINO_DIR)/hardware/arduino/avr/boards.txt)
    ifneq ($(filter $(BOARD_VARIANT), $(BOARD_VARIANT_LIST)), '')
        MCU_FAMILY = avr
        BOARD_VARIANT_LIST += $(call get_board_variants,$(ARDUINO_DIR)/hardware/arduino/sam/boards.txt)
    else
        BOARD_VARIANT_LIST += $(call get_board_variants,$(ARDUINO_DIR)/hardware/arduino/sam/boards.txt)
        ifneq ($(filter $(BOARD_VARIANT), $(BOARD_VARIANT_LIST)), '')
            MCU_FAMILY = sam
        else
            $(error Non supported board variant)
        endif
    endif
    ARDUINO_HW_DIR = $(ARDUINO_DIR)/hardware/arduino/$(MCU_FAMILY)
    ARDUINO_BOARDS_LIST = $(ARDUINO_DIR)/hardware/arduino/avr/boards.txt $(ARDUINO_DIR)/hardware/arduino/sam/boards.txt
endif

define get_board_variants
    $(filter-out menu,$(shell grep -v -P '^#|^[\s]*$$' $1 | cut -d '.' -f 1 | uniq))
endef

GET_BOARD_META = grep '^$(BOARD_VARIANT)\.' $(ARDUINO_HW_DIR)/boards.txt | sed 's/^$(BOARD_VARIANT)\.//' | awk -v cpu=$(BOARD_CPU) 'BEGIN { cpuRegex="^menu\.cpu\."cpu"\." } { if($$1 ~ /^menu\.cpu\./) { if($$1 ~ cpuRegex) { sub(cpuRegex, "", $$1); print $$1 } } else { print $$1 } }' | sort -u
GET_META_VALUE = cut -d '=' -f 2-

ARDUINO_CORE_DIR = $(ARDUINO_HW_DIR)/cores/arduino
ARDUINO_VARIANT_DIR_NAME := $(shell $(GET_BOARD_META) | grep '^build\.variant' | $(GET_META_VALUE))
ARDUINO_VARIANT_DIR = $(addprefix $(ARDUINO_HW_DIR)/variants/,$(ARDUINO_VARIANT_DIR_NAME))
ARDUINO_HW_LIBRARIES = $(addprefix $(ARDUINO_HW_DIR)/libraries/,$(shell ls $(ARDUINO_HW_DIR)/libraries))

ARDUINO_TOOLS_DIR = $(ARDUINO_DIR)/hardware/tools

# directory contains compiled core sources
CORE_DIR = $(BUILD_DIR)/core

CORE_CSRC = $(subst $(ARDUINO_CORE_DIR)/,,$(shell find $(ARDUINO_CORE_DIR) -name '*.c'))
CORE_CXXSRC = $(subst $(ARDUINO_CORE_DIR)/,,$(filter-out $(ARDUINO_CORE_DIR)/main.cpp,$(shell find $(ARDUINO_CORE_DIR) -name '*.cpp')))
CORE_OBJS = $(addprefix $(CORE_DIR)/,$(subst .c,.o,$(CORE_CSRC)) $(subst .cpp,.o,$(CORE_CXXSRC)))
CORE_SYSCALL_OBJ = $(filter $(CORE_DIR)/syscalls_sam3$(suffix $(firstword $(CORE_OBJS))), $(CORE_OBJS))
CORE_LIB = $(BUILD_DIR)/arduino_core.a

# linker script
ARDUINO_LINK_SCRIPT = $(addprefix $(ARDUINO_VARIANT_DIR)/,$(shell $(GET_BOARD_META) | grep '^build\.ldscript' | $(GET_META_VALUE)))
LINK_SCRIPT_FLAG = $(addprefix -T,$(ARDUINO_LINK_SCRIPT))

UPLOAD_TOOL := $(addprefix $(ARDUINO_TOOLS_DIR)/,$(shell $(GET_BOARD_META) | grep '^upload\.tool' | $(GET_META_VALUE)))
UPLOAD_SPPED := $(shell $(GET_BOARD_META) | grep '^upload\.speed' | $(GET_META_VALUE))

# define binutils
FALSE=false
CXX = $(FALSE)
CC = $(FALSE)
AR = $(FALSE)
OBJCOPY = $(FALSE)
ifeq ($(MCU_FAMILY),avr)
    CXX = $(ARDUINO_TOOLS_DIR)/avr/bin/avr-g++
    CC = $(ARDUINO_TOOLS_DIR)/avr/bin/avr-gcc
    AR = $(ARDUINO_TOOLS_DIR)/avr/bin/avr-ar
    OBJCOPY = $(ARDUINO_TOOLS_DIR)/avr/bin/avr-objcopy
else
ifeq ($(MCU_FAMILY),sam)
    CXX = $(ARDUINO_TOOLS_DIR)/g++_arm_none_eabi/bin/arm-none-eabi-g++
    CC = $(ARDUINO_TOOLS_DIR)/g++_arm_none_eabi/bin/arm-none-eabi-gcc
    AR = $(ARDUINO_TOOLS_DIR)/g++_arm_none_eabi/bin/arm-none-eabi-ar
    OBJCOPY = $(ARDUINO_TOOLS_DIR)/g++_arm_none_eabi/bin/arm-none-eabi-objcopy
endif
endif

# define platform-depended variables
ifeq ($(MCU_FAMILY),avr)
    MCU_PARAMETER_NAME = -mmcu=
    PLATFORM_DEFINES = 
    PLATFORM_INCLUDES = 
    PLATFORM_COMMON_FLAGS = 
    PLATFORM_CFLAGS = 
    PLATFORM_CXXFLAGS = 
    PLATFORM_LINK_OPTIONS = 
    PLATFORM_ELF_FLAGS = 
    BIN_FILE_SUFFIX = hex
    OBJCOPY_CMD = $(OBJCOPY) -O ihex -j .eeprom --set-section-flags=.eeprom=alloc,load --no-change-warnings --change-section-lma .eeprom=0 $(PROJECT_ELF_FILE) $(subst .elf,.eep,$(PROJECT_ELF_FILE)); \
        $(OBJCOPY) -O ihex -R .eeprom $(PROJECT_ELF_FILE) $(PROJECT_BIN_FILE)
    UPLOAD_CMD = $(UPLOAD_TOOL) -C$(ARDUINO_TOOLS_DIR)/avrdude.conf -vv -p$(DEF_MCU) -c$(PROGRAMMER) -P$(PORT) -b$(UPLOAD_SPPED) -D -Uflash:w:$(PROJECT_BIN_FILE):i
else
ifeq ($(MCU_FAMILY),sam)
    MCU_PARAMETER_NAME = -mcpu=
    ARDUINO_SYSTEM_DIR = $(ARDUINO_HW_DIR)/system
    PLATFORM_DEFINES = USBCON
    PLATFORM_INCLUDES = $(ARDUINO_SYSTEM_DIR)/libsam $(ARDUINO_SYSTEM_DIR)/CMSIS/CMSIS/Include $(ARDUINO_SYSTEM_DIR)/CMSIS/Device/ATMEL
    PLATFORM_COMMON_FLAGS = -ffunction-sections -fdata-sections
    PLATFORM_CFLAGS = 
    PLATFORM_CXXFLAGS = -fno-rtti -fno-exceptions
    PLATFORM_LINK_OPTIONS = 
    PLATFORM_ELF_FLAGS = 
    BIN_FILE_SUFFIX = bin
    
    # sam processors needs additional binaries in core library
    CORE_VARIANT = $(ARDUINO_VARIANT_DIR)/variant.cpp
    CORE_OBJS += $(notdir $(CORE_VARIANT))
    OBJCOPY_CMD = $(OBJCOPY) -O binary $< $@
    UPLOAD_CMD = stty -F $(PORT) cs8 1200 hupcl; $(UPLOAD_TOOL) -U false -e -v -w -b $(PROJECT_BIN_FILE) -R
endif
endif

# Arduino header for include
ARDUINO_HEADER_NAME = Arduino.h

# Arduino file which contains main() function
ARDUINO_MAIN_FILE = $(ARDUINO_CORE_DIR)/main.cpp

# store all generated files in one directory
BUILD_DIR = build-$(TARGET)

# name of file which will contains setup() and loop() functions
PROJECT_MAIN_FILE = $(TARGET)-$(MCU_FAMILY)-$(BOARD_VARIANT).cpp

PROJECT_ELF_FILE = $(BUILD_DIR)/$(TARGET).elf
PROJECT_BIN_FILE = $(BUILD_DIR)/$(TARGET).$(BIN_FILE_SUFFIX)

# source files
CSRC := $(sort $(notdir $(shell find -maxdepth 1 -name '*.c')))
CXXSRC := $(sort $(notdir $(shell find -maxdepth 1 -name '*.cpp')) $(PROJECT_MAIN_FILE))
OBJ = $(addprefix $(BUILD_DIR)/,$(subst .c,.o,$(CSRC)) $(subst .cpp,.o,$(CXXSRC)))

INCLUDES = $(PLATFORM_INCLUDES) $(ARDUINO_CORE_DIR) $(ARDUINO_VARIANT_DIR)
INCLUDES += $(ARDUINO_HW_LIBRARIES)
INCLUDES += $(PWD)
INCLUDE_FLAGS = $(addprefix -I,$(INCLUDES))

# setup defines
DEF_MCU := $(shell $(GET_BOARD_META) | grep '^build\.mcu' | $(GET_META_VALUE))
MCU_FLAG = $(addprefix $(MCU_PARAMETER_NAME),$(DEF_MCU))
DEF_F_CPU := $(shell $(GET_BOARD_META) | grep '^build\.f_cpu' | $(GET_META_VALUE))
DEF_F_CPU_FLAG = $(addprefix F_CPU=,$(DEF_F_CPU))
DEF_PID := $(shell $(GET_BOARD_META) | grep '^build\.pid' | $(GET_META_VALUE))
ifeq ($(DEF_PID),)
    DEF_PID = null
endif
DEF_PID_FLAG = $(addprefix USB_PID=,$(DEF_PID))
DEF_VID := $(shell $(GET_BOARD_META) | grep '^build\.vid' | $(GET_META_VALUE))
ifeq ($(DEF_VID),)
    DEF_VID = null
endif
DEF_VID_FLAG = $(addprefix USB_VID=,$(DEF_VID))
DEF_BOARD := $(shell $(GET_BOARD_META) | grep '^build\.board' | $(GET_META_VALUE))
DEF_BOARD_FLAG = $(addprefix BOARD=,$(DEF_BOARD))

# define flags
DEFINES = printf=iprintf $(DEF_F_CPU_FLAG) ARDUINO=$(ARDUINO_VERSION) $(DEF_PID_FLAG) $(DEF_VID_FLAG) $(DEF_BOARD_FLAG) $(PLATFORM_DEFINES)
DEFINE_FLAGS = $(addprefix -D,$(DEFINES))

LINK_OPTIONS = --cref --check-sections --gc-sections --entry=Reset_Handler --unresolved-symbols=report-all --warn-common --warn-section-align --warn-unresolved-symbols -Map,$(BUILD_DIR)/$(subst .cpp,.map,$(PROJECT_MAIN_FILE))
LINK_OPTIONS += $(PLATFORM_LINK_OPTIONS)
LINK_FLAGS = $(addprefix -Wl$(comma),$(LINK_OPTIONS)) $(LINK_SCRIPT_FLAG)

# define buil elf file features
ARDUINO_VARIANT_LIB := $(addprefix $(ARDUINO_VARIANT_DIR)/,$(shell $(GET_BOARD_META) | grep '^build\.variant_system_lib' | $(GET_META_VALUE)))

EXTRA_FLAGS := $(shell $(GET_BOARD_META) | grep '^build\.extra_flags' | $(GET_META_VALUE))

# compilation flags common to both c and c++
WARNINGS = all
WARNING_FLAGS = $(addprefix -W,$(WARNINGS))
COMMON_FLAGS = -lm -lm -lgcc -g -Os --param max-inline-insns-single=500 $(MCU_FLAG) $(WARNING_FLAGS) $(EXTRA_FLAGS) $(PLATFORM_COMMON_FLAGS)
#COMMON_FLAGS += -nostdlib
CFLAGS = $(PLATFORM_CFLAGS) $(COMMON_FLAGS)
CXXFLAGS = $(PLATFORM_CXXFLAGS) $(COMMON_FLAGS)

TARGET_HEX = $(TARGET).hex

all: build

$(BUILD_DIR):
	mkdir -p $@
	
$(CORE_DIR): | $(BUILD_DIR)
	mkdir -p $@
	
$(PROJECT_MAIN_FILE): $(SKETCH_FILE) | $(BUILD_DIR)
	@echo "\
	// #############################################################################\n\
	// ##            AUTOGENERATED FILE - ANY CHAGES WILL BE UNDONE               ##\n\
	// #############################################################################\n" > $(PROJECT_MAIN_FILE)
	echo "#include <$(ARDUINO_HEADER_NAME)>" >> $(PROJECT_MAIN_FILE)
	echo "\n" | cat $(SKETCH_FILE) - $(ARDUINO_MAIN_FILE) >> $(PROJECT_MAIN_FILE)

$(BUILD_DIR)/%.o: %.c | $(BUILD_DIR)
	$(CC) -c $(CFLAGS) $(INCLUDE_FLAGS) $(DEFINE_FLAGS) -o $@ $<

$(BUILD_DIR)/%.o: %.cpp | $(BUILD_DIR)
	$(CXX) -c $(CXXFLAGS) $(INCLUDE_FLAGS) $(DEFINE_FLAGS) -o $@ $<

$(PROJECT_ELF_FILE): $(CORE_LIB) $(PROJECT_MAIN_FILE) $(OBJ) | $(BUILD_DIR)
	$(CXX) $(LINK_FLAGS) $(CORE_SYSCALL_OBJ) $(OBJ) $(ARDUINO_VARIANT_LIB) $(CORE_LIB) $(CXXFLAGS) -o $@

$(PROJECT_BIN_FILE): $(PROJECT_ELF_FILE) | $(BUILD_DIR)
	$(OBJCOPY_CMD)

build: $(PROJECT_BIN_FILE)

upload: build
	$(UPLOAD_CMD)

# arduino core library
$(CORE_DIR)/%.o: $(ARDUINO_CORE_DIR)/%.c | $(CORE_DIR)
	if test -n $(subst $(notdir $^),,$(subst $(ARDUINO_CORE_DIR)/,,$^)); then mkdir -p $(CORE_DIR)/$(subst $(notdir $^),,$(subst $(ARDUINO_CORE_DIR)/,,$^)); fi
	$(CC) -c $(CFLAGS) $(INCLUDE_FLAGS) $(DEFINE_FLAGS) -o $@ $^

$(CORE_DIR)/%.o: $(ARDUINO_CORE_DIR)/%.cpp | $(CORE_DIR)
	if test -n $(subst $(notdir $^),,$(subst $(ARDUINO_CORE_DIR)/,,$^)); then mkdir -p $(CORE_DIR)/$(subst $(notdir $^),,$(subst $(ARDUINO_CORE_DIR)/,,$^)); fi
	$(CXX) -c $(CXXFLAGS) $(INCLUDE_FLAGS) $(DEFINE_FLAGS) -o $@ $^

$(CORE_DIR)/%.o: $(CORE_VARIANT) | $(CORE_DIR)
	$(CXX) -c $(CXXFLAGS) $(INCLUDE_FLAGS) $(DEFINE_FLAGS) -o $@ $^

$(CORE_LIB): $(CORE_OBJS) | $(CORE_DIR)
	$(AR) $(ARFLAGS) $@ $^

show-variants:
	@echo Supported board variants:
	@for board in $$(echo $(ARDUINO_BOARDS_LIST)); do \
		for i in $$(grep -v -P '^#|^[\s]*$$' $$board | cut -d '.' -f 1 | uniq); do \
			if grep "^$${i}\.menu\.cpu" $$board > /dev/null; then \
				grep -o "^$${i}\.menu\.cpu\.[^\.=]\+" $$board | uniq | sed 's/\..*\./ /g' | sed 's/\(.*\)/  \1/g'; \
			else \
				echo $$i | sed 's/\(.*\)/  \1/g'; \
			fi \
		done \
	done

clean:
	rm -f $(PROJECT_MAIN_FILE)
	rm -rf $(BUILD_DIR)

help:
	@echo "\
Available targets:\n\
\n\
  make\n\
  make clean\n\
  make help\
"

# include dependecy
DEP_DIR = $(BUILD_DIR)/dep
-include $(addprefix $(DEP_DIR)/,$(subst .c,.d,$(CSRC)))
-include $(addprefix $(DEP_DIR)/,$(subst .cpp,.d,$(CXXSRC)))

# create dependency directory
$(DEP_DIR): | $(BUILD_DIR)
	mkdir -p $@

$(DEP_DIR)/%.d: %.cpp $(PROJECT_MAIN_FILE) | $(DEP_DIR)
	$(create-dep)

$(DEP_DIR)/%.d: %.c | $(DEP_DIR)
	$(create-dep)

define create-dep
	$(CC) -M $(INCLUDE_FLAGS) $(DEFINE_FLAGS) $(MCU_FLAG) $< > $@.$$$$; \
	sed 's,\($*\)\.o[ :]*,$(BUILD_DIR)/\1.o $@ : ,g' < $@.$$$$ > $@; \
	rm -f $@.$$$$
endef

.PHONY: all clean help upload build show-variants


test:
	@echo $(MAKEFILE_LIST)
