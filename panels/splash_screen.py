import logging
import os

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk, Pango
from ks_includes.screen_panel import ScreenPanel


class Panel(ScreenPanel):

    def __init__(self, screen, title):
        super().__init__(screen, title)

        self.labels["menu"] = self._gtk.Button("settings", _("Menu"), "color4")
        self.labels["menu"].connect("clicked", self._screen._go_to_submenu, "")
        self.labels["restart"] = self._gtk.Button(
            "refresh", _("Klipper Restart"), "color1"
        )
        self.labels["restart"].connect("clicked", self.restart_klipper)
        self.labels["firmware_restart"] = self._gtk.Button(
            "refresh", _("Firmware Restart"), "color2"
        )
        self.labels["firmware_restart"].connect("clicked", self.firmware_restart)
        self.labels["restart_system"] = self._gtk.Button(
            "refresh", _("System Restart"), "color1"
        )
        self.labels["restart_system"].connect("clicked", self.reboot_poweroff, "reboot")
        self.labels["shutdown"] = self._gtk.Button(
            "shutdown", _("System Shutdown"), "color2"
        )
        self.labels["shutdown"].connect("clicked", self.reboot_poweroff, "shutdown")
        self.labels["retry"] = self._gtk.Button("load", _("Retry"), "color3")
        self.labels["retry"].connect("clicked", self.retry)

        self.labels["actions"] = Gtk.Box(hexpand=True, vexpand=False, homogeneous=True)

        # --- Woloong 品牌启动画面（本 fork 的唯一代码定制）---
        # 上游若改动本段，woloong-fork-sync 会报基线漂移，需人工重锚定后再重跑。
        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        main.set_homogeneous(False)

        top_spacer = Gtk.Box()
        top_spacer.set_vexpand(True)
        main.pack_start(top_spacer, True, True, 0)

        # Logo：取屏幕短边 25%（垂直居中偏上）
        logo_size = min(self._gtk.content_width, self._gtk.content_height) * 0.25
        image = self._gtk.Image("klipper", logo_size, logo_size)
        image.set_halign(Gtk.Align.CENTER)
        image.set_valign(Gtk.Align.CENTER)

        self.labels["brand"] = Gtk.Label(
            label="WOOLONG",
            halign=Gtk.Align.CENTER,
            valign=Gtk.Align.CENTER,
        )
        self.labels["brand"].get_style_context().add_class("splash_brand")

        self.labels["text"] = Gtk.Label(
            label=_("Initializing printer..."),
            wrap=True,
            wrap_mode=Pango.WrapMode.WORD_CHAR,
            halign=Gtk.Align.CENTER,
            valign=Gtk.Align.CENTER,
        )
        self.labels["text"].get_style_context().add_class("splash_status")
        self.labels["text"].set_valign(Gtk.Align.START)
        self.labels["text"].set_hexpand(True)
        self.labels["text"].set_xalign(0.0)
        self.labels["text"].set_margin_start(24)
        self.labels["text"].set_margin_end(24)
        # 固定高度的滚动区：错误信息再长也不会把底部按钮挤出屏幕
        self.text_scroll = Gtk.ScrolledWindow()
        self.text_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.EXTERNAL)
        self.text_scroll.set_size_request(-1, max(96, int(self._gtk.content_height * 0.30)))
        self.text_scroll.set_propagate_natural_height(False)
        self.text_scroll.set_hexpand(True)
        self.text_scroll.set_halign(Gtk.Align.FILL)
        self.text_scroll.add(self.labels["text"])

        self.labels["dots"] = Gtk.Label(label="●  ○  ○", halign=Gtk.Align.CENTER)
        self.labels["dots"].get_style_context().add_class("splash_dots")

        # Woloong: 错误信息可能很长，限制每次显示行数并自动翻页，避免把底部按钮挤出屏幕
        self._max_lines = 6
        self._page = 0
        self._pages = 1
        self._rotate_source = None
        self._full_lines = []

        content_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content_box.set_halign(Gtk.Align.FILL)
        content_box.set_hexpand(True)
        content_box.set_valign(Gtk.Align.CENTER)
        content_box.pack_start(image, False, True, 0)
        content_box.pack_start(self.labels["brand"], False, True, 0)
        content_box.pack_start(self.text_scroll, False, True, 0)
        content_box.pack_start(self.labels["dots"], False, True, 0)
        main.pack_start(content_box, False, True, 0)

        bottom_spacer = Gtk.Box()
        bottom_spacer.set_vexpand(True)
        main.pack_start(bottom_spacer, True, True, 0)

        main.pack_end(self.labels["actions"], False, False, 0)

        self.show_restart_buttons()

        self.content.add(main)

    def update_text(self, text):
        self._full_lines = str(text).splitlines() or [""]
        self._page = 0
        self._render_page()
        self.show_restart_buttons()

    def _render_page(self):
        self.labels["text"].set_label("\n".join(self._full_lines))
        self._schedule_rotation()

    def _schedule_rotation(self):
        if self._rotate_source is not None:
            GLib.source_remove(self._rotate_source)
            self._rotate_source = None
        GLib.idle_add(self._check_overflow)

    def _check_overflow(self):
        if not hasattr(self, "text_scroll"):
            return False
        adj = self.text_scroll.get_vadjustment()
        if adj.get_upper() <= adj.get_page_size() + 1:
            return False
        if self._rotate_source is None:
            self._rotate_source = GLib.timeout_add_seconds(6, self._scroll_step)
        return False

    def _scroll_step(self):
        adj = self.text_scroll.get_vadjustment()
        page = adj.get_page_size()
        upper = adj.get_upper()
        new_val = adj.get_value() + page * 0.9
        if new_val >= upper - page:
            new_val = 0
        adj.set_value(new_val)
        return True

    def clear_action_bar(self):
        for child in self.labels["actions"].get_children():
            self.labels["actions"].remove(child)

    def show_restart_buttons(self):

        self.clear_action_bar()
        if self.ks_printer_cfg is not None and self._screen._ws.connected:
            power_devices = self.ks_printer_cfg.get("power_devices", "")
            if power_devices and self._printer.get_power_devices():
                logging.info(f"Associated power devices: {power_devices}")
                self.add_power_button(power_devices)

        if self._screen.initialized:
            self.labels["actions"].add(self.labels["restart"])
            self.labels["actions"].add(self.labels["firmware_restart"])
        else:
            self.labels["actions"].add(self.labels["restart_system"])
            self.labels["actions"].add(self.labels["shutdown"])
        self.labels["actions"].add(self.labels["menu"])
        if (
            self._screen._ws
            and not self._screen._ws.connecting
            or self._screen.reinit_count > self._screen.max_retries
        ):
            self.labels["actions"].add(self.labels["retry"])
        self.labels["actions"].show_all()

    def add_power_button(self, powerdevs):
        self.labels["power"] = self._gtk.Button(
            "shutdown", _("Power On Printer"), "color3"
        )
        self.labels["power"].connect(
            "clicked", self._screen.power_devices, powerdevs, True
        )
        self.check_power_status()
        self.labels["actions"].add(self.labels["power"])

    def activate(self):
        self.check_power_status()

    def check_power_status(self):
        if "power" in self.labels:
            devices = self._printer.get_power_devices()
            if devices is not None:
                for device in devices:
                    if self._printer.get_power_device_status(device) == "off":
                        self.labels["power"].set_sensitive(True)
                        break
                    elif self._printer.get_power_device_status(device) == "on":
                        self.labels["power"].set_sensitive(False)

    def firmware_restart(self, widget):
        self._screen._ws.klippy.restart_firmware()

    def restart_klipper(self, widget):
        self._screen._ws.klippy.restart()

    def retry(self, widget):
        logging.debug("User retrying connection")
        self._screen.connect_printer(self._screen.connecting_to_printer)
        self.show_restart_buttons()

    def reboot_poweroff(self, widget, method):
        label = Gtk.Label(wrap=True, hexpand=True, vexpand=True)
        if method == "reboot":
            label.set_label(_("Are you sure you wish to reboot the system?"))
            title = _("Restart")
        else:
            label.set_label(_("Are you sure you wish to shutdown the system?"))
            title = _("Shutdown")
        buttons = [
            {
                "name": _("Host"),
                "response": Gtk.ResponseType.OK,
                "style": "dialog-info",
            },
            {
                "name": _("Cancel"),
                "response": Gtk.ResponseType.CANCEL,
                "style": "dialog-error",
            },
        ]
        if self._screen._ws.connected:
            buttons.insert(
                1,
                {
                    "name": _("Printer"),
                    "response": Gtk.ResponseType.APPLY,
                    "style": "dialog-warning",
                },
            )
        self._gtk.Dialog(title, buttons, label, self.reboot_poweroff_confirm, method)

    def reboot_poweroff_confirm(self, dialog, response_id, method):
        self._gtk.remove_dialog(dialog)
        if response_id == Gtk.ResponseType.OK:
            if method == "reboot":
                os.system("systemctl reboot -i")
            else:
                os.system("systemctl poweroff -i")
        elif response_id == Gtk.ResponseType.APPLY:
            if method == "reboot":
                self._screen._ws.send_method("machine.reboot")
            else:
                self._screen._ws.send_method("machine.shutdown")
