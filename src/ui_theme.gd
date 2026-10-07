class_name KingdomUiTheme extends RefCounted

## Charcoal, aged bronze and ivory carry the war-table palette across the UI.
const INK: Color = Color("171819")
const PANEL: Color = Color("252523")
const PANEL_RAISED: Color = Color("34332e")
const BORDER: Color = Color("70634e")
const GOLD: Color = Color("d9bd7d")
const TEXT: Color = Color("f1ead9")
const MUTED: Color = Color("c3bcaa")
const DISABLED: Color = Color("928b7e")


static func create(font: Font) -> Theme:
	var result: Theme = Theme.new()
	result.default_font = font
	result.default_font_size = 16
	for type: String in ["Label", "RichTextLabel", "LineEdit", "TextEdit", "SpinBox", "OptionButton"]:
		result.set_color("font_color", type, TEXT)
	result.set_type_variation("TitleLabel", "Label")
	result.set_font_size("font_size", "TitleLabel", 22)
	result.set_color("font_color", "TitleLabel", GOLD)
	result.set_type_variation("SectionLabel", "Label")
	result.set_font_size("font_size", "SectionLabel", 18)
	result.set_color("font_color", "SectionLabel", GOLD)
	result.set_type_variation("MutedLabel", "Label")
	result.set_font_size("font_size", "MutedLabel", 14)
	result.set_color("font_color", "MutedLabel", MUTED)
	result.set_color("default_color", "RichTextLabel", TEXT)
	result.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.28))
	result.set_constant("shadow_offset_y", "Label", 1)
	for type: String in ["VBoxContainer", "HBoxContainer"]:
		result.set_constant("separation", type, 8)
	result.set_constant("h_separation", "GridContainer", 8)
	result.set_constant("v_separation", "GridContainer", 6)
	result.set_stylebox("panel", "Panel", _box(PANEL, BORDER, 1, 14, 12))
	result.set_stylebox("panel", "PanelContainer", _box(PANEL, BORDER, 1, 14, 12))
	result.set_type_variation("SectionPanel", "PanelContainer")
	result.set_stylebox("panel", "SectionPanel", _box(PANEL, BORDER, 1, 14, 12))
	result.set_type_variation("ResourcePanel", "PanelContainer")
	result.set_stylebox("panel", "ResourcePanel", _box(INK, Color("847051"), 1, 10, 8))
	result.set_type_variation("InsetPanel", "PanelContainer")
	result.set_stylebox("panel", "InsetPanel", _box(INK, BORDER.darkened(0.2), 1, 10, 8))
	_buttons(result, "Button", PANEL_RAISED, BORDER)
	for variant: String in ["PrimaryButton", "NavButton", "UtilityButton"]:
		result.set_type_variation(variant, "Button")
	_buttons(result, "PrimaryButton", Color("514531"), Color("bca56d"))
	result.set_color("font_color", "PrimaryButton", Color("fff0c9"))
	_buttons(result, "NavButton", Color("282926"), Color("76664e"))
	_buttons(result, "UtilityButton", Color("292a27"), Color("645b4b"))
	result.set_font_size("font_size", "UtilityButton", 14)
	for type: String in ["OptionButton", "CheckBox", "CheckButton"]:
		_buttons(result, type, PANEL_RAISED, BORDER)
	result.set_constant("h_separation", "CheckBox", 9)
	result.set_constant("h_separation", "CheckButton", 9)
	for type: String in ["CheckBox", "CheckButton"]:
		for suffix: String in ["", "_disabled"]:
			var tint: Color = GOLD if suffix.is_empty() else DISABLED
			result.set_icon("checked" + suffix, type, _check_icon(tint, true))
			result.set_icon("unchecked" + suffix, type, _check_icon(tint, false))
	result.set_icon("arrow", "OptionButton", _svg_icon('<path d="M4 7 L10 13 L16 7" fill="none" stroke="#d9bd7d" stroke-width="2"/>', 20, 20))
	for type: String in ["LineEdit", "TextEdit"]:
		result.set_stylebox("normal", type, _box(INK, BORDER, 1, 10, 8))
		result.set_stylebox("read_only", type, _box(Color("1e201f"), Color("4e493f"), 1, 10, 8))
		result.set_stylebox("focus", type, _focus())
		result.set_color("font_color", type, TEXT)
		result.set_color("font_readonly_color", type, MUTED)
		result.set_color("font_uneditable_color", type, MUTED)
		result.set_color("font_placeholder_color", type, Color("b1a793"))
		result.set_color("font_selected_color", type, TEXT)
		result.set_color("selection_color", type, Color(0.56, 0.48, 0.27, 0.5))
		result.set_color("caret_color", type, GOLD)
	result.set_stylebox("panel", "PopupPanel", _box(PANEL, GOLD.darkened(0.3), 1, 14, 12))
	result.set_stylebox("panel", "PopupMenu", _box(PANEL, BORDER, 1, 8, 8))
	result.set_stylebox("hover", "PopupMenu", _box(PANEL_RAISED.lightened(0.09), GOLD.darkened(0.12), 1, 8, 6))
	result.set_color("font_color", "PopupMenu", TEXT)
	result.set_color("font_hover_color", "PopupMenu", Color("fff4d7"))
	result.set_color("font_disabled_color", "PopupMenu", DISABLED)
	result.set_stylebox("panel", "AcceptDialog", _box(PANEL, BORDER, 1, 14, 12))
	var window_border: StyleBoxFlat = _box(PANEL, Color("a39161"), 1, 10, 10)
	window_border.expand_margin_top = 34
	window_border.shadow_color = Color(0, 0, 0, 0.35)
	window_border.shadow_size = 7
	result.set_stylebox("embedded_border", "Window", window_border)
	result.set_color("title_color", "Window", GOLD)
	result.set_font("title_font", "Window", font)
	result.set_font_size("title_font_size", "Window", 17)
	result.set_constant("title_height", "Window", 34)
	for type: String in ["TabContainer", "TabBar"]:
		result.set_stylebox("tab_selected", type, _box(PANEL_RAISED, GOLD.darkened(0.25), 1, 12, 9))
		result.set_stylebox("tab_unselected", type, _box(INK, BORDER.darkened(0.2), 1, 12, 9))
		result.set_stylebox("tab_hovered", type, _box(PANEL_RAISED.lightened(0.06), GOLD.darkened(0.1), 1, 12, 9))
		result.set_stylebox("tab_disabled", type, _box(INK, BORDER.darkened(0.4), 1, 12, 9))
		result.set_stylebox("tab_focus", type, _focus())
		result.set_color("font_selected_color", type, GOLD)
		result.set_color("font_unselected_color", type, MUTED)
		result.set_color("font_hovered_color", type, TEXT)
		result.set_color("font_disabled_color", type, DISABLED)
		result.set_font_size("font_size", type, 16)
	result.set_stylebox("panel", "TabContainer", _box(PANEL, BORDER, 1, 12, 12))
	result.set_stylebox("background", "ProgressBar", _box(INK, BORDER, 1, 1, 1))
	result.set_stylebox("fill", "ProgressBar", _box(Color("a68e57"), GOLD.darkened(0.2), 0, 1, 1))
	result.set_color("font_color", "ProgressBar", TEXT)
	var grabber: Texture2D = _svg_icon('<path d="M11 2 L19 11 L11 20 L3 11 Z" fill="#d9bd7d" stroke="#f1ead9" stroke-width="1"/>', 22, 22)
	var highlighted_grabber: Texture2D = _svg_icon('<path d="M11 1 L20 11 L11 21 L2 11 Z" fill="#fff0bd" stroke="#d9bd7d" stroke-width="2"/>', 22, 22)
	for type: String in ["HSlider", "VSlider"]:
		result.set_stylebox("slider", type, _box(INK, BORDER, 1, 3, 3))
		result.set_stylebox("grabber_area", type, _box(Color("7b6848"), Color("a48b5b"), 0, 3, 3))
		result.set_stylebox("grabber_area_highlight", type, _box(Color("a18c55"), GOLD, 0, 3, 3))
		result.set_icon("grabber", type, grabber)
		result.set_icon("grabber_highlight", type, highlighted_grabber)
		result.set_icon("grabber_disabled", type, _svg_icon('<path d="M11 2 L19 11 L11 20 L3 11 Z" fill="#928b7e"/>', 22, 22))
	for type: String in ["HScrollBar", "VScrollBar"]:
		result.set_stylebox("scroll", type, _box(INK, Color.TRANSPARENT, 0, 2, 2))
		result.set_stylebox("grabber", type, _box(Color("736754"), Color.TRANSPARENT, 0, 4, 4))
		result.set_stylebox("grabber_highlight", type, _box(Color("93845a"), Color.TRANSPARENT, 0, 4, 4))
		result.set_stylebox("grabber_pressed", type, _box(GOLD, Color.TRANSPARENT, 0, 4, 4))
	result.set_stylebox("separator", "HSeparator", _box(BORDER, Color.TRANSPARENT, 0, 0, 0))
	return result


static func _buttons(theme: Theme, type: String, background: Color, border: Color) -> void:
	theme.set_stylebox("normal", type, _box(background, border, 1, 12, 9))
	theme.set_stylebox("hover", type, _box(background.lightened(0.09), GOLD.darkened(0.12), 1, 12, 9))
	theme.set_stylebox("pressed", type, _box(Color("574930"), GOLD, 1, 12, 9))
	theme.set_stylebox("hover_pressed", type, _box(Color("5b4b30"), GOLD, 1, 12, 9))
	theme.set_stylebox("disabled", type, _box(Color("222321"), Color("514a3e"), 1, 12, 9))
	theme.set_stylebox("focus", type, _focus())
	theme.set_color("font_color", type, TEXT)
	theme.set_color("font_hover_color", type, Color("fff4d7"))
	theme.set_color("font_pressed_color", type, GOLD)
	theme.set_color("font_hover_pressed_color", type, GOLD)
	theme.set_color("font_focus_color", type, TEXT)
	theme.set_color("font_disabled_color", type, DISABLED)


static func _box(background: Color, border: Color, width: int, horizontal: float, vertical: float) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(3)
	box.content_margin_left = horizontal
	box.content_margin_right = horizontal
	box.content_margin_top = vertical
	box.content_margin_bottom = vertical
	return box


static func _focus() -> StyleBoxFlat:
	var box: StyleBoxFlat = _box(Color.TRANSPARENT, Color("ffe3a0"), 2, 0, 0)
	box.draw_center = false
	return box


static func _check_icon(tint: Color, checked: bool) -> Texture2D:
	var mark: String = '<path d="M5 11 L9 15 L17 6" fill="none" stroke="#%s" stroke-width="2"/>' % tint.to_html(false) if checked else ""
	return _svg_icon('<rect x="2" y="2" width="18" height="18" rx="2" fill="#171819" stroke="#%s" stroke-width="1.5"/>%s' % [tint.to_html(false), mark], 22, 22)


static func _svg_icon(body: String, width: int, height: int) -> Texture2D:
	var image: Image = Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>' % [width, height, width, height, body])
	return ImageTexture.create_from_image(image)
