## AchievementsData : RefCounted
## 成就系统的静态成就定义数据。
## 扩展 RefCounted 以支持预加载兼容性（模式来自 MusicGalleryData.gd）。
##   id     — 全局唯一标识（同时作为解锁 key）
##   name   — 成就名称（中文原文，UI 层用 tr() 翻译）
##   todo   — 达成条件描述（中文原文，UI 层用 tr() 翻译）
##   hide   — 是否隐藏成就（未达成时显示 ？？？，需点击揭示）
##   target — 计数型成就的目标次数（0 = 非计数型）
extends RefCounted

# 成就 ID 符号常量 — 供外部引用，避免裸字符串散落（值须与 ENTRIES 的 id 逐字一致）
const ID_ADMISSION: String = "录取通知书"
const ID_GOOD_STUDENT: String = "好学生"
const ID_CAT_LOVER: String = "爱猫人士"
const ID_FIRST_VICTORY: String = "旗开得胜"
const ID_MASTER_PLAN: String = "运筹帷幄"
const ID_TRUE_FRIEND: String = "君子之交"
const ID_SOULMATE: String = "红颜知己"
const ID_TORCH_PASSED: String = "薪火相传"
const ID_NO_MISS: String = "不容遗漏"
const ID_QUICK_WIT: String = "机智过人"
const ID_REGRET: String = "遗憾"
const ID_TOP_SECRET: String = "绝密·启用前"

const ENTRIES: Array[Dictionary] = [
	{"id": "录取通知书", "name": "录取通知书", "todo": "成为火兰山中学学生", "hide": false, "target": 0},
	{"id": "好学生", "name": "好学生", "todo": "累计回答三次课堂抽问并全部答对", "hide": false, "target": 3},
	{"id": "爱猫人士", "name": "爱猫人士", "todo": "累计与猫咪交互十次以上", "hide": false, "target": 10},
	{"id": "旗开得胜", "name": "旗开得胜", "todo": "完成OP1", "hide": true, "target": 0},
	{"id": "运筹帷幄", "name": "运筹帷幄", "todo": "完成OP5", "hide": true, "target": 0},
	{"id": "君子之交", "name": "君子之交", "todo": "与某位协助者协作程度达到满级", "hide": false, "target": 0},
	{"id": "红颜知己", "name": "红颜知己", "todo": "和一名可攻略对象达成恋爱关系", "hide": false, "target": 0},
	{"id": "薪火相传", "name": "薪火相传", "todo": "完成李大泉的谜题", "hide": true, "target": 0},
	{"id": "不容遗漏", "name": "不容遗漏", "todo": "在任意一次行动中收集完全部线索", "hide": false, "target": 0},
	{"id": "机智过人", "name": "机智过人", "todo": "在十分钟内解决任意一次行动", "hide": false, "target": 0},
	{"id": "遗憾", "name": "遗憾", "todo": "达成任意坏结局", "hide": false, "target": 0},
	{"id": "绝密·启用前", "name": "绝密·启用前", "todo": "解锁最终结局并通关", "hide": false, "target": 0},
]
