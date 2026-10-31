## GoldFrame : RefCounted
## 「已达成 / 已完成」条目用的 1pt 金色细框（rgb(228, 158, 0)），自绘、铺满整行。
## 自绘而不是 Panel + StyleBox：细框永远压在所有兄弟节点之上（包括焦点扫光、文字），
## 选中（整行变白）时也不会被盖掉。
##   const GOLD_FRAME = preload("res://scenes/ui/GoldFrame.gd")
##   var frame: Control = GOLD_FRAME.attach(row)   # 在行构建的最后调用
##   frame.visible = true                          # 由各页面按达成状态控制
class_name GoldFrame
extends RefCounted

## rgb(228, 158, 0)
const COLOR: Color = Color(0.894118, 0.619608, 0.0, 1.0)
## 线宽：1pt
const WIDTH: float = 1.0

## 在 p_row 上挂一个铺满的细框（默认隐藏），返回该节点交给调用方控制显隐。
## 必须在行的子节点都加完之后调用 —— 后加 = 画在最上层。
static func attach(p_row: Control) -> Control:
	var frame := Control.new()
	frame.name = "GoldFrame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false
	frame.draw.connect(_draw_frame.bind(frame))
	p_row.add_child(frame)
	return frame


## 在自身矩形内缘画 1pt 细框（+.5 对齐，缩放后仍是细线）。
static func _draw_frame(p_frame: Control) -> void:
	if p_frame.size.x <= WIDTH + 0.5 or p_frame.size.y <= WIDTH + 0.5:
		return
	var half: float = WIDTH * 0.5
	var rect := Rect2(half, half, p_frame.size.x - WIDTH, p_frame.size.y - WIDTH)
	p_frame.draw_rect(rect, COLOR, false, WIDTH)
