all: build/suwaneeforth build/system.forth

clean:
	xcodebuild clean

build/suwaneeforth build/system.forth: forth/kernel.swift forth/system.forth
	xcodebuild -target suwaneeforth

