.PHONY: app run test install clean

app:
	./scripts/bundle.sh release

run: app
	-pkill -x MaKeep
	open build/MaKeep.app

test:
	swift test

install: app
	-pkill -x MaKeep
	rm -rf /Applications/MaKeep.app
	cp -R build/MaKeep.app /Applications/
	open /Applications/MaKeep.app

clean:
	rm -rf .build build
