## MusicGalleryData : RefCounted
## 音乐画廊屏幕的音轨数据。
## desc 字段为曲目简介（中文原文，显示时经 tr() 翻译，条目见 locale/*.po）。
extends RefCounted

const ENTRIES: Array[Dictionary] = [
	# 主题曲
	{"id": "LANSHANProject", "title": "LANSHANProject", "file": "res://assets/music/LANSHANProject.ogg", "desc": "火兰山中学故事的主题曲。"},
	{"id": "LANSHANProjectDemo", "title": "LANSHANProject Demo", "file": "res://assets/music/LANSHANProjectDemo.ogg", "desc": "主题曲的演示版本。"},
	# 主线主要歌曲
	{"id": "FirstDay", "title": "FirstDay", "file": "res://assets/music/FirstDay.ogg", "desc": "新生入学第一天的旋律。"},
	{"id": "Daylight", "title": "Daylight", "file": "res://assets/music/Daylight.ogg", "desc": "阳光明媚的欢快日常。"},
	{"id": "Noon", "title": "Noon", "file": "res://assets/music/Noon.ogg", "desc": "安静而温馨的午后时光。"},
	{"id": "Overnight", "title": "Overnight", "file": "res://assets/music/Overnight.ogg", "desc": "夜深人静的时刻。"},
	{"id": "Overnight2", "title": "Overnight 2", "file": "res://assets/music/Overnight_2_.ogg", "desc": "又一个无眠的夜晚。"},
	{"id": "Autumn", "title": "Autumn", "file": "res://assets/music/Autumn.ogg", "desc": "秋意渐浓的旋律。"},
	{"id": "Night", "title": "Night", "file": "res://assets/music/Night.ogg", "desc": "宁静而悠长的夜晚。"},
	# 主线中期歌曲
	{"id": "DayAfterDay", "title": "Day After Day", "file": "res://assets/music/DayAfterDay.ogg", "desc": "日复一日的日常，总有事情可做。"},
	{"id": "DayAfterDay2", "title": "Day After Day 2", "file": "res://assets/music/DayAfterDay2.ogg", "desc": "日复一日的日常，无事可做。"},
	{"id": "What", "title": "What", "file": "res://assets/music/What.ogg", "desc": "令人尴尬的瞬间。"},
	{"id": "Where", "title": "Where", "file": "res://assets/music/Where.ogg", "desc": "不知何去何从的迷茫。"},
	{"id": "Library", "title": "Library", "file": "res://assets/music/Library.ogg", "desc": "图书馆里的安静时光。"},
	{"id": "Warning", "title": "Warning", "file": "res://assets/music/Warning.ogg", "desc": "情况危急，危险逼近。"},
	# 支线歌曲
	{"id": "Memories", "title": "Memories", "file": "res://assets/music/Memories.ogg", "desc": "往事如潮水般浮现。"},
	{"id": "MySecret", "title": "My Secret", "file": "res://assets/music/MySecret.ogg", "desc": "倾诉心底秘密的旋律。"},
	{"id": "RAIN", "title": "RAIN", "file": "res://assets/music/RAIN.ogg", "desc": "雨声淅沥的旋律。"},
	# 江诗轩的主题曲
	{"id": "MayFlower", "title": "May Flower", "file": "res://assets/music/MayFlower.ogg", "desc": "江诗轩的主题曲。"},
	{"id": "MayFlowerEP", "title": "May Flower EP", "file": "res://assets/music/MayFlowerEP.ogg", "desc": "江诗轩主题曲的 EP 版本。"},
	{"id": "MayFlowerLove", "title": "May Flower (Love Ver.)", "file": "res://assets/music/MayFlower_LoveVersion.ogg", "desc": "江诗轩主题曲的恋爱版本。"},
	{"id": "MayFlowerSingle", "title": "May Flower (Single Ver.)", "file": "res://assets/music/MayFlower_SingleVersion.ogg", "desc": "江诗轩主题曲的单曲版本。"},
	{"id": "MayFlowerNormal", "title": "May Flower (Normal Ver.)", "file": "res://assets/music/MayFlowerNormalVersion.ogg", "desc": "江诗轩主题曲的原版。"},
	{"id": "Rainbow", "title": "Rainbow", "file": "res://assets/music/Rainbow.ogg", "desc": "雨后彩虹般绚烂的旋律。"},
	{"id": "Thought", "title": "Thought", "file": "res://assets/music/Thought.ogg", "desc": "思绪万千的沉思。"},
	# 林子欣的主题曲
	{"id": "Eden", "title": "Eden", "file": "res://assets/music/Eden.ogg", "desc": "林子欣的主题曲。"},
	{"id": "EdenNormalVer", "title": "Eden (Normal Ver.)", "file": "res://assets/music/Eden_NormalVer.ogg", "desc": "林子欣主题曲的原版。"},
	{"id": "Eden_LoveVer", "title": "Eden (Love Ver.)", "file": "res://assets/music/Eden_LoveVersion.ogg", "desc": "林子欣主题曲的恋爱版本。"},
	{"id": "Library_LoveVer", "title": "Library (Love Ver.)", "file": "res://assets/music/Library_LoveVer.ogg", "desc": "图书馆之恋的旋律。"},
	{"id": "Paradise", "title": "Paradise", "file": "res://assets/music/Paradise.ogg", "desc": "宛如乐园般美好的旋律。"},
	{"id": "Jingzhi Rd", "title": "Jingzhi Rd.", "file": "res://assets/music/Jingzhi Rd.ogg", "desc": "Jingzhi Rd 路上的故事。"},
	{"id": "JingzhiRdLib", "title": "Jingzhi Rd. (Library Ver.)", "file": "res://assets/music/Jingzhi Rd.(library version).ogg", "desc": "Jingzhi Rd 的图书馆版本。"},
	{"id": "Qili Rd", "title": "Qili Rd.", "file": "res://assets/music/Qili Rd.ogg", "desc": "Qili Rd 路上的故事。"},
	# 终端主线主题曲
	{"id": "HuolanMount", "title": "Huolan Mount.", "file": "res://assets/music/HuolanMount.ogg", "desc": "火兰山深处的故事。"},
	{"id": "Inside", "title": "Inside", "file": "res://assets/music/Inside.ogg", "desc": "深入内心世界的旋律。"},
	{"id": "Finale", "title": "Finale", "file": "res://assets/music/Finale.ogg", "desc": "最终章的旋律。"},
	{"id": "040", "title": "040", "file": "res://assets/music/040.ogg", "desc": "编号「040」的旋律。"},
	{"id": "Solution", "title": "Solution", "file": "res://assets/music/Solution.ogg", "desc": "寻得解答的时刻。"},
	{"id": "Solution_2", "title": "Solution 2", "file": "res://assets/music/Solutuion_2.ogg", "desc": "另一种解答。"},
	# 石晴雯主线主题曲
	{"id": "illustration", "title": "Illustration", "file": "res://assets/music/illustration.ogg", "desc": "如绘本插图般的旋律。"},
	{"id": "RainingSeason", "title": "Raining Season", "file": "res://assets/music/RainingSeason.ogg", "desc": "雨季里的旋律。"},
	# 各结局主题曲
	{"id": "TheGate2", "title": "The Gate (Final Ver.)", "file": "res://assets/music/The Gate 2.ogg", "desc": "通往结局之门的最终版本。"},
	{"id": "TheGate", "title": "The Gate", "file": "res://assets/music/The Gate.ogg", "desc": "通往结局之门。"},
	{"id": "FalseDawn", "title": "False Dawn", "file": "res://assets/music/FalseDawn.ogg", "desc": "虚假黎明到来之前。"},
	{"id": "Parallel_World", "title": "Parallel World", "file": "res://assets/music/Parallel_World.ogg", "desc": "平行世界的另一种可能。"},
]
