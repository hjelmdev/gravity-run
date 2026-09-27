extends Control

@export var icon_name := "inventory"

func _draw() -> void:
	var ink := Color("edf3ff")
	var accent := Color("42d6c5")
	if icon_name == "shop":
		# A storefront: awning, shop front, door and display window.
		draw_rect(Rect2(5, 12, 20, 15), ink, false, 2.0)
		draw_line(Vector2(3, 12), Vector2(27, 12), accent, 2.5)
		draw_line(Vector2(5, 9), Vector2(25, 9), ink, 2.0)
		draw_line(Vector2(5, 9), Vector2(3, 12), ink, 2.0)
		draw_line(Vector2(25, 9), Vector2(27, 12), ink, 2.0)
		draw_rect(Rect2(8, 16, 7, 6), accent, false, 1.5)
		draw_rect(Rect2(18, 18, 4, 9), ink, false, 1.5)
	else:
		# Inventory bag and handle, rendered as vector geometry (no font glyph dependency).
		draw_rect(Rect2(5, 11, 20, 17), ink, false, 2.0)
		draw_line(Vector2(10, 12), Vector2(10, 8), accent, 2.0)
		draw_line(Vector2(20, 12), Vector2(20, 8), accent, 2.0)
		draw_line(Vector2(10, 8), Vector2(20, 8), accent, 2.0)
		draw_line(Vector2(5, 16), Vector2(25, 16), ink, 1.5)
