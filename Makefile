.PHONY: build release install uninstall clean deb

build:
	cargo build

release:
	cargo build --release

install: release
	install -Dm755 target/release/typetune $(DESTDIR)/usr/bin/typetune
	install -Dm755 target/release/typetune-gui $(DESTDIR)/usr/bin/typetune-gui
	install -Dm644 packaging/typetune.desktop $(DESTDIR)/usr/share/applications/typetune.desktop
	install -Dm644 packaging/typetune.service $(DESTDIR)/usr/lib/systemd/user/typetune.service
	install -Dm644 config/default.toml $(DESTDIR)/etc/typetune/config.toml
	install -Dm644 dict/ru.txt $(DESTDIR)/usr/share/typetune/dict/ru.txt
	install -Dm644 dict/en.txt $(DESTDIR)/usr/share/typetune/dict/en.txt
	install -Dm644 resources/icons/hicolor/scalable/status/typetune-active.svg $(DESTDIR)/usr/share/icons/hicolor/scalable/status/typetune-active.svg
	install -Dm644 resources/icons/hicolor/scalable/status/typetune-disabled.svg $(DESTDIR)/usr/share/icons/hicolor/scalable/status/typetune-disabled.svg

uninstall:
	rm -f $(DESTDIR)/usr/bin/typetune
	rm -f $(DESTDIR)/usr/bin/typetune-gui
	rm -f $(DESTDIR)/usr/share/applications/typetune.desktop
	rm -f $(DESTDIR)/usr/lib/systemd/user/typetune.service
	rm -rf $(DESTDIR)/etc/typetune
	rm -rf $(DESTDIR)/usr/share/typetune
	rm -f $(DESTDIR)/usr/share/icons/hicolor/scalable/status/typetune-*.svg

clean:
	cargo clean
