## RollingText : RefCounted
## 给已有 Label 套一层裁剪，换文本时做「码表」式上下滚动 —— 旧字滚出裁剪框，新字从另一侧滚进来。
## 实现照 TabMenu 的白框大标题（_setup_branding_clip + _roll_branding）：
##   var _roll := RollingText.new()
##   _roll.setup(_scene_title)        # 只做一次（样式设好之后）
##   _roll.set_text("新标题", true)    # 切换时调；true = 向上滚（新字从下沿进）
## 只给标题用：描述框保持原来的瞬时切换，不要挂这个。
class_name RollingText
extends RefCounted

## 滚动时长 —— 比场景切换快一档，读起来像"刻度掉了一格"而不是"滑过一屏"。
const ROLL_TIME: float = 0.26

var _clip: Control = null
var _label: Label = null
var _tween: Tween = null


## 把 label 原位包进一个同尺寸的裁剪层。幂等：重复调用不会重复嵌套。
func setup(p_label: Label) -> void:
	if p_label == null or _label == p_label or _clip != null:
		return
	var parent: Node = p_label.get_parent()
	if parent == null:
		return

	var clip := Control.new()
	clip.name = "RollClip"
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(clip)
	# 跟标签原来的位置/尺寸一致，并保持原来的绘制顺序
	clip.position = p_label.position
	clip.size = p_label.size
	parent.move_child(clip, p_label.get_index())

	p_label.reparent(clip, false)
	p_label.position = Vector2.ZERO
	p_label.size = clip.size

	_clip = clip
	_label = p_label


## 换文本。文本没变则不动画；p_animate = false 时直接设（首次显示用）。
## p_up = true 时旧字向上滚出、新字从下沿进入；false 反向。
func set_text(p_text: String, p_up: bool = true, p_animate: bool = true) -> void:
	if _label == null:
		return
	if _label.text == p_text:
		return
	if not p_animate or _clip == null or not _clip.is_inside_tree():
		reset()
		_label.text = p_text
		return

	reset()

	var dist: float = _clip.size.y * (1.0 if p_up else -1.0)
	var outgoing: Label = _label
	var incoming: Label = _label.duplicate() as Label
	incoming.text = p_text
	incoming.position = Vector2(0.0, dist)
	_clip.add_child(incoming)
	_label = incoming

	_tween = _clip.create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_tween.tween_property(outgoing, "position:y", -dist, ROLL_TIME)
	_tween.tween_property(incoming, "position:y", 0.0, ROLL_TIME)
	_tween.set_parallel(false)
	_tween.tween_callback(outgoing.queue_free)


## 立即结束滚动：杀补间、清副本、当前 label 归位（退出场景时调，防止留半程）。
func reset() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if _clip == null or _label == null:
		return
	for c: Node in _clip.get_children():
		if c != _label:
			c.queue_free()
	_label.position.y = 0.0
