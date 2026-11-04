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
        # 相对尺寸 + 小屏收缩：保证底部按钮永远有位置
        _w, _h = self._gtk.content_width, self._gtk.content_height
        _ratio = 0.25 if _h >= 600 else 0.18
        logo_size = min(_w, _h) * _ratio
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
            halign=Gtk.Align.FILL,
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
        _reserved = int(logo_size) + 150  # 品牌行 + 圆点 + 底部按钮
        _scroll_h = max(80, min(int(_h * 0.33), max(80, _h - _reserved)))
        self.text_scroll.set_size_request(-1, _scroll_h)
        self.text_scroll.set_propagate_natural_height(False)
        self.text_scroll.set_hexpand(False)
        self.text_scroll.set_halign(Gtk.Align.CENTER)
        self._scroll_h = _scroll_h
        # 分页行数必须与错误框可视高度匹配；固定 6 行会在长段落最后一行
        # 留下半句，产生短句/断句。
        self._max_lines = max(6, int(_scroll_h / max(1, self._gtk.font_size * 1.15)))
        self.text_scroll.add(self.labels["text"])

        self.labels["dots"] = Gtk.Label(label="●  ○  ○", halign=Gtk.Align.CENTER)
        self.labels["dots"].get_style_context().add_class("splash_dots")

        # Woloong: 错误信息可能很长，按固定行数分页，从最后一页开始向上循环
        self._page_source = None
        self._page = 0
        self._pages = 1
        self._full_lines = []
        self._last_text = None

        content_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content_box.set_halign(Gtk.Align.CENTER)
        content_box.set_hexpand(False)
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

    def _reflow(self, text):
        """合并 Klipper 源文本中的硬换行续行，保留真正的独立行。"""
        lines = []
        for raw in text.splitlines():
            line = raw.strip()
            if not line:
                lines.append("")
                continue
            if (
                lines
                and lines[-1]
                and not lines[-1].endswith((".", "!", "?", ":"))
                and (line[0].islower() or line[0] in "\"'([")
            ):
                lines[-1] = lines[-1] + " " + line
            else:
                lines.append(line)
        return "\n".join(lines)

    def _wrap_lines(self, text, width):
        """按逻辑行分页，保证完整句子不跨页。"""
        text = self._reflow(text)
        layout = Pango.Layout(self.labels["text"].get_pango_context())
        layout.set_width(width * Pango.SCALE)
        layout.set_wrap(Pango.WrapMode.WORD_CHAR)
        units = []
        for raw in text.splitlines():
            unit = raw.strip()
            if not unit:
                units.append([""])
                continue
            layout.set_text(unit, -1)
            ulines = []
            for i in range(layout.get_line_count()):
                line = layout.get_line(i)
                start = line.start_index
                end = start + line.length
                ulines.append(unit[start:end].rstrip())
            if ulines:
                units.append(ulines)
        while units and not units[-1][0]:
            units.pop()
        pages, cur = [], []
        for ulines in units:
            if cur and len(cur) + len(ulines) > self._max_lines:
                pages.append(cur)
                cur = []
            cur.extend(ulines)
        if cur:
            pages.append(cur)
        return pages or [[""]]

    def update_text(self, text):
        text = str(text)
        # 错误状态可能每 4 秒重复上报同一消息；重复刷新会把分页重置到最后一页，
        # 导致页面永远不翻页。消息未变化时保留当前页和定时器。
        if text == self._last_text and self._page_source is not None:
            return
        self._last_text = text
        # 固定错误信息块宽度：不能按当前页的短行决定宽度，否则长句会被
        # 压成很窄的列，短句也会出现异常断行。
        max_width = max(100, int(self._gtk.content_width * 0.78))
        self._page_lines = self._wrap_lines(text, max_width)
        self._pages = max(1, len(self._page_lines))
        self.text_scroll.set_size_request(max_width, self._scroll_h)
        # Start from the last page (the bottom) and move upward.
        self._page = self._pages - 1
        self._render_page()
        self._schedule_pages()
        self.show_restart_buttons()

    def _render_page(self):
        lines = self._page_lines[self._page]
        self.labels["text"].set_label("\n".join(lines) or " ")
        self.labels["dots"].set_label("  ".join("●" if i == self._page else "○" for i in range(self._pages)))

    def _stop_pages(self):
        if self._page_source is not None:
            GLib.source_remove(self._page_source)
            self._page_source = None

    def _schedule_pages(self):
        self._stop_pages()
        if self._pages > 1:
            self._page_source = GLib.timeout_add_seconds(6, self._next_page)

    def _next_page(self):
        if self._pages <= 1:
            self._page_source = None
            return False
        self._page = self._page - 1 if self._page > 0 else self._pages - 1
        self._render_page()
        return True

    def deactivate(self):
        self._stop_pages()

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
