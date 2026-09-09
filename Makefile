.PHONY: build release install uninstall clean deb

build:
	cargo build

release:
	cargo build --release

install: release
	install -Dm755 target/release/tunetype $(DESTDIR)/usr/bin/tunetype
	install -Dm755 target/release/tunetype-gui $(DESTDIR)/usr/bin/tunetype-gui
	install -Dm644 packaging/tunetype.desktop $(DESTDIR)/usr/share/applications/tunetype.desktop
	install -Dm644 packaging/tunetype.service $(DESTDIR)/usr/lib/systemd/user/tunetype.service
	install -Dm644 config/default.toml $(DESTDIR)/etc/tunetype/config.toml
	install -Dm644 dict/ru.txt $(DESTDIR)/usr/share/tunetype/dict/ru.txt
	install -Dm644 dict/en.txt $(DESTDIR)/usr/share/tunetype/dict/en.txt
	install -Dm644 resources/icons/hicolor/scalable/status/tunetype-active.svg $(DESTDIR)/usr/share/icons/hicolor/scalable/status/tunetype-active.svg
	install -Dm644 resources/icons/hicolor/scalable/status/tunetype-disabled.svg $(DESTDIR)/usr/share/icons/hicolor/scalable/status/tunetype-disabled.svg

uninstall:
	rm -f $(DESTDIR)/usr/bin/tunetype
	rm -f $(DESTDIR)/usr/bin/tunetype-gui
	rm -f $(DESTDIR)/usr/share/applications/tunetype.desktop
	rm -f $(DESTDIR)/usr/lib/systemd/user/tunetype.service
	rm -rf $(DESTDIR)/etc/tunetype
	rm -rf $(DESTDIR)/usr/share/tunetype
	rm -f $(DESTDIR)/usr/share/icons/hicolor/scalable/status/tunetype-*.svg

clean:
	cargo clean
